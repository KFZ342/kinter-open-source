import Foundation
import CryptoKit

/// 安装前预览信息。只读，不写磁盘。
struct PackagePreview {
    let manifest: MiniAppManifest
    /// 高危能力（critical 档）：通讯录、健康、麦克风等
    let sensitiveCapabilities: [String]
    /// 中危能力（standard 档）：相机、定位、相册等
    let standardCapabilities: [String]
    /// 普通能力（L0 / network 档）
    let normalCapabilities: [String]
    /// 未知能力（网关会拒绝）
    let unknownCapabilities: [String]

    var totalCapabilityCount: Int {
        sensitiveCapabilities.count + standardCapabilities.count + normalCapabilities.count
    }
}

/// 安装前检查器：从 ZIP 里只提取 manifest.json 并解析，不做任何落盘。
enum PackageInspector {
    static func inspect(zipURL: URL) throws -> PackagePreview {
        let data: Data
        do {
            data = try Data(contentsOf: zipURL)
        } catch {
            throw InstallError.zipInvalid("无法读取文件")
        }

        let archive: ZipArchive
        do {
            archive = try ZipArchive(data: data)
        } catch {
            throw InstallError.zipInvalid(error.localizedDescription)
        }

        guard let mEntry = archive.entries.first(where: { $0.path.lowercased().hasSuffix("manifest.json") }) else {
            throw InstallError.missingManifest
        }

        let manifestData: Data
        do {
            manifestData = try archive.extract(mEntry)
        } catch {
            throw InstallError.invalidManifest(error.localizedDescription)
        }

        let manifest: MiniAppManifest
        do {
            manifest = try ManifestParser.parse(data: manifestData)
        } catch {
            throw InstallError.invalidManifest("\(error)")
        }

        var sensitive: [String] = []
        var standard: [String] = []
        var normal: [String] = []
        var unknown: [String] = []

        for cap in (manifest.capabilities ?? [:]).keys.sorted() {
            guard PermissionCatalog.isKnown(cap) else {
                unknown.append(cap)
                continue
            }
            if let tier = SecurityPolicy.tier(of: cap) {
                switch tier {
                case .critical: sensitive.append(cap)
                case .standard: standard.append(cap)
                case .network:  normal.append(cap)
                case .benign:   normal.append(cap)
                }
            } else {
                normal.append(cap)
            }
        }

        return PackagePreview(
            manifest: manifest,
            sensitiveCapabilities: sensitive,
            standardCapabilities: standard,
            normalCapabilities: normal,
            unknownCapabilities: unknown
        )
    }
}

// MARK: - 应用签名

/// 一个应用包的开发者签名。
///
/// 签名对象是整个包的「文件清单摘要」：每个文件按相对路径排序，取 SHA256，
/// 拼成 `路径\0摘要\n` 后再 SHA256 一次。签名只覆盖摘要，所以任何文件被改动一位，
/// 校验都会失败——签名不只在装的时候看一眼，而是在**每次打开**时重新算。
///
/// 签名文件放在包根目录 `signature.json`：
/// ```json
/// {"algorithm":"ed25519","developerId":"com.example.dev",
///  "publicKey":"<32 字节 raw 公钥 base64>","signature":"<base64>","signedAt":"..."}
/// ```
enum PackageSignature {
    enum Status {
        /// 设置里关掉了「要求开发者签名」
        case unenforced
        /// 宿主自带 / 本机生成
        case firstParty
        /// 签名有效，且开发者已在本机信任名单
        case trusted(developerId: String)
        /// 签名有效，但开发者没被信任。reviewNote 是第三方模型审查结论（可为空）
        case untrusted(developerId: String, publicKeyBase64: String, reviewNote: String?)
        /// 没有 signature.json
        case unsigned
        /// 有签名但校验不过（文件被改、公钥/签名格式错误）
        case invalid(String)
    }

    static let fileName = "signature.json"

    struct SignatureFile: Decodable {
        let algorithm: String
        let developerId: String
        let publicKey: String
        let signature: String
        let signedAt: String?
        /// 第三方模型安全审查记录（一段 JSON 字符串，字节原样参与验签）
        let review: String?
        /// 对 review 的 sha256 做的签名
        let reviewSignature: String?
    }

    /// review 里给用户看的那几项
    struct ReviewRecord: Decodable {
        let model: String
        let summary: String?
        let risk: String?
    }

    /// 打开前判定。注意：这里会读文件算摘要，别在主线程调用。
    static func status(for app: InstalledApp) -> Status {
        if !AppSettings.shared.requireDeveloperSignature { return .unenforced }
        if app.isFirstParty { return .firstParty }
        return verify(directory: app.directory)
    }

    static func verify(directory: URL) -> Status {
        let sigURL = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: sigURL) else { return .unsigned }
        guard let file = try? JSONDecoder().decode(SignatureFile.self, from: data),
              file.algorithm.lowercased() == "ed25519",
              let pubRaw = Data(base64Encoded: file.publicKey),
              let sigRaw = Data(base64Encoded: file.signature),
              let digest = digest(in: directory) else {
            return .invalid("签名文件格式不正确")
        }
        let key: Curve25519.Signing.PublicKey
        do {
            key = try Curve25519.Signing.PublicKey(rawRepresentation: pubRaw)
        } catch {
            return .invalid("公钥无效")
        }
        guard key.isValidSignature(sigRaw, for: digest) else {
            return .invalid("签名与本机文件不匹配，安装包可能被改动过")
        }

        // 审查记录跟着签名一起防篡改：改了记录，签名对不上
        var reviewNote: String?
        if let payload = file.review, let sigB64 = file.reviewSignature {
            guard let reviewSig = Data(base64Encoded: sigB64) else {
                return .invalid("安全审查记录格式不对")
            }
            let reviewDigest = SHA256.hash(data: Data(payload.utf8))
            guard key.isValidSignature(reviewSig, for: Data(reviewDigest)) else {
                return .invalid("安全审查记录被改动过")
            }
            if let data = payload.data(using: .utf8),
               let record = try? JSONDecoder().decode(ReviewRecord.self, from: data) {
                let summary = record.summary?.isEmpty == false ? record.summary! : "通过"
                reviewNote = "第三方模型（\(record.model)）审查：\(summary)"
            }
        }

        if TrustedDevelopers.shared.isTrusted(developerId: file.developerId,
                                              publicKey: file.publicKey) {
            return .trusted(developerId: file.developerId)
        }
        return .untrusted(developerId: file.developerId,
                          publicKeyBase64: file.publicKey,
                          reviewNote: reviewNote)
    }

    /// 计算包摘要。规则必须与 `Tools/sign_app.py` 完全一致。
    static func digest(in directory: URL) -> Data? {
        let fm = FileManager.default
        let root = directory.standardizedFileURL.path
        guard let en = fm.enumerator(at: directory,
                                     includingPropertiesForKeys: [.isRegularFileKey]) else {
            return nil
        }
        var rels: [String] = []
        for case let url as URL in en {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(root + "/") else { continue }
            let rel = String(path.dropFirst(root.count + 1))
            if rel == fileName { continue }
            rels.append(rel)
        }
        var canonical = Data()
        // 按 UTF-8 字节排序，保证和 Tools/sign_app.py 算出来的顺序一致
        let ordered = rels.sorted { lhs, rhs in
            Array(lhs.utf8).lexicographicallyPrecedes(Array(rhs.utf8))
        }
        for rel in ordered {
            let fileURL = directory.appendingPathComponent(rel)
            guard let body = try? Data(contentsOf: fileURL) else { return nil }
            let hex = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
            canonical.append(contentsOf: Array(rel.utf8))
            canonical.append(0x00)
            canonical.append(contentsOf: Array(hex.utf8))
            canonical.append(0x0A)
        }
        return Data(SHA256.hash(data: canonical))
    }
}

/// 本机信任的开发者名单：developerId → base64 公钥。
/// 首次遇到「签名有效但没信任」的包会问一次，用户点「信任并打开」后写入这里。
final class TrustedDevelopers {
    static let shared = TrustedDevelopers()
    private let defaults = UserDefaults.standard
    private let key = "signature.trustedDevelopers"
    private var cache: [String: String]
    private let lock = NSLock()

    private init() {
        cache = (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
    }

    func isTrusted(developerId: String, publicKey: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return cache[developerId] == publicKey
    }

    func trust(developerId: String, publicKey: String) {
        lock.lock(); defer { lock.unlock() }
        cache[developerId] = publicKey
        defaults.set(cache, forKey: key)
    }

    func revoke(developerId: String) {
        lock.lock(); defer { lock.unlock() }
        cache[developerId] = nil
        defaults.set(cache, forKey: key)
    }

    func revokeAll() {
        lock.lock(); defer { lock.unlock() }
        cache.removeAll()
        defaults.set(cache, forKey: key)
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return cache.count
    }

    var developerIds: [String] {
        lock.lock(); defer { lock.unlock() }
        return cache.keys.sorted()
    }
}
