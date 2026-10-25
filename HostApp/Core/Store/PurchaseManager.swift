import Foundation

/// 付费小程序购买/结算管理。
///
/// 支付通道说明：
///  - 当前阶段（TestFlight / 商店框架期）：已购凭据持久化到 UserDefaults，
///    由 PurchaseManager 统一查询；真实支付（Apple IAP / Advanced Commerce API）
///    接入后，只需替换 `purchase(appId:)` 的实现（走 StoreKit 2），凭据层保持不变。
///  - 平台抽成 7%：按“宿主实收（售价 × 85%）”再抽 7% 作为平台佣金，
///    开发者应得 = 售价 × 85% × (1 - 7%)。
final class PurchaseManager {
    static let shared = PurchaseManager()
    private init() {}

    // MARK: - 平台抽成（商业口径，可调）

    /// 平台抽成比例：7%
    static let platformCommissionRate: Double = 0.07
    /// Apple 抽成后宿主实收比例（Mini Apps Partner Program：85% 归宿主）
    static let hostShareRate: Double = 0.85

    /// 开发者最终应得金额（售价 × 85% × 93%）
    static func developerPayout(price: Double) -> Double {
        price * hostShareRate * (1 - platformCommissionRate)
    }

    /// 平台佣金（售价 × 85% × 7%）
    static func platformCommission(price: Double) -> Double {
        price * hostShareRate * platformCommissionRate
    }

    // MARK: - 已购凭据

    private let paidKey = "kinter.purchasedApps.v1"   // [appId: price]
    private let commissionLogKey = "kinter.commissionLog.v1"

    /// 查询是否已购买（免费小程序恒 true）
    func isPurchased(appId: String, price: Double?) -> Bool {
        guard let price = price, price > 0 else { return true }
        return purchased()[appId] != nil
    }

    /// 记录一次购买（真实 IAP 接入前的内部解锁入口；IAP 接入后改由 StoreKit 回调调用）
    func markPurchased(appId: String, price: Double) {
        var dict = purchased()
        dict[appId] = price
        UserDefaults.standard.set(dict, forKey: paidKey)
    }

    private func purchased() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: paidKey) as? [String: Double] ?? [:]
    }

    // MARK: - 结算流水（对账用）

    struct SettlementRecord: Codable {
        let appId: String
        let price: Double
        let commission: Double      // 平台佣金
        let payout: Double          // 开发者应得
        let date: Date
    }

    /// 登记一笔结算流水（平台对账/审计）
    func logSettlement(appId: String, price: Double) {
        let record = SettlementRecord(
            appId: appId,
            price: price,
            commission: Self.platformCommission(price: price),
            payout: Self.developerPayout(price: price),
            date: Date()
        )
        var log = settlementLog()
        log.append(record)
        if log.count > 200 { log.removeFirst(log.count - 200) }
        if let data = try? JSONEncoder().encode(log) {
            UserDefaults.standard.set(data, forKey: commissionLogKey)
        }
    }

    func settlementLog() -> [SettlementRecord] {
        guard let data = UserDefaults.standard.data(forKey: commissionLogKey),
              let list = try? JSONDecoder().decode([SettlementRecord].self, from: data) else {
            return []
        }
        return list
    }
}
