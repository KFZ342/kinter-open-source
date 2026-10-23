import Foundation

/// 应用级全局数据存储。每个小程序实例持有独立的一份。
/// 生命周期与小程序运行窗口一致，关闭时自动清空。
/// 支持任意 JSON 兼容类型（字符串、数字、布尔、数组、字典）。
final class AppStore {

    private var storage: [String: Any] = [:]
    private let lock = NSLock()

    /// 设置值。nil 表示删除。
    func set(_ key: String, value: Any?) {
        lock.lock(); defer { lock.unlock() }
        if let value = value {
            storage[key] = value
        } else {
            storage.removeValue(forKey: key)
        }
    }

    /// 读取值。
    func get(_ key: String) -> Any? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    /// 读取全部。
    func all() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    /// 清空。
    func clear() {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll()
    }
}
