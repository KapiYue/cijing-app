import AVFoundation
import Speech

@MainActor
final class SpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isSpeaking = false
    @Published var isPaused = false
    @Published var currentText: String?
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init(); synthesizer.delegate = self
    }

    func speak(_ text: String, slow: Bool = false) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = slow ? 0.38 : 0.49
        utterance.pitchMultiplier = 1
        currentText = text; synthesizer.speak(utterance)
    }

    func togglePause() {
        if synthesizer.isPaused { synthesizer.continueSpeaking(); isPaused = false }
        else if synthesizer.isSpeaking { synthesizer.pauseSpeaking(at: .word); isPaused = true }
    }

    func repeatCurrent(slow: Bool = false) { if let currentText { speak(currentText, slow: slow) } }
    func stop() { synthesizer.stopSpeaking(at: .immediate); isSpeaking = false; isPaused = false }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true; self.isPaused = false }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false; self.isPaused = false }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false; self.isPaused = false }
    }
}

@MainActor
final class ShadowingRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func requestPermissions() async -> Bool {
        let speechAllowed = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status == .authorized) }
        }
        let microphoneAllowed = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in continuation.resume(returning: allowed) }
        }
        if !speechAllowed || !microphoneAllowed { errorMessage = "请在系统设置中允许麦克风和语音识别权限。" }
        return speechAllowed && microphoneAllowed
    }

    func start() async {
        guard await requestPermissions() else { return }
        stop(); transcript = ""; errorMessage = nil
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest(); request.shouldReportPartialResults = true
            self.request = request
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            audioEngine.prepare(); try audioEngine.start(); isRecording = true
            task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    if let result { self?.transcript = result.bestTranscription.formattedString }
                    if error != nil || result?.isFinal == true { self?.stop() }
                }
            }
        } catch { errorMessage = error.localizedDescription; stop() }
    }

    func stop() {
        if audioEngine.isRunning { audioEngine.stop(); audioEngine.inputNode.removeTap(onBus: 0) }
        request?.endAudio(); task?.cancel(); request = nil; task = nil; isRecording = false
    }

    func accuracy(comparedTo expected: String) -> Double {
        let expectedWords = Self.words(expected), actualWords = Self.words(transcript)
        guard !expectedWords.isEmpty else { return 0 }
        let distance = Self.levenshtein(expectedWords, actualWords)
        return max(0, 1 - Double(distance) / Double(max(max(expectedWords.count, actualWords.count), 1)))
    }

    private static func words(_ value: String) -> [String] {
        value.lowercased().split { !$0.isLetter && $0 != "'" }.map(String.init)
    }
    private static func levenshtein(_ lhs: [String], _ rhs: [String]) -> Int {
        var previous = Array(0...rhs.count)
        for (i, left) in lhs.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: rhs.count)
            for (j, right) in rhs.enumerated() { current[j + 1] = min(current[j] + 1, previous[j + 1] + 1, previous[j] + (left == right ? 0 : 1)) }
            previous = current
        }
        return previous[rhs.count]
    }
}
