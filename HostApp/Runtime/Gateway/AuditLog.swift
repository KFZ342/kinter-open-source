import Foundation
import os.log

final class AuditLog {
    static let shared = AuditLog()

    private let logger = Logger(subsystem: "com.miniapphost", category: "gateway")
    private let queue = DispatchQueue(label: "gateway.audit", qos: .utility)

    // MARK: - 落盘（环形缓冲）

    private let fileQueue = DispatchQueue(label: "gateway.audit.file", qos: .utility)
    private let maxLines = 2000

    static var logFileURL: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("AuditLog", isDirectory: true)
                   .appendingPathComponent("gateway.log")
    }

    private init() {}

    private func appendToFile(_ line: String) {
        fileQueue.async { [weak self] in
            guard let self = self else { return }
            let url = Self.logFileURL
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            // 环形裁剪：超过上限时保留后一半
            if let existing = try? String(contentsOf: url, encoding: .utf8) {
                let lines = existing.split(separator: "\n", omittingEmptySubsequences: true)
                if lines.count >= self.maxLines {
                    let keep = lines.suffix(self.maxLines / 2).joined(separator: "\n") + "\n"
                    try? keep.write(to: url, atomically: true, encoding: .utf8)
                }
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                if let data = (line + "\n").data(using: .utf8) {
                    handle.write(data)
                }
                try? handle.close()
            } else {
                try? (line + "\n").write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    func record(module: String,
                method: String,
                result: Result<Any, GatewayError>,
                durationMs: Int) {
        let status: String
        switch result {
        case .success: status = "ok"
        case .failure(let err): status = err.code
        }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) module=\(module) method=\(method) status=\(status) ms=\(durationMs)"

        queue.async { [logger] in
            logger.log("module=\(module, privacy: .public) method=\(method, privacy: .public) status=\(status, privacy: .public) ms=\(durationMs)")
        }
        appendToFile(line)
    }
}
