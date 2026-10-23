import AVFoundation

final class AudioPlayerProvider: NSObject, CapabilityProvider, AVAudioPlayerDelegate {
    static var capability: String { "audio" }
    static var level: CapabilityLevel { .l0 }
    required override init() { super.init() }

    private var player: AVAudioPlayer?
    private var completion: ((Result<Any, GatewayError>) -> Void)?

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        switch method {
        case "play":
            guard let path = params["path"] as? String else {
                completion(.failure(.invalidParams("path 必填")))
                return
            }
            let url: URL
            if path.hasPrefix("http") {
                completion(.failure(.invalidParams("暂不支持网络音频，请先下载到本地")))
                return
            } else {
                url = URL(fileURLWithPath: path)
            }
            guard FileManager.default.fileExists(atPath: url.path) else {
                completion(.failure(.invalidParams("文件不存在")))
                return
            }
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default, options: [.duckOthers])
                try session.setActive(true)
                let p = try AVAudioPlayer(contentsOf: url)
                p.delegate = self
                let ok = p.play()
                self.player = p
                if !ok {
                    completion(.failure(.providerError("播放失败")))
                } else {
                    completion(.success(["ok": true, "duration": p.duration]))
                }
            } catch {
                completion(.failure(.providerError(error.localizedDescription)))
            }
        case "pause":
            player?.pause()
            completion(.success(["ok": true]))
        case "resume":
            let ok = player?.play() ?? false
            completion(.success(["ok": ok]))
        case "stop":
            player?.stop()
            player = nil
            completion(.success(["ok": true]))
        case "isPlaying":
            completion(.success(["playing": player?.isPlaying ?? false]))
        case "currentTime":
            completion(.success(["time": player?.currentTime ?? 0]))
        case "seek":
            let t = params["time"] as? TimeInterval ?? 0
            player?.currentTime = t
            completion(.success(["ok": true]))
        default:
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        self.player = nil
    }
}
