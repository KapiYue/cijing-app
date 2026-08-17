import AVFoundation
import Speech

enum SpeechVoicePreference {
    static let storageKey = "speechVoiceIdentifier"

    static func setSelectedIdentifier(_ identifier: String) {
        UserDefaults.standard.set(identifier, forKey: storageKey)
    }

    static var selectedVoice: AVSpeechSynthesisVoice? {
        if let identifier = UserDefaults.standard.string(forKey: storageKey), !identifier.isEmpty,
           let selected = AVSpeechSynthesisVoice(identifier: identifier) {
            return selected
        }
        return defaultVoice
    }

    static var defaultVoice: AVSpeechSynthesisVoice? {
        let samanthaVoices = englishVoices.filter {
            $0.language.lowercased() == "en-us" && $0.name.localizedCaseInsensitiveCompare("Samantha") == .orderedSame
        }
        return samanthaVoices.max { $0.quality.rawValue < $1.quality.rawValue }
            ?? englishVoices.max { voiceScore($0) < voiceScore($1) }
            ?? AVSpeechSynthesisVoice(language: "en-US")
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
        if label.contains("samantha") { score += 1_000 }
        else if label.contains("ava") || label.contains("allison") || label.contains("siri") { score += 20 }
        if label.contains("compact") || label.contains("novelty") { score -= 200 }
        return score
    }
}

@MainActor
final class SpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isSpeaking = false
    @Published var isPaused = false
    @Published var currentText: String?
    @Published var errorMessage: String?

    private let synthesizer = AVSpeechSynthesizer()
    private var pendingSpeechTask: Task<Void, Never>?
    private var playbackGeneration = 0

    override init() {
        super.init(); synthesizer.delegate = self
    }

    func speak(_ text: String, slow: Bool = false) {
        speak(text, speed: slow ? 0.75 : 1)
    }

    func speak(_ text: String, speed: Double) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        playbackGeneration += 1
        let generation = playbackGeneration
        pendingSpeechTask?.cancel()
        errorMessage = nil
        currentText = value
        isPaused = false

        // AVSpeechSynthesizer may still be delivering the cancellation callback for
        // the previous utterance. Starting a replacement in the same run-loop turn
        // can be silently discarded on a physical device, so wait briefly first.
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
            isSpeaking = false
            pendingSpeechTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled, let self, self.playbackGeneration == generation else { return }
                self.beginSpeaking(value, speed: speed)
            }
        } else {
            beginSpeaking(value, speed: speed)
        }
    }

    private func beginSpeaking(_ value: String, speed: Double) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            isSpeaking = false
            errorMessage = "示范发音未能启动：\(error.localizedDescription)"
            return
        }

        let utterance = AVSpeechUtterance(string: value)
        utterance.voice = SpeechVoicePreference.selectedVoice ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = Self.utteranceRate(for: speed)
        utterance.pitchMultiplier = 1
        utterance.volume = 1
        utterance.preUtteranceDelay = 0.03
        isSpeaking = true
        synthesizer.speak(utterance)

        // 设备上没有可用英文语音时，`speak` 会被静默丢弃：没有音频，也不会回调
        // didStart / didFinish / didCancel。不核对一下，UI 就会一直显示在朗读。
        let generation = playbackGeneration
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, self.playbackGeneration == generation,
                  self.isSpeaking, !self.synthesizer.isSpeaking, !self.synthesizer.isPaused
            else { return }
            self.stop()
            self.errorMessage = "这台设备上没有可用的英文语音。请到「设置 → 辅助功能 → 朗读内容 → 声音」中下载一个英语声音后重试。"
        }
    }

    func togglePause() {
        if synthesizer.isPaused || isPaused {
            synthesizer.continueSpeaking()
            isPaused = false
            // 合成器其实并没有在朗读（下面那种发散场景），继续也无从继续。
            if !synthesizer.isSpeaking { stop() }
            return
        }
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
            isPaused = true
            return
        }
        // 走到这里说明**我们的状态与合成器发散了**：`isSpeaking` 还是 true，但
        // 合成器已经不在朗读——设备上没有可用语音（模拟器常见）、朗读被系统
        // 中断、或启动本身就失败了，而这些情况都不会回调 didFinish/didCancel。
        //
        // 此前这里两个分支都进不去，于是静默什么也不做，按钮永久卡在暂停图标、
        // 再点也没有反应。收敛回停止状态，至少让控件恢复可用。
        stop()
    }

    func repeatCurrent(slow: Bool = false) { if let currentText { speak(currentText, slow: slow) } }
    func repeatCurrent(speed: Double) { if let currentText { speak(currentText, speed: speed) } }
    func stop() {
        playbackGeneration += 1
        pendingSpeechTask?.cancel()
        pendingSpeechTask = nil
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
    }

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
        Task { @MainActor in self.isSpeaking = true; self.isPaused = false; self.errorMessage = nil }
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
    @Published var isTranscribing = false
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var hasInputTap = false
    private var recordingURL: URL?
    private var liveRecognitionFailed = false

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
        cancel(); transcript = ""; errorMessage = nil
        liveRecognitionFailed = false
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest(); request.shouldReportPartialResults = true
            self.request = request
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("cijing-shadowing-\(UUID().uuidString)")
                .appendingPathExtension("caf")
            let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
            recordingURL = url
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                try? audioFile.write(from: buffer)
                request.append(buffer)
            }
            hasInputTap = true
            audioEngine.prepare(); try audioEngine.start(); isRecording = true
            task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    if let value = result?.bestTranscription.formattedString, !value.isEmpty { self?.transcript = value }
                    // Recognition may report a final result or a transient error while the
                    // microphone is still active, especially in Simulator. Recording only
                    // ends when the user taps the stop button.
                    if error != nil, self?.isRecording == true { self?.liveRecognitionFailed = true }
                }
            }
        } catch { errorMessage = error.localizedDescription; cancel() }
    }

    func stop() {
        guard isRecording else { return }
        stopAudioCapture()
        request?.endAudio()
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        task?.cancel(); task = nil; request = nil
        transcribeSavedRecording()
    }

    func cancel() {
        stopAudioCapture()
        request?.endAudio(); task?.cancel(); request = nil; task = nil; isRecording = false
        isTranscribing = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        removeTemporaryRecording()
    }

    private func stopAudioCapture() {
        if audioEngine.isRunning { audioEngine.stop() }
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
    }

    private func transcribeSavedRecording() {
        guard let recordingURL else {
            if transcript.isEmpty { errorMessage = "没有识别到朗读内容，请重试。" }
            return
        }

        isTranscribing = true
        errorMessage = nil
        let request = SFSpeechURLRecognitionRequest(url: recordingURL)
        request.shouldReportPartialResults = false
        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let value = result?.bestTranscription.formattedString, !value.isEmpty {
                    self.transcript = value
                }
                if error != nil || result?.isFinal == true {
                    self.isTranscribing = false
                    self.task = nil
                    if self.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.errorMessage = self.liveRecognitionFailed
                            ? "没有识别到朗读内容。请确认系统麦克风输入后重试，真机识别通常更稳定。"
                            : "没有识别到朗读内容，请靠近麦克风后重试。"
                    }
                    self.removeTemporaryRecording()
                }
            }
        }

        if task == nil {
            isTranscribing = false
            errorMessage = "当前设备暂时无法使用语音识别，请稍后重试。"
            removeTemporaryRecording()
        }
    }

    private func removeTemporaryRecording() {
        guard let recordingURL else { return }
        try? FileManager.default.removeItem(at: recordingURL)
        self.recordingURL = nil
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
