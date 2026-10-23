import AVFoundation

final class MicrophoneProvider: NSObject, CapabilityProvider, AVAudioRecorderDelegate {
    static var capability: String { "microphone" }
    static var level: CapabilityLevel { .l1 }

    private var recorder: AVAudioRecorder?
    private var completion: ((Result<Any, GatewayError>) -> Void)?
    private var currentURL: URL?

    required override init() { super.init() }

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        switch method {
        case "start":
            start(completion: completion)
        case "stop":
            stop(completion: completion)
        default:
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
        }
    }

    private func start(completion: @escaping (Result<Any, GatewayError>) -> Void) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            completion(.failure(.providerError("audio session: \(error.localizedDescription)")))
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec_\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.delegate = self
            rec.record()
            self.recorder = rec
            self.currentURL = url
            completion(.success(["ok": true]))
        } catch {
            completion(.failure(.providerError("recorder: \(error.localizedDescription)")))
        }
    }

    private func stop(completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard let rec = recorder, let url = currentURL else {
            completion(.failure(.providerError("not recording")))
            return
        }
        rec.stop()
        recorder = nil
        currentURL = nil
        completion(.success(["tempFilePath": url.path]))
    }
}
