import Speech
import AVFoundation

final class SpeechProvider: NSObject, CapabilityProvider {
    static var capability: String { "speech" }
    static var level: CapabilityLevel { .l1 }

    private let engine = AVAudioEngine()
    private var req: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var completion: ((Result<Any, GatewayError>) -> Void)?

    required override init() { super.init() }

    func invoke(method: String, params: [String: Any], completion: @escaping (Result<Any, GatewayError>) -> Void) {
        guard method == "recognizeOnce" else {
            completion(.failure(.methodNotFound(module: Self.capability, method: method)))
            return
        }
        self.completion = completion
        SFSpeechRecognizer.requestAuthorization { st in
            guard st == .authorized else {
                self.finish(.failure(.userDenied("speech")))
                return
            }
            AVAudioSession.sharedInstance().requestRecordPermission { mic in
                guard mic else {
                    self.finish(.failure(.userDenied("microphone")))
                    return
                }
                DispatchQueue.main.async { self.start() }
            }
        }
    }

    private func finish(_ r: Result<Any, GatewayError>) {
        DispatchQueue.main.async {
            self.completion?(r)
            self.completion = nil
        }
    }

    private func start() {
        // 模拟器 / 无输入设备时 inputNode 返回 0 采样率格式，
        // installTap 会抛 ObjC 异常且无法被 Swift catch，必须预先校验 + 内部捕获。
        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0, fmt.channelCount > 0 else {
            finish(.failure(.unsupported("speech (no audio input device)")))
            return
        }

        let rec = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
        guard rec?.isAvailable == true else {
            finish(.failure(.unsupported("speech recognizer unavailable")))
            return
        }

        let r = SFSpeechAudioBufferRecognitionRequest()
        r.shouldReportPartialResults = false

        // 异步 block 里的 ObjC 异常网关捕获不到，必须自己包一层。
        var thrown: String?
        thrown = ObjCExceptionCatcher.catchException {
            input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { buf, _ in
                r.append(buf)
            }
            self.engine.prepare()
            try? self.engine.start()
        }
        if let t = thrown {
            finish(.failure(.providerError("audio tap failed: \(t)")))
            return
        }

        self.req = r
        self.task = rec?.recognitionTask(with: r) { result, err in
            if let result = result {
                self.cleanup()
                self.finish(.success(["text": result.bestTranscription.formattedString]))
            } else if err != nil {
                self.cleanup()
                self.finish(.failure(.providerError("speech recognition failed")))
            }
        }
    }

    private func cleanup() {
        var thrown: String?
        thrown = ObjCExceptionCatcher.catchException {
            self.engine.stop()
            self.engine.inputNode.removeTap(onBus: 0)
        }
        _ = thrown
        task?.cancel()
        task = nil
        req = nil
    }
}
