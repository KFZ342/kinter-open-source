import Foundation
import UIKit
import os.log

/// 单条能力调用记录（JSONL 落盘，一行一条）。
struct TraceEntry: Codable {
    let sessionId: String
    let timestamp: Date
    let module: String
    let method: String
    let status: String      // ok / blocked / failed
    let appId: String?
    let durationMs: Int?
}

/// 能力调用记录器。
/// 只在安全模式开启时记录，避免正常模式产生额外 I/O。
/// 落盘格式：Documents/SecurityTrace/<sessionId>.jsonl
final class TraceRecorder {
    static let shared = TraceRecorder()

    /// 单文件上限：2MB（约 2 万条），超了滚动到 <sessionId>.1.jsonl
    private static let maxFileBytes = 2 * 1024 * 1024
    /// 最多保留 20 个会话文件，超出按时间删最旧的
    private static let maxSessions = 20
    /// 当前文件已写字节（只在 queue 上读写）
    private var written = 0

    private let queue = DispatchQueue(label: "kinter.trace", qos: .utility)
    private let logger = Logger(subsystem: "com.kinter.host", category: "trace")
    private var currentSessionId: String?
    private var fileHandle: FileHandle?
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private init() {
        // 进后台时把缓冲写入磁盘，避免 App 被挂起/杀掉丢最后几条记录
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: nil) { [weak self] _ in
            self?.flush()
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil, queue: nil) { [weak self] _ in
            self?.flush()
        }
    }

    /// 同步把当前文件句柄的缓冲刷到磁盘。
    func flush() {
        queue.async { [weak self] in
            guard let self = self else { return }
            if let fh = self.fileHandle {
                try? fh.synchronize()
            }
        }
    }

    // MARK: - 目录

    static var traceDir: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SecurityTrace", isDirectory: true)
    }

    private static func fileURL(for sessionId: String) -> URL {
        traceDir.appendingPathComponent("\(sessionId).jsonl")
    }

    // MARK: - 会话

    func beginSession() {
        let sid = SessionSeed.sessionId
        queue.async { [weak self] in
            guard let self = self else { return }
            self.closeHandle()
            self.currentSessionId = sid
            try? FileManager.default.createDirectory(at: Self.traceDir, withIntermediateDirectories: true)
            let url = Self.fileURL(for: sid)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            self.fileHandle = try? FileHandle(forWritingTo: url)
            self.fileHandle?.seekToEndOfFile()
            self.written = Int(self.fileHandle?.offsetInFile ?? 0)
            self.pruneSessions()
            self.logger.log("trace session begin: \(sid, privacy: .public)")
        }
    }

    func endSession() {
        queue.async { [weak self] in
            self?.closeHandle()
            self?.currentSessionId = nil
        }
    }

    private func closeHandle() {
        try? fileHandle?.close()
        fileHandle = nil
    }

    // MARK: - 记录

    func record(module: String, method: String, status: String,
                appId: String? = nil, durationMs: Int? = nil) {
        guard SecurityMode.shared.isEnabled else { return }
        let sid = currentSessionId ?? SessionSeed.sessionId
        let entry = TraceEntry(sessionId: sid,
                               timestamp: Date(),
                               module: module,
                               method: method,
                               status: status,
                               appId: appId,
                               durationMs: durationMs)
        queue.async { [weak self] in
            guard let self = self, let data = try? self.encoder.encode(entry) else { return }
            var line = data
            line.append(0x0A)   // \n
            if let fh = self.fileHandle {
                fh.write(line)
                self.written += line.count
                if self.written >= Self.maxFileBytes { self.rotate(on: sid) }
            } else {
                // 句柄未就绪（如安全模式在会话中途开启），降级为追加写
                let url = Self.fileURL(for: sid)
                try? FileManager.default.createDirectory(at: Self.traceDir, withIntermediateDirectories: true)
                if let h = try? FileHandle(forWritingTo: url) {
                    h.seekToEndOfFile()
                    h.write(line)
                    try? h.close()
                } else {
                    FileManager.default.createFile(atPath: url.path, contents: line)
                }
            }
        }
    }

    // MARK: - 滚动与清理

    /// 当前会话文件写满后滚动到 <sid>.1.jsonl（只保留一代），避免长期使用把 Documents 撑大。
    private func rotate(on sid: String) {
        closeHandle()
        let url = Self.fileURL(for: sid)
        let archived = Self.traceDir.appendingPathComponent("\(sid).1.jsonl")
        try? FileManager.default.removeItem(at: archived)
        try? FileManager.default.moveItem(at: url, to: archived)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: url)
        fileHandle?.seekToEndOfFile()
        written = 0
    }

    /// 只保留最近 maxSessions 个会话记录（含滚动文件，按修改时间删最旧）。
    private func pruneSessions() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: Self.traceDir,
            includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let jsonl = files.filter { $0.pathExtension == "jsonl" }
        guard jsonl.count > Self.maxSessions else { return }
        let sorted = jsonl.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da < db
        }
        for f in sorted.prefix(sorted.count - Self.maxSessions) {
            try? FileManager.default.removeItem(at: f)
        }
    }

    // MARK: - 读取

    /// 读取某会话的全部记录（同步，供统计页使用）。
    func entries(sessionId: String) -> [TraceEntry] {
        let url = Self.fileURL(for: sessionId)
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: 0x0A).compactMap { line in
            try? decoder.decode(TraceEntry.self, from: Data(line))
        }
    }

    /// 全部历史会话 ID（按文件修改时间倒序）。
    func allSessionIds() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: Self.traceDir,
            includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        return files
            .filter { $0.pathExtension == "jsonl" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
            .map { $0.deletingPathExtension().lastPathComponent }
    }
}
