import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published var plan = DailyPlan()
    @Published var words: [Word] = []
    @Published var recentReadings: [ReadingSession] = []
    @Published var activity: [DailyActivity] = []
    @Published var profile: Profile?
    @Published var currentReading: ReadingSession?
    @Published var isLoading = false
    @Published var errorMessage: String?

    let api: SupabaseAPI
    init(api: SupabaseAPI) { self.api = api }

    var weakWords: [Word] { words.filter { $0.status == .weak }.sorted { $0.strength < $1.strength } }
    var dueWords: [Word] { words.filter { $0.status != .new && $0.status != .ignored && $0.isDue } }

    func refreshAll() async {
        guard api.isSignedIn else { return }
        isLoading = true; defer { isLoading = false }
        do {
            async let fetchedPlan = api.dailyPlan()
            async let fetchedWords = api.words()
            async let readings = api.recentReadings()
            async let fetchedActivity = api.activity()
            async let fetchedProfile = api.profile()
            (plan, words, recentReadings, activity, profile) = try await (fetchedPlan, fetchedWords, readings, fetchedActivity, fetchedProfile)
        } catch { errorMessage = error.localizedDescription }
    }

    func loadTargets(limit: Int = 10) async -> [Word] {
        do { return try await api.learningTargets(limit: limit) }
        catch { errorMessage = error.localizedDescription; return [] }
    }

    func generateReading(targets: [Word], theme: String, style: String, difficulty: String, regenerate: Bool = false) async throws -> ReadingSession {
        isLoading = true; defer { isLoading = false }
        let reading = try await api.generateReading(targetWordIDs: targets.map(\.id), theme: theme, style: style, difficulty: difficulty, regenerate: regenerate)
        currentReading = reading
        recentReadings.removeAll { $0.id == reading.id }; recentReadings.insert(reading, at: 0)
        return reading
    }

    func updateWord(_ word: Word, notes: String? = nil, customMeaning: String? = nil, status: WordStatus? = nil) async throws {
        let updated = try await api.updateWord(id: word.id, notes: notes, customMeaning: customMeaning, status: status)
        replace(updated)
    }

    func deleteWord(_ word: Word) async throws {
        try await api.deleteWord(id: word.id); words.removeAll { $0.id == word.id }
        await refreshPlan()
    }

    func recordReview(word: Word, quality: Int, type: String, answer: String? = nil, expected: String? = nil, milliseconds: Int? = nil) async {
        do { replace(try await api.applyReview(wordID: word.id, quality: quality, exerciseType: type, answer: answer, expected: expected, responseTime: milliseconds)); await refreshPlan() }
        catch { errorMessage = error.localizedDescription }
    }

    func saveReadingWord(_ explanation: ReadingWordExplanation, sentence: String, readingTitle: String) async throws -> Word {
        let payload = SaveWordPayload(term: explanation.term, lemma: explanation.lemma, phonetic: explanation.phonetic,
            parts: [LexiconPart(partOfSpeech: explanation.partOfSpeech, meaning: explanation.meaning)], primaryMeaning: explanation.meaning,
            contextualMeaning: explanation.contextualMeaning, englishDefinition: nil, exampleEn: sentence, exampleZh: nil,
            context: sentence, sentence: sentence, sourceUrl: nil, sourceTitle: "AI 阅读 · \(readingTitle)")
        let word = try await api.saveWord(payload); replace(word); return word
    }

    func saveLookup(_ result: LookupResult) async throws -> Word {
        let payload = SaveWordPayload(
            term: result.term,
            lemma: result.lemma,
            phonetic: result.phonetic,
            parts: result.parts,
            primaryMeaning: result.primaryMeaning,
            contextualMeaning: result.contextualMeaning,
            englishDefinition: result.englishDefinition,
            exampleEn: result.exampleEnglish,
            exampleZh: result.exampleChinese,
            context: result.sentence,
            sentence: result.sentence,
            sourceUrl: nil,
            sourceTitle: "词鲸背单词 App 查词"
        )
        let word = try await api.saveWord(payload)
        replace(word)
        await refreshPlan()
        return word
    }

    func markReadingComplete(_ reading: ReadingSession) async {
        do { try await api.completeReading(id: reading.id, minutes: reading.estimatedMinutes); await refreshPlan() }
        catch { errorMessage = error.localizedDescription }
    }

    func importDemoWords() async {
        isLoading = true; defer { isLoading = false }
        for item in DemoLexicon.items {
            do { replace(try await api.saveWord(item)) } catch { errorMessage = error.localizedDescription; return }
        }
        await refreshAll()
    }

    func saveProfile(_ value: Profile) async throws {
        profile = try await api.updateProfile(value)
        await refreshPlan()
    }

    private func refreshPlan() async { if let next = try? await api.dailyPlan() { plan = next } }
    private func replace(_ word: Word) {
        if let index = words.firstIndex(where: { $0.id == word.id }) { words[index] = word } else { words.insert(word, at: 0) }
    }

    func loadPreviewData() {
        plan.completedToday = true
        plan.streakDays = 7
        plan.learnedCount = 8
        plan.masteredCount = 5
        plan.reviewedToday = 12
        plan.practiceToday = 12
        plan.readingToday = 1
        plan.newSuggested = 8
        profile = Profile(id: UUID(), displayName: "Qing", dailyNewGoal: 8, dailyReviewGoal: 20, preferredDifficulty: "intermediate", preferredTheme: "daily_life", preferredStyle: "story", timezone: "Asia/Shanghai")
        words = PreviewContent.words
        recentReadings = [PreviewContent.reading(words: words)]
    }
}

private enum PreviewContent {
    static let samples: [(String, String, String, String, WordStatus, Double)] = [
        ("estimate", "ˈestɪmeɪt", "估计；估算", "v.", .weak, 0.15),
        ("investment", "ɪnˈvestmənt", "投资；投入", "n.", .weak, 0.33),
        ("independent", "ˌɪndɪˈpendənt", "独立的；自主的", "adj.", .learning, 0.45),
        ("outperform", "ˌaʊtpərˈfɔːrm", "胜过；表现优于", "v.", .review, 0.33),
        ("automated", "ˈɔːtəmeɪtɪd", "自动化的", "adj.", .learning, 0.52),
        ("alternative", "ɔːlˈtɜːrnətɪv", "选择；替代方案", "n.", .learning, 0.41),
        ("defense", "dɪˈfens", "防御；保护", "n.", .review, 0.38),
        ("long-horizon", "ˌlɔːŋ həˈraɪzn", "长期的；远期的", "adj.", .new, 0.08)
    ]

    static var words: [Word] {
        let now = ISO8601DateFormatter().string(from: .now)
        return samples.map { term, phonetic, meaning, pos, status, strength in
            Word(
                id: UUID(), userId: nil, term: term, normalizedTerm: term.lowercased(), lemma: term,
                phonetic: phonetic, audioUrl: nil, parts: [LexiconPart(partOfSpeech: pos, meaning: meaning)],
                primaryMeaning: meaning, contextualMeaning: meaning, englishDefinition: "A concise English definition for \(term).",
                exampleEn: "Small daily efforts can \(term) sudden bursts of motivation.", exampleZh: "微小而持续的努力会带来改变。",
                firstContext: "Learning is a long-term investment in your future self.", firstSourceUrl: nil, firstSourceTitle: "Chrome 扩展",
                notes: "", customMeaning: nil, status: status, strength: strength, easeFactor: 2.5, intervalDays: 1,
                repetitions: 1, lapses: status == .weak ? 2 : 0, lookupCount: 1, errorCount: status == .weak ? 2 : 0,
                dueAt: now, lastReviewedAt: now, masteredAt: nil, createdAt: now, updatedAt: now
            )
        }
    }

    static func reading(words: [Word]) -> ReadingSession {
        let now = ISO8601DateFormatter().string(from: .now)
        return ReadingSession(
            id: UUID(), userId: nil, title: "A Quiet Kind of Progress", subtitle: "一种安静的进步",
            theme: "daily_life", style: "story", difficulty: "intermediate", targetWordIds: words.map(\.id), targetTerms: words.map(\.term),
            paragraphs: [ReadingParagraph(english: "Small daily efforts can outperform sudden bursts of motivation.", chinese: "每天微小的努力能够胜过一时的热情。")],
            estimatedMinutes: 2, cacheKey: nil, isCached: true, translationsVisible: false, completedAt: now, createdAt: now
        )
    }
}

enum DemoLexicon {
    static let items: [SaveWordPayload] = [
        item("resilient", "rɪˈzɪliənt", "有韧性的；能迅速恢复的", "The resilient community rebuilt after the storm.", "暴风雨后，这个坚韧的社区完成了重建。", "adj."),
        item("subtle", "ˈsʌtəl", "微妙的；不易察觉的", "A subtle change in tone altered the whole conversation.", "语气的微妙变化改变了整场对话。", "adj."),
        item("navigate", "ˈnævəˌɡeɪt", "应对；导航", "She learned to navigate a complex workplace.", "她学会了应对复杂的职场环境。", "v."),
        item("sustain", "səˈsteɪn", "维持；支撑", "Curiosity can sustain a lifetime of learning.", "好奇心能支撑终身学习。", "v."),
        item("inevitable", "ɪnˈevɪtəbəl", "不可避免的", "Some uncertainty is inevitable when plans change.", "计划改变时，一些不确定性不可避免。", "adj."),
        item("perspective", "pərˈspɛktɪv", "视角；观点", "Travel gave him a broader perspective.", "旅行给了他更广阔的视角。", "n."),
        item("convey", "kənˈveɪ", "表达；传达", "Her calm voice conveyed confidence.", "她平静的声音传达出自信。", "v."),
        item("thrive", "θraɪv", "茁壮成长；兴旺", "People thrive when they feel trusted.", "人们在被信任时更容易蓬勃成长。", "v.")
    ]
    private static func item(_ term: String, _ phonetic: String, _ meaning: String, _ en: String, _ zh: String, _ pos: String) -> SaveWordPayload {
        SaveWordPayload(term: term, lemma: term, phonetic: phonetic, parts: [LexiconPart(partOfSpeech: pos, meaning: meaning)], primaryMeaning: meaning, contextualMeaning: meaning, englishDefinition: nil, exampleEn: en, exampleZh: zh, context: en, sentence: en, sourceUrl: nil, sourceTitle: "词鲸背单词演示词库")
    }
}
