import SwiftUI

struct ReadingWordSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechService()
    let selection: SelectedReadingWord
    let readingTitle: String
    @State private var explanation: ReadingWordExplanation?
    @State private var lookupFallback: LookupResult?
    @State private var loading = true
    @State private var saved = false
    @State private var errorMessage: String?

    private var known: Word? { store.words.first { $0.term.caseInsensitiveCompare(selection.term) == .orderedSame || $0.lemma.caseInsensitiveCompare(selection.term) == .orderedSame } }

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 17) {
                        HStack(alignment: .firstTextBaseline) { Text(explanation?.term ?? known?.term ?? selection.term).font(.system(size: 38, weight: .bold, design: .serif)); Button { speech.speak(explanation?.term ?? known?.term ?? selection.term) } label: { Image(systemName: "speaker.wave.2.fill").padding(10).background(CiJingTheme.lightGreen, in: Circle()) }; Spacer() }
                        if loading { ProgressView("正在理解这个句子…").frame(maxWidth: .infinity).padding(.vertical, 50) }
                        else if let word = known { knownContent(word) }
                        else if let explanation { explanationContent(explanation) }
                        else if let lookupFallback { lookupContent(lookupFallback) }
                        if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(CiJingTheme.danger).cijingCard() }
                    }.padding(20)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .task {
            if store.autoPronunciationEnabled { speech.speak(selection.term) }
            await load()
        }
        .onDisappear { speech.stop() }
    }

    private func knownContent(_ word: Word) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("/\(word.phonetic ?? "")/ · \(word.parts.first?.partOfSpeech ?? "")").foregroundStyle(CiJingTheme.secondary)
            Text(word.displayMeaning).font(.title3.bold())
            if let contextual = word.contextualMeaning { Label("当前语境", systemImage: "scope").font(.caption.bold()).foregroundStyle(CiJingTheme.green); Text(contextual) }
            Text(selection.sentence).font(.body).padding(13).background(CiJingTheme.paper, in: RoundedRectangle(cornerRadius: 13))
            if let attribution = word.dictionaryAttribution {
                DictionaryAttributionView(attribution: attribution)
            }
            Label("已在个人词库 · \(word.status.title)", systemImage: "checkmark.circle.fill").font(.subheadline.bold()).foregroundStyle(CiJingTheme.green)
        }.cijingCard()
    }

    private func explanationContent(_ item: ReadingWordExplanation) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("/\(item.phonetic)/ · \(item.partOfSpeech) · 原形 \(item.lemma)").foregroundStyle(CiJingTheme.secondary)
            Text(item.meaning).font(.title3.bold())
            Label("这个句子里", systemImage: "scope").font(.caption.bold()).foregroundStyle(CiJingTheme.green)
            Text(item.contextualMeaning)
            Text(selection.sentence).font(.body).padding(13).background(CiJingTheme.paper, in: RoundedRectangle(cornerRadius: 13))
            if let attribution = item.dictionaryAttribution {
                DictionaryAttributionView(attribution: attribution)
            }
            Button(saved ? "✓ 已保存到词库" : "＋ 保存为新词") { Task { await save(item) } }.buttonStyle(PrimaryButtonStyle()).disabled(saved)
        }.cijingCard()
    }

    private func lookupContent(_ item: LookupResult) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("/\(item.phonetic)/ · 原形 \(item.lemma)").foregroundStyle(CiJingTheme.secondary)
            Text(item.primaryMeaning).font(.title3.bold())
            Label("这个句子里", systemImage: "scope").font(.caption.bold()).foregroundStyle(CiJingTheme.purple)
            Text(item.contextualMeaning)
            Text(selection.sentence).font(.body).padding(13).background(CiJingTheme.paper, in: RoundedRectangle(cornerRadius: 13))
            if !item.englishDefinition.isEmpty {
                Text(item.englishDefinition).font(.subheadline).foregroundStyle(CiJingTheme.secondary)
            }
            if let attribution = item.dictionaryAttribution {
                DictionaryAttributionView(attribution: attribution)
            }
            Button(saved ? "✓ 已保存到词库" : "＋ 保存为新词") { Task { await save(item) } }
                .buttonStyle(PrimaryButtonStyle()).disabled(saved)
        }.cijingCard()
    }

    private func load() async {
        if known != nil { loading = false; return }
        do { explanation = try await store.api.explainReadingWord(selection.term, sentence: selection.sentence) }
        catch {
            do {
                lookupFallback = try await store.api.lookupWord(selection.term, context: selection.sentence, sentence: selection.sentence)
            } catch {
                errorMessage = "暂时没查到这个词，请检查网络后重试。\n\(error.localizedDescription)"
            }
        }
        loading = false
    }
    private func save(_ item: ReadingWordExplanation) async { do { _ = try await store.saveReadingWord(item, sentence: selection.sentence, readingTitle: readingTitle); saved = true } catch { errorMessage = error.localizedDescription } }
    private func save(_ item: LookupResult) async { do { _ = try await store.saveLookup(item); saved = true } catch { errorMessage = error.localizedDescription } }
}
