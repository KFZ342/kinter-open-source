import Foundation

/// GitHub REST API 最小封装。
final class GitHubAPI {
    static let shared = GitHubAPI()
    private init() {}

    private let baseURL = "https://api.github.com"

    enum APIError: LocalizedError {
        case noToken
        case httpError(Int, String)
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .noToken:                return "未登录"
            case .httpError(let c, let m): return "GitHub API 错误 (\(c)): \(m)"
            case .parseError(let s):      return "响应解析失败: \(s)"
            }
        }
    }

    // MARK: - 基础请求

    private func request(_ method: String,
                         path: String,
                         body: [String: Any]? = nil,
                         completion: @escaping (Result<Any, Error>) -> Void) {
        guard let token = AuthStore.shared.accessToken else {
            completion(.failure(APIError.noToken))
            return
        }
        guard let url = URL(string: baseURL + path) else {
            completion(.failure(APIError.parseError("URL 无效")))
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.timeoutInterval = 30

        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                if let err = err {
                    completion(.failure(err))
                    return
                }
                guard let http = resp as? HTTPURLResponse else {
                    completion(.failure(APIError.parseError("无 HTTP 响应")))
                    return
                }
                let data = data ?? Data()
                // 204 无内容
                if http.statusCode == 204 {
                    completion(.success([:]))
                    return
                }
                let json = (try? JSONSerialization.jsonObject(with: data)) ?? [:]
                if (200...299).contains(http.statusCode) {
                    completion(.success(json))
                } else {
                    let msg = (json as? [String: Any])?["message"] as? String
                        ?? String(data: data, encoding: .utf8)
                        ?? ""
                    completion(.failure(APIError.httpError(http.statusCode, String(msg.prefix(200)))))
                }
            }
        }.resume()
    }

    // MARK: - 用户

    /// 验证 token 并返回当前登录名。
    func getLogin(completion: @escaping (Result<String, Error>) -> Void) {
        request("GET", path: "/user") { result in
            switch result {
            case .success(let json):
                if let dict = json as? [String: Any], let login = dict["login"] as? String {
                    completion(.success(login))
                } else {
                    completion(.failure(APIError.parseError("缺少 login 字段")))
                }
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }

    // MARK: - 仓库

    /// 检查仓库是否存在（当前用户私有）。
    func repoExists(name: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        getLogin { loginResult in
            switch loginResult {
            case .failure(let err):
                completion(.failure(err))
            case .success(let login):
                self.request("GET", path: "/repos/\(login)/\(name)") { result in
                    switch result {
                    case .success:
                        completion(.success(true))
                    case .failure(let err):
                        // 404 表示不存在，其他错误上抛
                        if case APIError.httpError(404, _) = err {
                            completion(.success(false))
                        } else {
                            completion(.failure(err))
                        }
                    }
                }
            }
        }
    }

    /// 创建公开仓库，自动初始化 README。
    func createRepo(name: String, description: String,
                    completion: @escaping (Result<String, Error>) -> Void) {
        let body: [String: Any] = [
            "name": name,
            "description": description,
            "private": false,
            "auto_init": true,
            "has_issues": false,
            "has_wiki": false,
            "has_projects": false
        ]
        request("POST", path: "/user/repos", body: body) { result in
            switch result {
            case .success(let json):
                if let dict = json as? [String: Any], let fullName = dict["full_name"] as? String {
                    completion(.success(fullName))
                } else {
                    completion(.failure(APIError.parseError("缺少 full_name")))
                }
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }

    // MARK: - 文件

    /// 获取文件当前的 sha（更新已存在文件时需要）。
    private func getFileSHA(owner: String, repo: String, path: String,
                            completion: @escaping (String?) -> Void) {
        request("GET", path: "/repos/\(owner)/\(repo)/contents/\(path)") { result in
            switch result {
            case .success(let json):
                if let dict = json as? [String: Any], let sha = dict["sha"] as? String {
                    completion(sha)
                } else {
                    completion(nil)
                }
            case .failure:
                completion(nil)
            }
        }
    }

    /// 上传或更新文件。内容会自动 base64 编码。
    func putFile(owner: String, repo: String, path: String,
                 content: Data, message: String,
                 completion: @escaping (Result<Void, Error>) -> Void) {
        getFileSHA(owner: owner, repo: repo, path: path) { sha in
            var body: [String: Any] = [
                "message": message,
                "content": content.base64EncodedString()
            ]
            if let sha = sha {
                body["sha"] = sha
            }
            self.request("PUT", path: "/repos/\(owner)/\(repo)/contents/\(path)", body: body) { result in
                switch result {
                case .success:
                    completion(.success(()))
                case .failure(let err):
                    completion(.failure(err))
                }
            }
        }
    }

    // MARK: - Pages

    /// 开启 GitHub Pages，源为 main 分支根目录。
    func enablePages(owner: String, repo: String,
                     completion: @escaping (Result<String, Error>) -> Void) {
        let body: [String: Any] = [
            "source": ["branch": "main", "path": "/"]
        ]
        request("POST", path: "/repos/\(owner)/\(repo)/pages", body: body) { result in
            switch result {
            case .success(let json):
                if let dict = json as? [String: Any], let url = dict["html_url"] as? String {
                    completion(.success(url))
                } else {
                    completion(.success("https://\(owner).github.io/\(repo)/"))
                }
            case .failure(let err):
                // 409 表示 Pages 已开启
                if case APIError.httpError(409, _) = err {
                    completion(.success("https://\(owner).github.io/\(repo)/"))
                } else {
                    completion(.failure(err))
                }
            }
        }
    }
}
