import SwiftUI

struct WordDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechService()
    @State private var current: Word
    @State private var contexts: [WordContext] = []
    @State private var events: [ReviewEvent] = []
    @State private var notes = ""
    @State private var customMeaning = ""
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    init(word: Word) { _current = State(initialValue: word); _notes = State(initialValue: word.notes); _customMeaning = State(initialValue: word.customMeaning ?? "") }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    wordHeader
                    meaningCard
                    if let context = current.firstContext, !context.isEmpty { contextCard(context, title: "第一次遇见") }
                    if !contexts.isEmpty { contextsSection }
                    learningCard
                    notesCard
                    errorCard
                }.padding(16).padding(.bottom, 30)
            }
        }
        .navigationTitle(current.term).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Menu { statusMenu; Divider(); Button("删除单词", role: .destructive) { confirmDelete = true } } label: { Image(systemName: "ellipsis.circle") } } }
        .task { async let c = store.api.contexts(wordID: current.id); async let e = store.api.reviewEvents(wordID: current.id); do { contexts = try await c; events = try await e } catch { errorMessage = error.localizedDescription } }
        .confirmationDialog("删除“\(current.term)”？", isPresented: $confirmDelete, titleVisibility: .visible) { Button("删除", role: .destructive) { Task { do { try await store.deleteWord(current); dismiss() } catch { errorMessage = error.localizedDescription } } } }
    }

    private var wordHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(current.term).font(.system(size: 42, weight: .bold, design: .serif))
                Button { speech.speak(current.term) } label: { Image(systemName: "speaker.wave.2.fill").padding(10).background(CiJingTheme.lightGreen, in: Circle()) }
                Spacer()
                Label(current.status.title, systemImage: current.status.icon).font(.caption.bold()).foregroundStyle(current.status.color).padding(.horizontal, 10).padding(.vertical, 7).background(current.status.color.opacity(0.1), in: Capsule())
            }
            HStack { if let phonetic = current.phonetic { Text("/\(phonetic)/") }; if current.lemma.lowercased() != current.term.lowercased() { Text("原形 · \(current.lemma)") } }.font(.subheadline).foregroundStyle(CiJingTheme.secondary)
        }
    }

    private var meaningCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(current.displayMeaning).font(.title3.bold())
            ForEach(current.parts) { part in HStack(alignment: .top) { Text(part.partOfSpeech).font(.caption.bold()).foregroundStyle(CiJingTheme.green).frame(width: 48, alignment: .leading); Text(part.meaning) } }
            if let contextual = current.contextualMeaning { Divider(); Label("此处含义", systemImage: "scope").font(.caption.bold()).foregroundStyle(CiJingTheme.green); Text(contextual) }
            if let definition = current.englishDefinition { Text(definition).font(.subheadline).foregroundStyle(CiJingTheme.secondary) }
            if let example = current.exampleEn { Divider(); Text(example).font(.body); if let chinese = current.exampleZh { Text(chinese).font(.subheadline).foregroundStyle(CiJingTheme.secondary) } }
        }.cijingCard()
    }

    private func contextCard(_ text: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 9) { Label(title, systemImage: "quote.opening").font(.caption.bold()).foregroundStyle(CiJingTheme.green); Text(text).font(.body); if let source = current.firstSourceTitle { Text(source).font(.caption).foregroundStyle(CiJingTheme.secondary) } }.cijingCard()
    }

    private var contextsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("后来遇见的语境 · \(contexts.count)").font(.headline)
            ForEach(contexts.filter { $0.contextText != current.firstContext }) { item in
                VStack(alignment: .leading, spacing: 6) { Text(item.sentence ?? item.contextText).lineLimit(5); if let meaning = item.contextualMeaning { Text(meaning).font(.caption).foregroundStyle(CiJingTheme.green) }; Text(item.sourceTitle ?? "网页阅读").font(.caption2).foregroundStyle(CiJingTheme.secondary) }.cijingCard()
            }
        }
    }

    private var learningCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("学习状态").font(.headline)
            HStack { LearnMetric(title: "记忆强度", value: "\(Int(current.strength * 100))%"); LearnMetric(title: "复习间隔", value: "\(current.intervalDays) 天"); LearnMetric(title: "错误记录", value: "\(current.errorCount) 次") }
            ProgressView(value: current.strength).tint(current.status.color)
            if !events.isEmpty { Text("最近 \(events.count) 次练习 · 正确质量均值 \(String(format: "%.1f", Double(events.map(\.quality).reduce(0, +)) / Double(events.count))) / 5").font(.caption).foregroundStyle(CiJingTheme.secondary) }
        }.cijingCard()
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("我的编辑").font(.headline); Spacer(); Button(editing ? "保存" : "编辑") { if editing { Task { await saveEdits() } } else { editing = true } }.font(.subheadline.bold()) }
            if editing { TextField("自定义释义", text: $customMeaning, axis: .vertical).textFieldStyle(.roundedBorder); TextField("写下联想、易错点或助记…", text: $notes, axis: .vertical).lineLimit(3...7).textFieldStyle(.roundedBorder) }
            else { if !customMeaning.isEmpty { LabeledContent("自定义释义", value: customMeaning) }; Text(notes.isEmpty ? "还没有笔记" : notes).foregroundStyle(notes.isEmpty ? CiJingTheme.secondary : CiJingTheme.ink) }
        }.cijingCard()
    }

    @ViewBuilder private var errorCard: some View { if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(CiJingTheme.danger).cijingCard() } }
    @ViewBuilder private var statusMenu: some View { ForEach(WordStatus.allCases) { status in Button { Task { do { try await store.updateWord(current, status: status); current.status = status } catch { errorMessage = error.localizedDescription } } } label: { Label(status.title, systemImage: status.icon) } } }
    private func saveEdits() async { do { try await store.updateWord(current, notes: notes, customMeaning: customMeaning); current.notes = notes; current.customMeaning = customMeaning; editing = false } catch { errorMessage = error.localizedDescription } }
}

private struct LearnMetric: View { let title, value: String; var body: some View { VStack(alignment: .leading, spacing: 3) { Text(value).font(.headline); Text(title).font(.caption2).foregroundStyle(CiJingTheme.secondary) }.frame(maxWidth: .infinity, alignment: .leading) } }

