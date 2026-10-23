import Foundation
import UIKit

/// 生成 Web Clip 配置描述文件，让用户把小程序固定到主屏幕。
/// 安装后主屏出现「应用名-Kinter」图标，点击通过 kinter:// URL Scheme 唤起。
enum WebClipGenerator {

    enum ClipError: LocalizedError {
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .writeFailed(let s): return "写入失败: \(s)"
            }
        }
    }

    /// 生成 .mobileconfig 文件，返回本地路径。
    static func generate(for app: InstalledApp) throws -> URL {
        // 读取图标；没有就用首字母生成占位图
        let iconData: Data
        if let iconURL = app.iconURL,
           let data = try? Data(contentsOf: iconURL) {
            iconData = data
        } else {
            guard let placeholder = makePlaceholderIcon(name: app.name) else {
                throw ClipError.writeFailed("无法生成占位图标")
            }
            iconData = placeholder
        }
        let iconBase64 = iconData.base64EncodedString()

        let label = "\(app.name)-Kinter"
        let urlScheme = "kinter://open?appId=\(app.appId)"
        let profileUUID = UUID().uuidString
        let clipUUID = UUID().uuidString

        // 分行 base64，避免单行过长
        let iconLines = iconBase64.chunked(into: 76).joined(separator: "\n")

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>PayloadContent</key>
            <array>
                <dict>
                    <key>FullScreen</key>
                    <true/>
                    <key>Icon</key>
                    <data>
        \(iconLines)
                    </data>
                    <key>IsRemovable</key>
                    <true/>
                    <key>Label</key>
                    <string>\(label)</string>
                    <key>PayloadDescription</key>
                    <string>把「\(app.name)」固定到主屏幕</string>
                    <key>PayloadDisplayName</key>
                    <string>\(label)</string>
                    <key>PayloadIdentifier</key>
                    <string>com.kinter.webclip.\(clipUUID)</string>
                    <key>PayloadType</key>
                    <string>com.apple.webClip.managed</string>
                    <key>PayloadUUID</key>
                    <string>\(clipUUID)</string>
                    <key>PayloadVersion</key>
                    <integer>1</integer>
                    <key>URL</key>
                    <string>\(urlScheme)</string>
                </dict>
            </array>
            <key>PayloadDescription</key>
            <string>为「\(app.name)」创建主屏幕快捷方式</string>
            <key>PayloadDisplayName</key>
            <string>\(label)</string>
            <key>PayloadIdentifier</key>
            <string>com.kinter.profile.\(profileUUID)</string>
            <key>PayloadOrganization</key>
            <string>Kinter</string>
            <key>PayloadRemovalDisallowed</key>
            <false/>
            <key>PayloadType</key>
            <string>Configuration</string>
            <key>PayloadUUID</key>
            <string>\(profileUUID)</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
        </dict>
        </plist>
        """

        guard let data = plist.data(using: .utf8) else {
            throw ClipError.writeFailed("编码失败")
        }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kinter-\(sanitize(app.name)).mobileconfig")
        do {
            try data.write(to: tmp, options: .atomic)
        } catch {
            throw ClipError.writeFailed(error.localizedDescription)
        }
        return tmp
    }

    /// 用应用名首字生成 512x512 占位图标（圆角矩形 + 白字）。
    private static func makePlaceholderIcon(name: String) -> Data? {
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        let bg = UIColor.systemBlue

        let firstChar = String(name.prefix(1))

        let image = renderer.image { ctx in
            bg.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()

            let font = UIFont.systemFont(ofSize: 280, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white
            ]
            let text = firstChar as NSString
            let textSize = text.size(withAttributes: attrs)
            let rect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: rect, withAttributes: attrs)
        }

        return image.pngData()
    }

    /// 文件名里去掉非法字符
    private static func sanitize(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return name.components(separatedBy: illegal).joined(separator: "_")
    }
}

private extension String {
    func chunked(into size: Int) -> [String] {
        var result: [String] = []
        var index = startIndex
        while index < endIndex {
            let next = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(String(self[index..<next]))
            index = next
        }
        return result
    }
}
