import ActivityKit
import Foundation

/// 实时活动能力。
/// 支持启动、更新、结束、列出、读状态，带深链与过期时间。
final class LiveActivityProvider: CapabilityProvider, AppContextInjectable {
    static var capability: String { "liveActivity" }
    static var level: CapabilityLevel { .l2 }
    required init() {}

    var appId: String?
    private var currentIds: [String: String] = [:]

    func invoke(method: String, params: [String: Any],
                completion: @escaping (Result<Any, GatewayError>) -> Void) {
        switch method {
        case "start":      start(params, completion)
        case "update":     update(params, completion)
        case "end":        end(params, completion)
        case "list":       list(completion)
        case "getState":   getState(completion)
        case "isSupported":
            completion(.success(["supported": ActivityAuthorizationInfo().areActivitiesEnabled]))
        default:
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
        }
    }

    // MARK: - start

    private func start(_ params: [String: Any],
                       _ completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            completion(.failure(.unsupported("实时活动未启用或设备不支持"))); return
        }
        guard let aid = appId, !aid.isEmpty else {
            completion(.failure(.providerError("缺少 appId"))); return
        }

        if let oldId = currentIds[aid],
           let old = Activity<KinterActivityAttributes>.activities.first(where: { $0.id == oldId }) {
            Task { await old.end(nil, dismissalPolicy: .immediate) }
            currentIds.removeValue(forKey: aid)
        }

        let appName = params["appName"] as? String ?? "小程序"
        let attrs = KinterActivityAttributes(appId: aid, appName: appName)

        let state = makeState(params, fallback: nil)
        let staleDate = (params["staleAfter"] as? Double).map { Date().addingTimeInterval($0) }
        let content = ActivityContent(state: state, staleDate: staleDate)

        do {
            let activity = try Activity.request(
                attributes: attrs,
                content: content,
                pushType: nil
            )
            currentIds[aid] = activity.id
            completion(.success(["ok": true, "activityId": activity.id]))
        } catch {
            completion(.failure(.providerError("启动失败: \(error.localizedDescription)")))
        }
    }

    // MARK: - update

    private func update(_ params: [String: Any],
                        _ completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard let aid = appId,
              let act = currentActivity(for: aid) else {
            completion(.failure(.providerError("没有正在进行的实时活动"))); return
        }
        let state = makeState(params, fallback: act.content.state)
        let staleDate = (params["staleAfter"] as? Double).map { Date().addingTimeInterval($0) }
        let content = ActivityContent(state: state, staleDate: staleDate)
        Task {
            await act.update(content)
            DispatchQueue.main.async {
                completion(.success(["ok": true]))
            }
        }
    }

    // MARK: - end

    private func end(_ params: [String: Any],
                     _ completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard let aid = appId,
              let act = currentActivity(for: aid) else {
            completion(.success(["ok": true, "skipped": true])); return
        }
        currentIds.removeValue(forKey: aid)

        // 可传最终状态；不传则用当前状态
        let finalState = makeState(params, fallback: act.content.state)
        let content = ActivityContent(state: finalState, staleDate: nil)

        let policy: ActivityUIDismissalPolicy
        switch params["dismissPolicy"] as? String {
        case "immediate":   policy = .immediate
        case "default":     policy = .default
        default:
            let secs = params["dismissAfter"] as? Double ?? 3
            policy = .after(Date().addingTimeInterval(secs))
        }

        Task {
            await act.end(content, dismissalPolicy: policy)
            DispatchQueue.main.async {
                completion(.success(["ok": true]))
            }
        }
    }

    // MARK: - list / getState

    private func list(_ completion: @escaping (Result<Any, GatewayError>) -> Void) {
        let all = Activity<KinterActivityAttributes>.activities
            .filter { $0.attributes.appId == (appId ?? "") }
            .map { act -> [String: Any] in
                [
                    "activityId": act.id,
                    "appId": act.attributes.appId,
                    "appName": act.attributes.appName,
                    "state": stateToDict(act.content.state),
                    "isStale": act.content.staleDate.map { $0 < Date() } ?? false
                ]
            }
        completion(.success(["activities": all, "count": all.count]))
    }

    private func getState(_ completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard let aid = appId, let act = currentActivity(for: aid) else {
            completion(.success(["exists": false])); return
        }
        completion(.success([
            "exists": true,
            "activityId": act.id,
            "state": stateToDict(act.content.state)
        ]))
    }

    // MARK: - 工具

    private func currentActivity(for aid: String) -> Activity<KinterActivityAttributes>? {
        if let id = currentIds[aid],
           let act = Activity<KinterActivityAttributes>.activities.first(where: { $0.id == id }) {
            return act
        }
        // 恢复：App 重启后内存丢失，但 Activity 仍在
        if let act = Activity<KinterActivityAttributes>.activities.first(where: { $0.attributes.appId == aid }) {
            currentIds[aid] = act.id
            return act
        }
        return nil
    }

    private func makeState(_ params: [String: Any],
                           fallback: KinterActivityAttributes.ContentState?) -> KinterActivityAttributes.ContentState {
        KinterActivityAttributes.ContentState(
            title: params["title"] as? String ?? fallback?.title ?? "进行中",
            subtitle: params["subtitle"] as? String ?? fallback?.subtitle,
            progress: clampProgress(params["progress"]) ?? fallback?.progress,
            status: params["status"] as? String ?? fallback?.status,
            deepLink: params["deepLink"] as? String ?? fallback?.deepLink
        )
    }

    private func clampProgress(_ raw: Any?) -> Double? {
        guard let v = raw as? Double else { return nil }
        return max(0, min(1, v))
    }

    private func stateToDict(_ s: KinterActivityAttributes.ContentState) -> [String: Any] {
        var d: [String: Any] = ["title": s.title]
        if let v = s.subtitle { d["subtitle"] = v }
        if let v = s.progress { d["progress"] = v }
        if let v = s.status { d["status"] = v }
        if let v = s.deepLink { d["deepLink"] = v }
        return d
    }
}
