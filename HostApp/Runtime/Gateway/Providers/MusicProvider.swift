import AVFoundation

/// 音乐播放能力（AVPlayer）。
/// 与 audio（AVAudioPlayer，本地文件）互补：支持本地文件与 http(s) 远程 URL、
/// 循环播放、音量调节、完整播放状态查询。
/// 后台播放：宿主 Info.plist 已声明 UIBackgroundModes = [audio]。
final class MusicProvider: CapabilityProvider {
    static var capability: String { "music" }
    static var level: CapabilityLevel { .l0 }
    required init() {}

    private var player: AVPlayer?
    private var loop = false
    private var endObserver: NSObjectProtocol?

    deinit {
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
    }

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        switch method {
        case "play":
            handlePlay(params: params, completion: completion)

        case "pause":
            player?.pause()
            completion(.success(["ok": true]))

        case "resume":
            guard let player else {
                completion(.failure(.providerError("尚未播放，请先 playMusic")))
                return
            }
            player.play()
            completion(.success(["ok": true]))

        case "stop":
            player?.pause()
            player = nil
            loop = false
            if let o = endObserver {
                NotificationCenter.default.removeObserver(o)
                endObserver = nil
            }
            completion(.success(["ok": true]))

        case "seek":
            guard let player else {
                completion(.failure(.providerError("尚未播放")))
                return
            }
            let t = params["position"] as? TimeInterval ?? 0
            player.seek(to: CMTime(seconds: max(0, t), preferredTimescale: 600))
            completion(.success(["ok": true]))

        case "getState":
            completion(.success(state()))

        case "setVolume":
            guard let player else {
                completion(.failure(.providerError("尚未播放")))
                return
            }
            let vol = params["volume"] as? Double ?? 1
            player.volume = Float(max(0, min(1, vol)))
            completion(.success(["ok": true, "volume": player.volume]))

        default:
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
        }
    }

    // MARK: - play

    private func handlePlay(params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard let src = params["path"] as? String, !src.isEmpty else {
            completion(.failure(.invalidParams("path 必填（本地路径或 http(s) URL）")))
            return
        }

        let url: URL?
        if src.hasPrefix("http://") || src.hasPrefix("https://") {
            url = URL(string: src)
        } else {
            url = URL(fileURLWithPath: src)
            guard FileManager.default.fileExists(atPath: src) else {
                completion(.failure(.invalidParams("文件不存在")))
                return
            }
        }
        guard let u = url else {
            completion(.failure(.invalidParams("无效地址")))
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            completion(.failure(.providerError(error.localizedDescription)))
            return
        }

        let item = AVPlayerItem(url: u)
        let p = AVPlayer(playerItem: item)
        if let vol = params["volume"] as? Double {
            p.volume = Float(max(0, min(1, vol)))
        }
        if let l = params["loop"] as? Bool { loop = l }
        if let start = params["position"] as? TimeInterval {
            item.seek(to: CMTime(seconds: max(0, start), preferredTimescale: 600))
        }

        // 播完处理：loop 重播，否则暂停并保留进度
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak p] _ in
            guard let self, let p else { return }
            if self.loop {
                p.seek(to: .zero)
                p.play()
            } else {
                p.pause()
            }
        }

        p.play()
        self.player = p

        let duration = item.duration.seconds
        completion(.success([
            "ok": true,
            "duration": duration.isFinite ? duration : 0
        ]))
    }

    // MARK: - state

    private func state() -> [String: Any] {
        guard let player else {
            return [
                "playing": false,
                "paused": true,
                "duration": 0,
                "position": 0,
                "volume": 1.0,
                "loop": loop
            ]
        }
        let duration = player.currentItem?.duration.seconds ?? 0
        let position = player.currentTime().seconds
        return [
            "playing": player.timeControlStatus == .playing,
            "paused": player.timeControlStatus == .paused,
            "duration": duration.isFinite ? duration : 0,
            "position": position.isFinite ? position : 0,
            "volume": player.volume,
            "loop": loop
        ]
    }
}
