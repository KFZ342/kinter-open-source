import Foundation

/// 付费小程序购买/结算管理。
///
/// 账号绑定规则（付费应用必须登录才能购买和下载）：
///  - 购买：调用服务端 `POST /api/apps/purchase`，购买记录落在账号（服务端 db.purchases），
///    成功后写本地缓存（卸载重装后凭服务端记录恢复）。
///  - 下载：StoreManager 下载付费 ZIP 时携带 Bearer token，服务端校验已购后才下发。
///  - 平台抽成 7%：按“宿主实收（售价 × 85%）”再抽 7%，开发者应得 = 售价 × 85% × (1-7%)。
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

    // MARK: - 已购凭据（本地缓存）

    private let paidKey = "kinter.purchasedApps.v2"   // [appId: price]
    private let commissionLogKey = "kinter.commissionLog.v1"

    /// 查询是否已购买（免费小程序恒 true；本地缓存 + 服务端记录均视为已购）
    func isPurchased(appId: String, price: Double?) -> Bool {
        guard let price = price, price > 0 else { return true }
        return purchased()[appId] != nil || isOwnedOnServer(appId: appId)
    }

    private func purchased() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: paidKey) as? [String: Double] ?? [:]
    }

    /// 服务端购买记录缓存（登录后同步）
    private func isOwnedOnServer(appId: String) -> Bool {
        let key = "kinter.ownedAppIds.v1"
        let owned = UserDefaults.standard.stringArray(forKey: key) ?? []
        return owned.contains(appId)
    }

    /// 登录成功后同步服务端已购列表（恢复跨设备/重装的购买）
    func syncOwnedFromServer(_ appIds: [String]) {
        UserDefaults.standard.set(appIds, forKey: "kinter.ownedAppIds.v1")
    }

    /// 拉取服务端已购列表并同步本地缓存（登录/启动时调用，失败静默）
    func fetchOwned() {
        guard let token = AuthStore.shared.accessToken else { return }
        let base = (AppSettings.shared.authServerURL ?? KinterAuthManager.defaultServerURL)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/api/apps/owned") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = obj["purchases"] as? [[String: Any]] else { return }
            let ids = list.compactMap { $0["appId"] as? String }
            DispatchQueue.main.async {
                self.syncOwnedFromServer(ids)
            }
        }.resume()
    }

    /// 本地标记购买成功（服务端确认后调用）
    func markPurchasedLocal(appId: String, price: Double) {
        var dict = purchased()
        dict[appId] = price
        UserDefaults.standard.set(dict, forKey: paidKey)
        var owned = UserDefaults.standard.stringArray(forKey: "kinter.ownedAppIds.v1") ?? []
        if !owned.contains(appId) { owned.append(appId) }
        UserDefaults.standard.set(owned, forKey: "kinter.ownedAppIds.v1")
    }

    // MARK: - 服务端购买

    enum PurchaseError: LocalizedError {
        case notLoggedIn
        case server(String)

        var errorDescription: String? {
            switch self {
            case .notLoggedIn:  return "购买付费应用需要登录账号"
            case .server(let s): return "购买失败: \(s)"
            }
        }
    }

    /// 服务端购买（付费应用必须登录；幂等——重复购买直接返回成功）
    func purchase(appId: String, price: Double,
                  completion: @escaping (Result<Void, Error>) -> Void) {
        guard let token = AuthStore.shared.accessToken else {
            completion(.failure(PurchaseError.notLoggedIn))
            return
        }
        let base = (AppSettings.shared.authServerURL ?? KinterAuthManager.defaultServerURL)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/api/apps/purchase") else {
            completion(.failure(PurchaseError.server("服务器地址无效")))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["appId": appId])

        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                if let err = err {
                    completion(.failure(PurchaseError.server(err.localizedDescription)))
                    return
                }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if (200...299).contains(code) {
                    self.markPurchasedLocal(appId: appId, price: price)
                    self.logSettlement(appId: appId, price: price)
                    completion(.success(()))
                } else if code == 401 {
                    completion(.failure(PurchaseError.notLoggedIn))
                } else {
                    let msg = (try? JSONSerialization.jsonObject(with: data ?? Data())
                        as? [String: Any])?["error"] as? String ?? "HTTP \(code)"
                    completion(.failure(PurchaseError.server(msg)))
                }
            }
        }.resume()
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
