import Foundation

/// 最小 ZIP 写入器。只支持 STORE（不压缩），适合小程序包。
/// 小程序包本身就不大，不压缩也没问题。
enum ZipWriter {

    struct Entry {
        let path: String
        let data: Data
    }

    /// 把一组文件打成 ZIP。
    static func build(entries: [Entry]) -> Data {
        var output = Data()
        var centralDirectory = Data()

        for entry in entries {
            let nameData = entry.path.data(using: .utf8) ?? Data()
            let crc = crc32(entry.data)
            let offset = UInt32(output.count)

            // 本地文件头
            output.append(u32(0x04034b50))          // 签名
            output.append(u16(20))                   // 版本需要
            output.append(u16(0))                    // 标志
            output.append(u16(0))                    // 压缩方法：STORE
            output.append(u16(0))                    // 修改时间
            output.append(u16(0))                    // 修改日期
            output.append(u32(crc))                  // CRC32
            output.append(u32(UInt32(entry.data.count)))  // 压缩后大小
            output.append(u32(UInt32(entry.data.count)))  // 原始大小
            output.append(u16(UInt16(nameData.count)))    // 文件名长度
            output.append(u16(0))                    // 扩展字段长度
            output.append(nameData)
            output.append(entry.data)

            // 中央目录条目
            centralDirectory.append(u32(0x02014b50))  // 签名
            centralDirectory.append(u16(20))          // 创建版本
            centralDirectory.append(u16(20))          // 需要版本
            centralDirectory.append(u16(0))           // 标志
            centralDirectory.append(u16(0))           // 压缩方法
            centralDirectory.append(u16(0))           // 时间
            centralDirectory.append(u16(0))           // 日期
            centralDirectory.append(u32(crc))
            centralDirectory.append(u32(UInt32(entry.data.count)))
            centralDirectory.append(u32(UInt32(entry.data.count)))
            centralDirectory.append(u16(UInt16(nameData.count)))
            centralDirectory.append(u16(0))           // 扩展字段
            centralDirectory.append(u16(0))           // 注释
            centralDirectory.append(u16(0))           // 磁盘号
            centralDirectory.append(u16(0))           // 内部属性
            centralDirectory.append(u32(0))           // 外部属性
            centralDirectory.append(u32(offset))      // 本地头偏移
            centralDirectory.append(nameData)
        }

        let cdOffset = UInt32(output.count)
        output.append(centralDirectory)

        // EOCD
        output.append(u32(0x06054b50))
        output.append(u16(0))
        output.append(u16(0))
        output.append(u16(UInt16(entries.count)))
        output.append(u16(UInt16(entries.count)))
        output.append(u32(UInt32(centralDirectory.count)))
        output.append(u32(cdOffset))
        output.append(u16(0))  // 注释长度

        return output
    }

    // MARK: - 工具

    private static func u16(_ v: UInt16) -> Data {
        var x = v.littleEndian
        return Data(bytes: &x, count: 2)
    }

    private static func u32(_ v: UInt32) -> Data {
        var x = v.littleEndian
        return Data(bytes: &x, count: 4)
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            table[i] = c
        }
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}
