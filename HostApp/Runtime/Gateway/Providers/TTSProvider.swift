import AVFoundation

final class TTSProvider: NSObject, CapabilityProvider, AVSpeechSynthesizerDelegate {
    static var capability: String { "tts" }
    static var level: CapabilityLevel { .l0 }
    required override init() { super.init() }

    private let synth = AVSpeechSynthesizer()
    private var completion: ((Result<Any, GatewayError>) -> Void)?

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        switch method {
        case "speak":
            guard let text = params["text"] as? String, !text.isEmpty else {
                completion(.failure(.invalidParams("text 必填")))
                return
            }
            let lang = params["lang"] as? String ?? "zh-CN"
            let rate = params["rate"] as? Float ?? AVSpeechUtteranceDefaultSpeechRate

            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try? session.setActive(true)

            let utt = AVSpeechUtterance(string: text)
            utt.voice = AVSpeechSynthesisVoice(language: lang)
            utt.rate = rate
            self.completion = completion
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

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        completion?(.success(["ok": true]))
        completion = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        completion?(.success(["ok": true, "cancelled": true]))
        completion = nil
    }
}
