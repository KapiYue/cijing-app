import AVFoundation
import Speech

enum SpeechVoicePreference {
    static let storageKey = "speechVoiceIdentifier"

    static var selectedVoice: AVSpeechSynthesisVoice? {
        if let identifier = UserDefaults.standard.string(forKey: storageKey), !identifier.isEmpty,
           let selected = AVSpeechSynthesisVoice(identifier: identifier) {
            return selected
        }
        return englishVoices.max { voiceScore($0) < voiceScore($1) } ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    static var englishVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix("en-") }
            .sorted { left, right in
                let leftScore = voiceScore(left), rightScore = voiceScore(right)
                if leftScore != rightScore { return leftScore > rightScore }
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
    }

    private static func voiceScore(_ voice: AVSpeechSynthesisVoice) -> Int {
        let label = "\(voice.name) \(voice.identifier)".lowercased()
        var score = voice.quality.rawValue * 100
        if voice.language.lowercased() == "en-us" { score += 60 }
        if label.contains("samantha") || label.contains("ava") || label.contains("allison") || label.contains("siri") { score += 20 }
        if label.contains("compact") || label.contains("novelty") { score -= 200 }
        return score
    }
}

@MainActor
final class SpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isSpeaking = false
    @Published var isPaused = false
    @Published var currentText: String?

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init(); synthesizer.delegate = self
    }

    func speak(_ text: String, slow: Bool = false) {
        speak(text, speed: slow ? 0.75 : 1)
    }

    func speak(_ text: String, speed: Double) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: value)
        utterance.voice = SpeechVoicePreference.selectedVoice
        utterance.rate = Self.utteranceRate(for: speed)
        utterance.pitchMultiplier = 1
        utterance.volume = 1
        utterance.preUtteranceDelay = 0.03
        currentText = value
        isPaused = false
        synthesizer.speak(utterance)
    }

    func togglePause() {
        if synthesizer.isPaused { synthesizer.continueSpeaking(); isPaused = false }
        else if synthesizer.isSpeaking { synthesizer.pauseSpeaking(at: .word); isPaused = true }
    }

    func repeatCurrent(slow: Bool = false) { if let currentText { speak(currentText, slow: slow) } }
    func repeatCurrent(speed: Double) { if let currentText { speak(currentText, speed: speed) } }
    func stop() { synthesizer.stopSpeaking(at: .immediate); isSpeaking = false; isPaused = false }

    private static func utteranceRate(for speed: Double) -> Float {
        switch speed {
        case ...0.5: 0.33
        case ...0.75: 0.41
        case ...1.0: 0.49
        case ...1.25: 0.56
        default: 0.62
        }
    }

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
