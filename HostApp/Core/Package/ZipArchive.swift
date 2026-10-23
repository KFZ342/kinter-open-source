import Foundation
import Compression

/// 最小 ZIP 读取器：支持 STORE（0）与 DEFLATE（8）。
/// 只做读取，不解压到磁盘以外的地方。
struct ZipArchive {
    struct Entry {
        let path: String
        let compressionMethod: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    enum ZipError: LocalizedError {
        case badSignature
        case truncated
        case unsupportedMethod(UInt16)
        case inflateFailed

        var errorDescription: String? {
            switch self {
            case .badSignature:            return "不是有效的 ZIP 文件"
            case .truncated:               return "ZIP 文件不完整"
            case .unsupportedMethod(let m): return "不支持的压缩方式: \(m)"
            case .inflateFailed:           return "解压失败"
            }
        }
    }

    let data: Data
    let entries: [Entry]

    init(data: Data) throws {
        self.data = data
        self.entries = try Self.parseCentralDirectory(data)
    }

    // MARK: - 解析中央目录

    private static func parseCentralDirectory(_ d: Data) throws -> [Entry] {
        // 从尾部找 EOCD (0x06054b50)
        let eocdSig: UInt32 = 0x06054b50
        var eocd: Int = -1
        let minEocd = 22
        guard d.count >= minEocd else { throw ZipError.truncated }
        let scanStart = max(0, d.count - 65557)  // 注释最长 65535
        var i = d.count - minEocd
        while i >= scanStart {
            if d.u32(at: i) == eocdSig { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.badSignature }

        let entryCount = Int(d.u16(at: eocd + 10))
        let cdSize     = Int(d.u32(at: eocd + 12))
        let cdOffset   = Int(d.u32(at: eocd + 16))
        guard cdOffset + cdSize <= d.count else { throw ZipError.truncated }

        var entries: [Entry] = []
        var p = cdOffset
        let cdSig: UInt32 = 0x02014b50
        for _ in 0..<entryCount {
            guard p + 46 <= d.count, d.u32(at: p) == cdSig else { throw ZipError.badSignature }
            let method   = d.u16(at: p + 10)
            let compSize = Int(d.u32(at: p + 20))
            let uncompSize = Int(d.u32(at: p + 24))
            let nameLen  = Int(d.u16(at: p + 28))
            let extraLen = Int(d.u16(at: p + 30))
            let commentLen = Int(d.u16(at: p + 32))
            let localOff = Int(d.u32(at: p + 42))
            guard p + 46 + nameLen <= d.count else { throw ZipError.truncated }
            let name = String(data: d.subdata(in: (p + 46)..<(p + 46 + nameLen)), encoding: .utf8) ?? ""
            entries.append(Entry(path: name,
                                 compressionMethod: method,
                                 compressedSize: compSize,
                                 uncompressedSize: uncompSize,
                                 localHeaderOffset: localOff))
            p += 46 + nameLen + extraLen + commentLen
        }
        return entries
    }

    // MARK: - 提取单个条目

    func extract(_ entry: Entry) throws -> Data {
        let lhSig: UInt32 = 0x04034b50
        let p = entry.localHeaderOffset
        guard p + 30 <= data.count, data.u32(at: p) == lhSig else { throw ZipError.badSignature }
        let nameLen  = Int(data.u16(at: p + 26))
        let extraLen = Int(data.u16(at: p + 28))
        let start = p + 30 + nameLen + extraLen
        let end = start + entry.compressedSize
        guard end <= data.count else { throw ZipError.truncated }
        let raw = data.subdata(in: start..<end)

        switch entry.compressionMethod {
        case 0:
            return raw
        case 8:
            return try Self.inflate(raw, expected: entry.uncompressedSize)
        default:
            throw ZipError.unsupportedMethod(entry.compressionMethod)
        }
    }

    private static func inflate(_ src: Data, expected: Int) throws -> Data {
        guard !src.isEmpty else { return Data() }
        let capacity = max(expected, 1)
        var out = Data(count: capacity)
        let srcCount = src.count
        let decoded: Int = src.withUnsafeBytes { (sp: UnsafeRawBufferPointer) -> Int in
            out.withUnsafeMutableBytes { (op: UnsafeMutableRawBufferPointer) -> Int in
                guard let s = sp.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let o = op.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
                return compression_decode_buffer(o, capacity, s, srcCount, nil, COMPRESSION_ZLIB)
            }
        }
        guard decoded > 0 else { throw ZipError.inflateFailed }
        out.removeSubrange(decoded..<capacity)
        return out
    }
}

// MARK: - 小端读取

private extension Data {
    func u16(at i: Int) -> UInt16 {
        guard i + 2 <= count else { return 0 }
        return UInt16(self[startIndex + i]) | (UInt16(self[startIndex + i + 1]) << 8)
    }
    func u32(at i: Int) -> UInt32 {
        guard i + 4 <= count else { return 0 }
        return UInt32(self[startIndex + i])
            | (UInt32(self[startIndex + i + 1]) << 8)
            | (UInt32(self[startIndex + i + 2]) << 16)
            | (UInt32(self[startIndex + i + 3]) << 24)
    }
}
