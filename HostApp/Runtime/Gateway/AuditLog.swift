import Foundation
import os.log

final class AuditLog {
    static let shared = AuditLog()

    private let logger = Logger(subsystem: "com.miniapphost", category: "gateway")
    private let queue = DispatchQueue(label: "gateway.audit", qos: .utility)

    private init() {}

    func record(module: String,
                method: String,
                result: Result<Any, GatewayError>,
                durationMs: Int) {
        let status: String
        switch result {
        case .success: status = "ok"
        case .failure(let err): status = err.code
        }
        queue.async { [logger] in
            logger.log("module=\(module, privacy: .public) method=\(method, privacy: .public) status=\(status, privacy: .public) ms=\(durationMs)")
        }
    }
}
