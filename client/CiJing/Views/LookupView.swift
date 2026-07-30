import SwiftUI

struct LookupView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var speech = SpeechService()
    @State private var query = ""
    @State private var result: LookupResult?
    @State private var isLookingUp = false
    @State private var isSaving = false
    @State private var saved = false
    @State private var errorMessage: String?

    private var recentTerms: [String] {
        store.recentLookupTermsRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty }.prefix(6).map { $0 }
    }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageHeader(title: "查词", subtitle: "查释义，也收藏下一次相遇")
                        .padding(.bottom, 18)
                    SearchField(text: $query, placeholder: "输入英文单词", submitTitle: "查询", onSubmit: lookup)

                    if isLookingUp { loadingState }
                    else if let result { resultCard(result) }
                    else { emptyState }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 112)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard ProcessInfo.processInfo.arguments.contains("-ui-preview"), result == nil else { return }
            query = "resilient"
            result = LookupResult(
                term: "resilient",
                lemma: "resilient",
                phonetic: "rɪˈzɪliənt",
                audioUrl: nil,
                parts: [LexiconPart(partOfSpeech: "adj.", meaning: "有韧性的；能迅速恢复的")],
                primaryMeaning: "有韧性的；能迅速恢复的",
                contextualMeaning: "在压力或变化后仍能恢复并继续前进",
                englishDefinition: "Able to recover quickly from difficulty, change, or pressure.",
                exampleEnglish: "The resilient learner returned to the lesson with fresh curiosity.",
                exampleChinese: "这位坚韧的学习者带着新的好奇心回到了课堂。",
                sentence: "The resilient learner returned to the lesson with fresh curiosity."
            )
        }
        .alert("暂时无法查询", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("知道了") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .onDisappear { speech.stop() }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(CiJingTheme.purple)
                .frame(width: 88, height: 88)
                .background(CiJingTheme.purpleSoft, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .padding(.top, 50)
                .padding(.bottom, 17)
            Text("想查哪个词？").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(CiJingTheme.ink)
            Text("释义、发音、例句和词源，一次看清楚")
                .font(.caption).foregroundStyle(CiJingTheme.secondary).padding(.top, 7)

            VStack(alignment: .leading, spacing: 12) {
                Text("最近查询").font(.system(size: 13, weight: .bold)).foregroundStyle(CiJingTheme.ink)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(recentTerms, id: \.self) { term in
                        Button {
                            query = term
                            lookup()
                        } label: {
                            Text(term)
                                .font(.caption)
                                .foregroundStyle(Color(red: 120 / 255, green: 108 / 255, blue: 127 / 255))
                                .padding(.horizontal, 11).padding(.vertical, 8)
                                .background(CiJingTheme.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 11))
                        }.buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 26)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView().tint(CiJingTheme.purple).scaleEffect(1.2)
            Text("正在理解这个词…").font(.subheadline.bold()).foregroundStyle(CiJingTheme.ink)
            Text("结合释义、例句和真实语境整理结果").font(.caption).foregroundStyle(CiJingTheme.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 86)
    }

    private func resultCard(_ value: LookupResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(value.term).font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(CiJingTheme.ink)
                    Text("/\(value.phonetic)/").font(.system(size: 12, design: .monospaced)).foregroundStyle(CiJingTheme.secondary)
                }
                Spacer()
                Button { speech.speak(value.term) } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(CiJingTheme.purple)
                        .frame(width: 38, height: 38)
                        .background(CiJingTheme.purpleSoft, in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("朗读 \(value.term)")
            }

            Text(value.primaryMeaning)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(CiJingTheme.ink)
                .padding(.top, 18)
            Text(value.englishDefinition)
                .font(.system(size: 12)).foregroundStyle(CiJingTheme.secondary).lineSpacing(4).padding(.top, 7)

            VStack(alignment: .leading, spacing: 7) {
                Text(value.exampleEnglish).italic()
                Text(value.exampleChinese).foregroundStyle(CiJingTheme.secondary)
            }
            .font(.system(size: 13))
            .lineSpacing(4)
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CiJingTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 13))
            .padding(.top, 16)

            Button { save(value) } label: {
                HStack(spacing: 7) {
                    if isSaving { ProgressView().tint(saved ? CiJingTheme.purple : .white) }
                    Image(systemName: saved ? "checkmark" : "plus")
                    Text(saved ? "已收藏到词库" : "收藏到词库")
                }
            }
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(saved ? CiJingTheme.purple : .white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                saved ? AnyShapeStyle(CiJingTheme.purpleSoft) : AnyShapeStyle(CiJingTheme.primaryGradient),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .buttonStyle(.plain)
            .disabled(isSaving || saved)
            .padding(.top, 16)
        }
        .cijingCard(padding: 21)
        .padding(.top, 16)
    }

    private func lookup() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.range(of: "^[A-Za-z][A-Za-z'-]{0,60}$", options: .regularExpression) != nil else {
            errorMessage = "请输入一个英文单词。"
            return
        }
        isLookingUp = true
        result = nil
        saved = false
        Task {
            defer { isLookingUp = false }
            do {
                let value = try await store.api.lookupWord(term)
                result = value
                if store.autoPronunciationEnabled { speech.speak(value.term) }
                remember(term.lowercased())
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func save(_ value: LookupResult) {
        isSaving = true
        Task {
            defer { isSaving = false }
            do { _ = try await store.saveLookup(value); saved = true }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func remember(_ term: String) {
        store.setRecentLookupTermsRaw(([term] + recentTerms.filter { $0.caseInsensitiveCompare(term) != .orderedSame }).prefix(6).joined(separator: ","))
    }
}
