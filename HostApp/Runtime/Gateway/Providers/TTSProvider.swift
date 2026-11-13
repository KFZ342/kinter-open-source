import AVFoundation

final class TTSProvider: NSObject, CapabilityProvider, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    static var capability: String { "tts" }
    static var level: CapabilityLevel { .l0 }
    required override init() { super.init() }

    private let synth = AVSpeechSynthesizer()
    private let lock = NSLock()
    private var completion: ((Result<Any, GatewayError>) -> Void)?

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        switch method {
        case "speak":
            guard let text = params["text"] as? String, !text.isEmpty else {
                completion(.failure(.invalidParams("text 必填")))
                return
            }
            let lang = params["lang"] as? String ?? "zh-CN"
            let requestedRate = params["rate"] as? Float ?? AVSpeechUtteranceDefaultSpeechRate
            let rate = min(max(requestedRate, AVSpeechUtteranceMinimumSpeechRate),
                           AVSpeechUtteranceMaximumSpeechRate)

            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try? session.setActive(true)

            // 上一次朗读尚未结束：先把旧回调以 cancelled 收尾，避免被新回调覆盖而丢失。
            lock.lock()
            let previous = self.completion
            self.completion = nil
            lock.unlock()
            previous?(.success(["ok": true, "cancelled": true]))

            let utt = AVSpeechUtterance(string: text)
            utt.voice = AVSpeechSynthesisVoice(language: lang)
            utt.rate = rate
            lock.lock(); self.completion = completion; lock.unlock()
            synth.delegate = self
            synth.speak(utt)

        case "stop":
            synth.stopSpeaking(at: .immediate)
            completion(.success(["ok": true]))

        case "isSpeaking":
            completion(.success(["speaking": synth.isSpeaking]))

        default:
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
        }
    }

    private func finish(_ result: Result<Any, GatewayError>) {
        lock.lock()
        let cb = completion
        completion = nil
        lock.unlock()
        // 合成器 delegate 回调不保证在主线程，回主线程再通知 JS 侧。
        DispatchQueue.main.async { cb?(result) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finish(.success(["ok": true]))
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finish(.success(["ok": true, "cancelled": true]))
    }
}
