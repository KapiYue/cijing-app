import SwiftUI

struct SelectedReadingWord: Identifiable { let id = UUID(); let term, sentence: String }

struct ReadingSessionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechService()
    @State private var displayed: ReadingSession
    @State private var selectedWord: SelectedReadingWord?
    @State private var showTranslations: Bool
    @State private var slowSpeech = false
    @State private var showingShadowing = false
    @State private var showingPractice = false
    @State private var regenerating = false
    @State private var errorMessage: String?

    init(reading: ReadingSession) { _displayed = State(initialValue: reading); _showTranslations = State(initialValue: reading.translationsVisible) }

    var body: some View {
        ZStack(alignment: .bottom) {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    readingHeader
                    targetStrip
                    ForEach(Array(displayed.paragraphs.enumerated()), id: \.offset) { index, paragraph in paragraphView(paragraph, index: index) }
                    completionCard
                }.padding(.horizontal, 20).padding(.bottom, speech.isSpeaking ? 100 : 30)
            }
            if speech.isSpeaking || speech.isPaused { audioBar }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Menu { Button(showTranslations ? "隐藏全部翻译" : "显示全部翻译") { showTranslations.toggle() }; Button("简单一点") { Task { await regenerate(adjustment: -1) } }; Button("难一点") { Task { await regenerate(adjustment: 1) } }; Button("换一篇") { Task { await regenerate(adjustment: 0) } }; Button("跟读模式") { showingShadowing = true } } label: { if regenerating { ProgressView() } else { Image(systemName: "slider.horizontal.3") } } }
        }
        .sheet(item: $selectedWord) { ReadingWordSheet(selection: $0, readingTitle: displayed.title) }
        .fullScreenCover(isPresented: $showingShadowing) { NavigationStack { ShadowingView(reading: displayed) } }
        .fullScreenCover(isPresented: $showingPractice) { NavigationStack { PracticeSessionView(reading: displayed) } }
        .alert("操作失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("好") {} } message: { Text(errorMessage ?? "") }
        .onDisappear { speech.stop() }
    }

    private var readingHeader: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { Label(ReadingOptions.label(for: displayed.theme), systemImage: "sparkles"); Text("·"); Text(ReadingOptions.label(for: displayed.difficulty)); Spacer(); Text("约 \(displayed.estimatedMinutes) 分钟") }.font(.caption).foregroundStyle(CiJingTheme.secondary)
            Text(displayed.title).font(.system(size: 34, weight: .bold, design: .serif))
            if let subtitle = displayed.subtitle { Text(subtitle).font(.subheadline).foregroundStyle(CiJingTheme.secondary) }
        }.padding(.top, 12)
    }

    private var targetStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) { HStack { Text("目标词").font(.caption.bold()).foregroundStyle(CiJingTheme.secondary); ForEach(displayed.targetTerms, id: \.self) { Text($0).font(.caption.bold()).foregroundStyle(CiJingTheme.green).padding(.horizontal, 9).padding(.vertical, 6).background(CiJingTheme.lightGreen, in: Capsule()) } } }
    }

    private func paragraphView(_ paragraph: ReadingParagraph, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text("\(index + 1)").font(.caption.bold()).foregroundStyle(CiJingTheme.green).frame(width: 25, height: 25).background(CiJingTheme.lightGreen, in: Circle())
                ParagraphText(text: paragraph.english, targets: Set(displayed.targetTerms.map { $0.lowercased() })) { term in selectedWord = SelectedReadingWord(term: term, sentence: sentence(containing: term, in: paragraph.english)) }
                    .onTapGesture { speech.speak(paragraph.english, slow: slowSpeech) }
                Button { speech.speak(paragraph.english, slow: slowSpeech) } label: { Image(systemName: speech.currentText == paragraph.english && speech.isSpeaking ? "waveform" : "speaker.wave.2") }.buttonStyle(.borderless)
            }
            if showTranslations { Text(paragraph.chinese).font(.subheadline).foregroundStyle(CiJingTheme.secondary).padding(.leading, 35).transition(.opacity.combined(with: .move(edge: .top))) }
            else { DisclosureGroup("查看本段中文") { Text(paragraph.chinese).font(.subheadline).foregroundStyle(CiJingTheme.secondary).padding(.top, 7) }.font(.caption.bold()).foregroundStyle(CiJingTheme.green).padding(.leading, 35) }
        }.padding(.vertical, 15).overlay(alignment: .bottom) { Divider().opacity(0.45) }
    }

    private var completionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("读完了？让这些词留下来。", systemImage: "checkmark.seal").font(.headline)
            Text("接下来会混合释义辨认、语境完形、拼写和自评回忆。") .font(.subheadline).foregroundStyle(CiJingTheme.secondary)
            Button("完成阅读并开始练习") { Task { await store.markReadingComplete(displayed); showingPractice = true } }.buttonStyle(PrimaryButtonStyle())
            Button("进入逐句跟读") { showingShadowing = true }.font(.subheadline.bold()).frame(maxWidth: .infinity)
        }.cijingCard().padding(.top, 8)
    }

    private var audioBar: some View {
        HStack(spacing: 18) { Button { speech.togglePause() } label: { Image(systemName: speech.isPaused ? "play.fill" : "pause.fill") }; Button { speech.repeatCurrent(slow: slowSpeech) } label: { Image(systemName: "repeat") }; Button { slowSpeech.toggle(); speech.repeatCurrent(slow: slowSpeech) } label: { Text(slowSpeech ? "0.75×" : "1.0×").font(.caption.bold()) }; Text("正在朗读本段").font(.caption).lineLimit(1); Spacer(); Button { speech.stop() } label: { Image(systemName: "xmark") } }
            .foregroundStyle(.white).padding(.horizontal, 19).frame(height: 62).background(.ultraThinMaterial).background(CiJingTheme.green.opacity(0.94)).clipShape(RoundedRectangle(cornerRadius: 20)).padding(12).shadow(radius: 15)
    }

    private func sentence(containing word: String, in text: String) -> String { text.split(whereSeparator: { ".!?".contains($0) }).map(String.init).first { $0.localizedCaseInsensitiveContains(word) }?.trimmingCharacters(in: .whitespaces) ?? text }
    private func regenerate(adjustment: Int) async { let levels = ReadingOptions.difficulties.map(\.0); let index = levels.firstIndex(of: displayed.difficulty) ?? 2; let next = levels[min(levels.count - 1, max(0, index + adjustment))]; let targets = store.words.filter { displayed.targetWordIds.contains($0.id) }; guard targets.count >= 3 else { errorMessage = "目标词已从词库移除，无法重新生成。"; return }; regenerating = true; defer { regenerating = false }; do { displayed = try await store.generateReading(targets: targets, theme: displayed.theme, style: displayed.style, difficulty: next, regenerate: true) } catch { errorMessage = error.localizedDescription } }
}

private struct ParagraphText: View {
    let text: String; let targets: Set<String>; let onWord: (String) -> Void
    var body: some View { Text(attributed).font(.system(size: 19, design: .serif)).lineSpacing(7).foregroundStyle(CiJingTheme.ink).environment(\.openURL, OpenURLAction { url in guard url.scheme == "cijingword", let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "term" })?.value else { return .systemAction }; onWord(value); return .handled }) }
    private var attributed: AttributedString {
        var output = AttributedString(); let pattern = #"[A-Za-z]+(?:['’-][A-Za-z]+)*"#; let regex = try! NSRegularExpression(pattern: pattern); let ns = text as NSString; var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor { output.append(AttributedString(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))) }
            let word = ns.substring(with: match.range); var token = AttributedString(word); let normalized = word.lowercased().trimmingCharacters(in: .punctuationCharacters); let target = targets.contains(normalized) || targets.contains(where: { normalized.hasPrefix($0) || $0.hasPrefix(normalized) })
            token.link = URL(string: "cijingword://lookup?term=\(word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? word)"); token.foregroundColor = target ? CiJingTheme.green : CiJingTheme.ink
            if target { token.font = .system(size: 19, weight: .bold, design: .serif); token.backgroundColor = CiJingTheme.lightGreen }
            output.append(token); cursor = match.range.location + match.range.length
        }
        if cursor < ns.length { output.append(AttributedString(ns.substring(from: cursor))) }
        return output
    }
}

