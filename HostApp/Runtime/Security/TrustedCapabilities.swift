import Foundation

/// 每个小程序的能力信任清单。
/// 用户在横幅里点「以后都允许」后，该 (appId, module) 记入信任，
/// 之后安全模式下这个能力对这个 app 直接放行——但仍全程记录。
/// 高危能力（critical）不参与信任，永远每次拦。
final class TrustedCapabilities {
    static let shared = TrustedCapabilities()
    private let defaults = UserDefaults.standard
    private let key = "security.trusted"
    /// appId -> Set(module)
    private var cache: [String: Set<String>]
    private let lock = NSLock()

    private init() {
        let raw = defaults.dictionary(forKey: key) as? [String: [String]] ?? [:]
        cache = raw.mapValues { Set($0) }
    }

    func isTrusted(appId: String, module: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return cache[appId]?.contains(module) ?? false
    }

    func trust(appId: String, module: String) {
        lock.lock(); defer { lock.unlock() }
        cache[appId, default: []].insert(module)
        persistLocked()
    }

    func revoke(appId: String, module: String) {
        lock.lock(); defer { lock.unlock() }
        cache[appId]?.remove(module)
        persistLocked()
    }

    func revokeAll(appId: String) {
        lock.lock(); defer { lock.unlock() }
        cache[appId] = nil
        persistLocked()
    }

    func trustedModules(appId: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return (cache[appId] ?? []).sorted()
    }

    private func persistLocked() {
        let raw = cache.mapValues { Array($0) }
        defaults.set(raw, forKey: key)
    }
}
