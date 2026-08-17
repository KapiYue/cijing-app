import SwiftUI

struct SelectedReadingWord: Identifiable { let id = UUID(); let term, sentence: String }

struct ReadingSessionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTabBarHidden) private var tabBarHidden
    @StateObject private var speech = SpeechService()
    @State private var displayed: ReadingSession
    @State private var selectedWord: SelectedReadingWord?
    @State private var expandedTranslations: Set<Int>
    @State private var playbackSpeed = 1.0
    @State private var showingShadowing = false
    @State private var showingPractice = false
    @State private var startingPractice = false
    @State private var regenerating = false
    @State private var errorMessage: String?
    private let onFinish: (() -> Void)?

    init(reading: ReadingSession, onFinish: (() -> Void)? = nil) {
        _displayed = State(initialValue: reading)
        _expandedTranslations = State(initialValue: reading.translationsVisible ? Set(reading.paragraphs.indices) : [])
        self.onFinish = onFinish
    }

    private var fullText: String { displayed.paragraphs.map(\.english).joined(separator: "\n\n") }
    private var allTranslationsVisible: Bool {
        !displayed.paragraphs.isEmpty && expandedTranslations.count == displayed.paragraphs.count
    }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    readingHeader
                    targetStrip
                    Label("本文及翻译由 AI 生成，可能不准确，请结合原文和权威来源核对。", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(CiJingTheme.secondary)
                    ForEach(Array(displayed.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                        paragraphView(paragraph, index: index)
                    }
                    Text("读完后，用几道小练习把这些词真正留下来。")
                        .font(.caption)
                        .foregroundStyle(CiJingTheme.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomDock }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(allTranslationsVisible ? "隐藏全部翻译" : "显示全部翻译") { toggleAllTranslations() }
                    Divider()
                    Button("简单一点") { Task { await regenerate(adjustment: -1) } }
                    Button("难一点") { Task { await regenerate(adjustment: 1) } }
                    Button("换一篇") { Task { await regenerate(adjustment: 0) } }
                } label: {
                    if regenerating { ProgressView() }
                    else { Image(systemName: "slider.horizontal.3") }
                }
                .accessibilityLabel("阅读设置")
            }
        }
        .sheet(item: $selectedWord) { ReadingWordSheet(selection: $0, readingTitle: displayed.title) }
        .fullScreenCover(isPresented: $showingShadowing) { NavigationStack { ShadowingView(reading: displayed) } }
        .fullScreenCover(isPresented: $showingPractice) {
            NavigationStack {
                PracticeSessionView(reading: displayed) {
                    showingPractice = false
                    Task {
                        try? await Task.sleep(for: .milliseconds(240))
                        finishFlow()
                    }
                }
            }
        }
        .alert("操作失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好") {}
        } message: { Text(errorMessage ?? "") }
        // 朗读起不来时（设备上没有英文语音、音频会话被占用）此前是彻底静默的：
        // 播放键点下去没声音也没提示，只能当成"点了没反应"。
        .alert("无法朗读", isPresented: Binding(get: { speech.errorMessage != nil }, set: { if !$0 { speech.errorMessage = nil } })) {
            Button("好") {}
        } message: { Text(speech.errorMessage ?? "") }
        .onAppear { tabBarHidden.wrappedValue = true }
        .onDisappear { speech.stop(); tabBarHidden.wrappedValue = false }
    }

    private var readingHeader: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(ReadingOptions.label(for: displayed.theme), systemImage: "sparkles")
                Text("·")
                Text(ReadingOptions.label(for: displayed.difficulty))
                Spacer()
                Text("约 \(displayed.estimatedMinutes) 分钟")
            }
            .font(.caption)
            .foregroundStyle(CiJingTheme.secondary)
            Text(displayed.title)
                .font(.system(size: 34, weight: .bold, design: .serif))
                .foregroundStyle(CiJingTheme.ink)
            if let subtitle = displayed.subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(CiJingTheme.secondary)
            }
        }
        .padding(.top, 12)
    }

    private var targetStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("目标词").font(.caption.bold()).foregroundStyle(CiJingTheme.secondary)
                ForEach(displayed.targetTerms, id: \.self) { term in
                    Text(term)
                        .font(.caption.bold())
                        .foregroundStyle(CiJingTheme.purple)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(CiJingTheme.purpleSoft, in: Capsule())
                }
            }
        }
    }

    private func paragraphView(_ paragraph: ReadingParagraph, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 9) {
                Text("\(index + 1)")
                    .font(.caption.bold())
                    .foregroundStyle(CiJingTheme.purple)
                    .frame(width: 27, height: 27)
                    .background(CiJingTheme.purpleSoft, in: Circle())
                Button { toggleParagraphPlayback(paragraph.english) } label: {
                    Image(systemName: paragraphPlaybackIcon(paragraph.english))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CiJingTheme.purple)
                        .frame(width: 29, height: 27)
                        .background(CiJingTheme.surface.opacity(0.84), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying(paragraph.english) ? "暂停第 \(index + 1) 段" : "播放第 \(index + 1) 段")
                Spacer()
                Button { toggleTranslation(index) } label: {
                    Text("译")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(expandedTranslations.contains(index) ? .white : CiJingTheme.purple)
                        .frame(width: 31, height: 27)
                        .background(expandedTranslations.contains(index) ? CiJingTheme.purple : CiJingTheme.purpleSoft, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expandedTranslations.contains(index) ? "隐藏第 \(index + 1) 段翻译" : "显示第 \(index + 1) 段翻译")
            }

            ParagraphText(text: paragraph.english, targets: Set(displayed.targetTerms.map { $0.lowercased() })) { term in
                selectedWord = SelectedReadingWord(term: term, sentence: sentence(containing: term, in: paragraph.english))
            }

            if expandedTranslations.contains(index) {
                HStack(alignment: .top, spacing: 8) {
                    Text("译").font(.caption2.bold()).foregroundStyle(CiJingTheme.purple)
                    Text(paragraph.chinese).font(.subheadline).foregroundStyle(CiJingTheme.secondary).lineSpacing(4)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CiJingTheme.surfaceMuted.opacity(0.78), in: RoundedRectangle(cornerRadius: 13))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
        .animation(.easeInOut(duration: 0.2), value: expandedTranslations)
    }

    private var bottomDock: some View {
        VStack(spacing: 10) {
            readingControls
            Button {
                startPractice()
            } label: {
                HStack(spacing: 8) {
                    if startingPractice { ProgressView().tint(.white) }
                    else { Image(systemName: "checkmark.circle.fill") }
                    Text("完成阅读，开始练习")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(startingPractice)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.35) }
    }

    private var readingControls: some View {
        HStack(spacing: 7) {
            Button { toggleFullPlayback() } label: {
                Image(systemName: fullPlaybackIcon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 43, height: 43)
                    .background(CiJingTheme.purple, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(speech.isSpeaking && !speech.isPaused ? "暂停朗读" : (speech.isPaused ? "继续朗读" : "播放全文"))

            Divider().frame(height: 28).padding(.horizontal, 2)

            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5], id: \.self) { speed in
                    Button {
                        setPlaybackSpeed(speed)
                    } label: {
                        if playbackSpeed == speed { Label(speedLabel(speed), systemImage: "checkmark") }
                        else { Text(speedLabel(speed)) }
                    }
                }
            } label: {
                ControlItem(icon: "speedometer", title: speedLabel(playbackSpeed), active: playbackSpeed != 1)
            }

            Button { showingShadowing = true } label: {
                ControlItem(icon: "mic.fill", title: "跟读", active: false)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button { toggleAllTranslations() } label: {
                VStack(spacing: 2) {
                    Text("译").font(.system(size: 16, weight: .heavy))
                    Text("全文").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(allTranslationsVisible ? .white : CiJingTheme.purple)
                .frame(width: 48, height: 42)
                .background(allTranslationsVisible ? CiJingTheme.purple : CiJingTheme.purpleSoft, in: RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 11)
        .frame(height: 57)
        .background(CiJingTheme.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(CiJingTheme.line))
        .shadow(color: CiJingTheme.purpleDark.opacity(0.1), radius: 12, y: 5)
    }

    /// 这段文本是否正在朗读（暂停中不算「正在」，按钮要显示成可继续）。
    private func isPlaying(_ text: String) -> Bool {
        speech.currentText == text.trimmingCharacters(in: .whitespacesAndNewlines)
            && speech.isSpeaking && !speech.isPaused
    }

    private func isActive(_ text: String) -> Bool {
        speech.currentText == text.trimmingCharacters(in: .whitespacesAndNewlines)
            && (speech.isSpeaking || speech.isPaused)
    }

    private func paragraphPlaybackIcon(_ text: String) -> String {
        isPlaying(text) ? "pause.fill" : "speaker.wave.2"
    }

    private func toggleParagraphPlayback(_ text: String) {
        if isActive(text) { speech.togglePause() }
        else { speech.speak(text, speed: playbackSpeed) }
    }

    // 底部这颗是全局走带键：只要有朗读在进行（不管是全文还是某一段），它就是
    // 暂停键。此前它只认全文，先点过段落播放再点它会去另起一段全文朗读。
    private var fullPlaybackIcon: String {
        speech.isSpeaking && !speech.isPaused ? "pause.fill" : "play.fill"
    }

    private func toggleFullPlayback() {
        if speech.isSpeaking || speech.isPaused { speech.togglePause() }
        else { speech.speak(fullText, speed: playbackSpeed) }
    }

    private func setPlaybackSpeed(_ speed: Double) {
        playbackSpeed = speed
        if speech.isSpeaking || speech.isPaused { speech.repeatCurrent(speed: speed) }
    }

    private func speedLabel(_ speed: Double) -> String {
        speed == 1 ? "1.0×" : "\(speed.formatted(.number.precision(.fractionLength(speed == 0.5 || speed == 1.5 ? 1 : 2))))×"
    }

    private func toggleTranslation(_ index: Int) {
        if expandedTranslations.contains(index) { expandedTranslations.remove(index) }
        else { expandedTranslations.insert(index) }
    }

    private func toggleAllTranslations() {
        expandedTranslations = allTranslationsVisible ? [] : Set(displayed.paragraphs.indices)
    }

    private func startPractice() {
        guard !startingPractice else { return }
        startingPractice = true
        store.playHaptic(.completion)
        speech.stop()
        Task {
            await store.markReadingComplete(displayed)
            startingPractice = false
            showingPractice = true
        }
    }

    private func finishFlow() {
        if let onFinish { onFinish() }
        else { dismiss() }
    }

    private func sentence(containing word: String, in text: String) -> String {
        text.split(whereSeparator: { ".!?".contains($0) })
            .map(String.init)
            .first { $0.localizedCaseInsensitiveContains(word) }?
            .trimmingCharacters(in: .whitespaces) ?? text
    }

    private func regenerate(adjustment: Int) async {
        let levels = ReadingOptions.difficulties.map(\.0)
        let index = levels.firstIndex(of: displayed.difficulty) ?? 2
        let next = levels[min(levels.count - 1, max(0, index + adjustment))]
        let targets = store.words.filter { displayed.targetWordIds.contains($0.id) }
        guard targets.count >= 3 else { errorMessage = "目标词已从词库移除，无法重新生成。"; return }
        regenerating = true
        defer { regenerating = false }
        do {
            displayed = try await store.generateReading(targets: targets, theme: displayed.theme, style: displayed.style, difficulty: next, regenerate: true)
            expandedTranslations = []
            speech.stop()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct ControlItem: View {
    let icon: String
    let title: String
    let active: Bool

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold))
            Text(title).font(.system(size: 9, weight: .bold)).lineLimit(1)
        }
        .foregroundStyle(active ? CiJingTheme.purpleDark : CiJingTheme.purple)
        .frame(width: 54, height: 42)
        .background(active ? CiJingTheme.purpleSoft : Color.clear, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ParagraphText: View {
    let text: String
    let targets: Set<String>
    let onWord: (String) -> Void

    var body: some View {
        Text(attributed)
            .font(.system(size: 20, design: .serif))
            .lineSpacing(8)
            .foregroundStyle(CiJingTheme.ink)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "cijingword",
                      let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "term" })?.value else {
                    return .systemAction
                }
                onWord(value)
                return .handled
            })
    }

    private var attributed: AttributedString {
        var output = AttributedString()
        let pattern = #"[A-Za-z]+(?:['’-][A-Za-z]+)*"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let ns = text as NSString
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                output.append(AttributedString(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))))
            }
            let word = ns.substring(with: match.range)
            var token = AttributedString(word)
            let normalized = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            let target = targets.contains(normalized) || targets.contains(where: { normalized.hasPrefix($0) || $0.hasPrefix(normalized) })
            var components = URLComponents()
            components.scheme = "cijingword"
            components.host = "lookup"
            components.queryItems = [URLQueryItem(name: "term", value: word)]
            token.link = components.url
            token.foregroundColor = target ? CiJingTheme.purpleDark : CiJingTheme.ink
            if target {
                token.font = .system(size: 20, weight: .bold, design: .serif)
                token.backgroundColor = CiJingTheme.purpleSoft
            }
            output.append(token)
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length { output.append(AttributedString(ns.substring(from: cursor))) }
        return output
    }
}
