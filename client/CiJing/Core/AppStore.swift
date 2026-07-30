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
    @Published private(set) var hasLoadedAccountData = false
    @Published private(set) var preferredAppearance: String?
    @Published private(set) var dailyReminderEnabled = false
    @Published private(set) var autoPronunciationEnabled = true
    @Published private(set) var hapticFeedbackEnabled = true
    @Published private(set) var recentLookupTermsRaw = "serendipity,resilient,nuance"
    @Published var errorMessage: String?

    let api: SupabaseAPI
    init(api: SupabaseAPI) {
        self.api = api
        loadLocalAccountPreferences(migratingLegacyValues: true)
    }

    var weakWords: [Word] { words.filter { $0.status == .weak }.sorted { $0.strength < $1.strength } }
    var dueWords: [Word] { words.filter { $0.status != .new && $0.status != .ignored && $0.isDue } }

    func refreshAll() async {
        guard api.isSignedIn else { return }
        loadLocalAccountPreferences(migratingLegacyValues: true)
        isLoading = true
        defer {
            isLoading = false
            hasLoadedAccountData = true
        }
        async let planResult = fetchResult { try await api.dailyPlan() }
        async let wordsResult = fetchResult { try await api.words() }
        async let readingsResult = fetchResult { try await api.recentReadings() }
        async let activityResult = fetchResult { try await api.activity() }
        async let profileResult = fetchResult { try await api.profile() }
        let results = await (planResult, wordsResult, readingsResult, activityResult, profileResult)

        var successfulRequests = 0
        var firstError: Error?

        switch results.0 {
        case .success(let value): plan = value; successfulRequests += 1
        case .failure(let error): firstError = firstError ?? error
        }
        switch results.1 {
        case .success(let value): words = value; successfulRequests += 1
        case .failure(let error): firstError = firstError ?? error
        }
        switch results.2 {
        case .success(let value): recentReadings = value; successfulRequests += 1
        case .failure(let error): firstError = firstError ?? error
        }
        switch results.3 {
        case .success(let value): activity = value; successfulRequests += 1
        case .failure(let error): firstError = firstError ?? error
        }
        switch results.4 {
        case .success(let value): profile = value; applyAccountPreferences(); successfulRequests += 1
        case .failure(let error): firstError = firstError ?? error
        }

        // 首页的词库、短文、计划和资料来自独立接口。只要其中一部分已成功，
        // 就保留可用内容且不弹出阻断式错误；全部失败时才提示用户重试。
        errorMessage = successfulRequests == 0 ? firstError?.localizedDescription : nil
        await reconcileDailyReminder()
    }

    /// Refreshes the library independently so an unrelated home/profile request cannot leave it stale.
    func refreshLibrary() async {
        guard api.isSignedIn else { return }
        let showsLoader = words.isEmpty
        if showsLoader { isLoading = true }
        defer { if showsLoader { isLoading = false } }
        do {
            words = try await api.words()
            if let refreshedPlan = try? await api.dailyPlan() { plan = refreshedPlan }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
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
        let payload = SaveWordPayload(term: explanation.term, lemma: explanation.lemma, phonetic: explanation.phonetic, audioUrl: nil,
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
            audioUrl: result.audioUrl,
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
        applyAccountPreferences()
        await refreshPlan()
    }

    func clearSessionData() {
        plan = DailyPlan()
        words = []
        recentReadings = []
        activity = []
        profile = nil
        currentReading = nil
        hasLoadedAccountData = false
        preferredAppearance = nil
        dailyReminderEnabled = false
        autoPronunciationEnabled = true
        hapticFeedbackEnabled = true
        recentLookupTermsRaw = Self.defaultRecentLookupTerms
        errorMessage = nil
        UserDefaults.standard.removeObject(forKey: SpeechVoicePreference.storageKey)
    }

    func setAppearancePreference(_ appearance: AppAppearance) {
        guard let userID = api.currentUserID else { return }
        preferredAppearance = appearance.rawValue
        UserDefaults.standard.set(appearance.rawValue, forKey: Self.accountStorageKey("appearance", userID: userID))
    }

    func setDailyReminderEnabled(_ value: Bool) async -> String? {
        guard api.currentUserID != nil else { return "请先登录后再设置学习提醒。" }
        let result = await DailyReminderScheduler.setEnabled(value, requestAuthorization: value)
        switch result {
        case .scheduled:
            setLocalPreference(value, name: "daily-reminder") { dailyReminderEnabled = value }
            return nil
        case .permissionDenied:
            setLocalPreference(false, name: "daily-reminder") { dailyReminderEnabled = false }
            return "通知权限已关闭。请前往 iPhone“设置”→“通知”→“词鲸背单词”允许通知后再开启。"
        case .permissionNotRequested:
            setLocalPreference(false, name: "daily-reminder") { dailyReminderEnabled = false }
            return "尚未获得通知权限，请再次开启提醒并允许系统通知。"
        case .failed(let detail):
            setLocalPreference(false, name: "daily-reminder") { dailyReminderEnabled = false }
            return "学习提醒设置失败：\(detail)"
        }
    }

    func setAutoPronunciationEnabled(_ value: Bool) {
        setLocalPreference(value, name: "auto-pronunciation") { autoPronunciationEnabled = value }
    }

    func setHapticFeedbackEnabled(_ value: Bool) {
        setLocalPreference(value, name: "haptic-feedback") { hapticFeedbackEnabled = value }
    }

    func playHaptic(_ event: LearningHaptic) {
        guard hapticFeedbackEnabled else { return }
        LearningHapticFeedback.play(event)
    }

    func reconcileDailyReminder() async {
        guard api.currentUserID != nil else {
            _ = await DailyReminderScheduler.setEnabled(false, requestAuthorization: false)
            dailyReminderEnabled = false
            return
        }
        guard dailyReminderEnabled else { return }
        let result = await DailyReminderScheduler.setEnabled(true, requestAuthorization: false)
        switch result {
        case .scheduled:
            break
        case .permissionDenied, .permissionNotRequested, .failed:
            setLocalPreference(false, name: "daily-reminder") { dailyReminderEnabled = false }
        }
    }

    func clearDailyReminder() async {
        _ = await DailyReminderScheduler.setEnabled(false, requestAuthorization: false)
    }

    func setRecentLookupTermsRaw(_ value: String) {
        setLocalPreference(value, name: "recent-lookups") { recentLookupTermsRaw = value }
    }

    private static let defaultRecentLookupTerms = "serendipity,resilient,nuance"
    private static let legacyAppearancePrefix = "cijing.appearance."
    private static let legacyPreferenceKeys = [
        "dailyReminderEnabled",
        "autoPronunciationEnabled",
        "hapticFeedbackEnabled",
        "recentLookupTerms",
    ]

    private func loadLocalAccountPreferences(migratingLegacyValues: Bool) {
        guard let userID = api.currentUserID else {
            preferredAppearance = nil
            dailyReminderEnabled = false
            autoPronunciationEnabled = true
            hapticFeedbackEnabled = true
            recentLookupTermsRaw = Self.defaultRecentLookupTerms
            return
        }

        let defaults = UserDefaults.standard
        if migratingLegacyValues {
            migrateLegacyPreferences(to: userID, defaults: defaults)
        }
        preferredAppearance = defaults.string(forKey: Self.accountStorageKey("appearance", userID: userID))
        dailyReminderEnabled = defaults.object(forKey: Self.accountPreferenceStorageKey("daily-reminder", userID: userID)) as? Bool ?? false
        autoPronunciationEnabled = defaults.object(forKey: Self.accountPreferenceStorageKey("auto-pronunciation", userID: userID)) as? Bool ?? true
        hapticFeedbackEnabled = defaults.object(forKey: Self.accountPreferenceStorageKey("haptic-feedback", userID: userID)) as? Bool ?? true
        recentLookupTermsRaw = defaults.string(forKey: Self.accountPreferenceStorageKey("recent-lookups", userID: userID)) ?? Self.defaultRecentLookupTerms
    }

    private func migrateLegacyPreferences(to userID: UUID, defaults: UserDefaults) {
        let appearanceKey = Self.accountStorageKey("appearance", userID: userID)
        let legacyAppearanceKey = Self.legacyAppearancePrefix + api.currentEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if defaults.object(forKey: appearanceKey) == nil, let value = defaults.string(forKey: legacyAppearanceKey) {
            defaults.set(value, forKey: appearanceKey)
        }
        defaults.removeObject(forKey: legacyAppearanceKey)

        // These values used to be global, so their owning account cannot be known.
        // Discard them instead of assigning another user's preferences to the
        // account that happened to be signed in during the upgrade.
        for legacyKey in Self.legacyPreferenceKeys {
            defaults.removeObject(forKey: legacyKey)
        }
    }

    private func setLocalPreference<T>(_ value: T, name: String, apply: () -> Void) {
        guard let userID = api.currentUserID else { return }
        apply()
        UserDefaults.standard.set(value, forKey: Self.accountPreferenceStorageKey(name, userID: userID))
    }

    private static func accountStorageKey(_ name: String, userID: UUID) -> String {
        "cijing.account.\(userID.uuidString.lowercased()).\(name)"
    }

    private static func accountPreferenceStorageKey(_ name: String, userID: UUID) -> String {
        "cijing.account.\(userID.uuidString.lowercased()).preferences.v2.\(name)"
    }

    private func refreshPlan() async { if let next = try? await api.dailyPlan() { plan = next } }
    private func fetchResult<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await operation()) }
        catch { return .failure(error) }
    }
    private func replace(_ word: Word) {
        if let index = words.firstIndex(where: { $0.id == word.id }) { words[index] = word } else { words.insert(word, at: 0) }
    }

    func loadPreviewData() {
        plan.completedToday = true
        plan.streakDays = 18
        // Match the production review account used for App Store review.
        plan.learnedCount = 146
        plan.masteredCount = 68
        plan.reviewedToday = 14
        plan.practiceToday = 8
        plan.readingToday = 2
        plan.reviewDue = 7
        plan.newSuggested = 1
        profile = Profile(id: UUID(), displayName: "Qing", dailyNewGoal: 8, dailyReviewGoal: 20, preferredDifficulty: "intermediate", preferredTheme: "daily_life", preferredStyle: "story", preferredVoiceIdentifier: "", timezone: "Asia/Shanghai")
        words = PreviewContent.words
        recentReadings = PreviewContent.readings(words: words)
        activity = PreviewContent.activity
        hasLoadedAccountData = true
    }

    private func applyAccountPreferences() {
        SpeechVoicePreference.setSelectedIdentifier(profile?.preferredVoiceIdentifier ?? "")
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

    // These terms mirror the production review account's supplemental vocabulary.
    // The first 68 are mastered; the remainder alternate between review and learning.
    static let supplementalTerms = [
        "resilient", "subtle", "navigate", "sustain", "inevitable", "perspective", "convey", "thrive",
        "adapt", "allocate", "anticipate", "articulate", "assess", "attain", "coherent", "collaborate",
        "compelling", "concise", "consensus", "constraint", "contemplate", "conventional", "crucial", "cultivate",
        "deliberate", "demonstrate", "diminish", "diverse", "elaborate", "emerge", "empirical", "enhance",
        "evaluate", "evident", "facilitate", "flexible", "formulate", "fundamental", "generate", "illustrate",
        "implement", "imply", "incentive", "integrate", "interpret", "justify", "maintain", "mitigate",
        "mutual", "objective", "perceive", "persist", "preliminary", "prioritize", "profound", "promote",
        "refine", "relevant", "reliable", "reinforce", "resolve", "retain", "rigorous", "scarce",
        "significant", "stable", "strategy", "transform", "accessible", "accumulate", "adjacent", "advocate",
        "ambiguous", "analyze", "apparent", "approximate", "authentic", "autonomous", "beneficial", "capacity",
        "clarify", "compatible", "comprehensive", "consistent", "contribute", "credible", "critical", "cumulative",
        "derive", "dynamic", "efficient", "encounter", "establish", "ethical", "explicit", "framework",
        "gradual", "hypothesis", "identify", "impact", "innovate", "insight", "interact", "internal",
        "logical", "maximize", "minimize", "monitor", "motivate", "occur", "optimize", "outcome",
        "overall", "parameter", "participate", "practical", "predict", "preserve", "pursue", "recover",
        "regulate", "robust", "scope", "sequence", "simulate", "specify", "sufficient", "sustainable",
        "synthesize", "tendency", "transition", "transparent", "valid", "versatile", "voluntary", "widespread",
        "acknowledge", "acquire"
    ]

    static var words: [Word] {
        let now = ISO8601DateFormatter().string(from: .now)
        let coreWords = samples.map { term, phonetic, meaning, pos, status, strength in
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
        let supplementalWords = supplementalTerms.enumerated().map { index, term in
            let status: WordStatus = index < 68 ? .mastered : (index.isMultiple(of: 3) ? .review : .learning)
            return Word(
                id: UUID(), userId: nil, term: term, normalizedTerm: term, lemma: term,
                phonetic: nil, audioUrl: nil, parts: [], primaryMeaning: "审核演示词汇", contextualMeaning: nil,
                englishDefinition: nil, exampleEn: nil, exampleZh: nil, firstContext: nil, firstSourceUrl: nil,
                firstSourceTitle: "Chrome 扩展", notes: "", customMeaning: nil, status: status,
                strength: status == .mastered ? 0.92 : 0.58, easeFactor: 2.5,
                intervalDays: status == .mastered ? 45 : 7, repetitions: status == .mastered ? 6 : 2,
                lapses: 0, lookupCount: 2, errorCount: 0, dueAt: now, lastReviewedAt: now,
                masteredAt: status == .mastered ? now : nil, createdAt: now, updatedAt: now
            )
        }
        return coreWords + supplementalWords
    }

    static func readings(words: [Word]) -> [ReadingSession] {
        let now = ISO8601DateFormatter().string(from: .now)
        let earlier = ISO8601DateFormatter().string(from: .now.addingTimeInterval(-86_400))
        let oldest = ISO8601DateFormatter().string(from: .now.addingTimeInterval(-172_800))
        let coreWords = Array(words.prefix(samples.count))
        return [
            ReadingSession(
                id: UUID(), userId: nil, title: "A Quiet Kind of Progress", subtitle: "一种安静的进步",
                theme: "daily_life", style: "story", difficulty: "intermediate", targetWordIds: coreWords.map(\.id), targetTerms: coreWords.map(\.term),
                paragraphs: [
                    ReadingParagraph(english: "Small daily efforts can outperform sudden bursts of motivation. Mei stopped trying to estimate how quickly her English would improve and focused on one thoughtful page each morning.", chinese: "每天微小的努力能够胜过一时的热情。小梅不再估算英语能多快进步，而是专注于每天清晨认真读完一页。"),
                    ReadingParagraph(english: "This independent routine became an investment in her future. Automated reminders helped, but the real change came from choosing a sustainable alternative to cramming.", chinese: "这个独立的习惯成了她对未来的投资。自动提醒有所帮助，但真正的改变来自她选择了可持续的学习方式，而不是突击。"),
                    ReadingParagraph(english: "Weeks later, she could defend her ideas with clearer words and a long-horizon perspective. Her progress was quiet, but unmistakable.", chinese: "几周后，她能用更清晰的词语表达并捍卫自己的观点，也拥有了更长远的视角。她的进步很安静，却清晰可见。")
                ],
                estimatedMinutes: 4, cacheKey: nil, isCached: true, translationsVisible: true, completedAt: now, createdAt: now
            ),
            ReadingSession(
                id: UUID(), userId: nil, title: "The Train Beyond the Rain", subtitle: "驶出雨幕的列车",
                theme: "travel", style: "story", difficulty: "upper_intermediate", targetWordIds: Array(coreWords.prefix(6).map(\.id)), targetTerms: Array(coreWords.prefix(6).map(\.term)),
                paragraphs: [ReadingParagraph(english: "A delayed train gave Lina an unexpected afternoon in a mountain town. Instead of treating it as wasted time, she wandered into a family café and listened to the stories around her.", chinese: "晚点的列车让莉娜意外地在山城多停留了一个下午。她没有把这当作浪费，而是走进一家家庭咖啡馆，倾听身边的故事。")],
                estimatedMinutes: 5, cacheKey: nil, isCached: true, translationsVisible: false, completedAt: earlier, createdAt: earlier
            ),
            ReadingSession(
                id: UUID(), userId: nil, title: "Designing Time for Deep Work", subtitle: "为深度工作设计时间",
                theme: "workplace", style: "article", difficulty: "advanced", targetWordIds: Array(coreWords.suffix(5).map(\.id)), targetTerms: Array(coreWords.suffix(5).map(\.term)),
                paragraphs: [ReadingParagraph(english: "Protecting attention is less about perfect discipline than deliberate design. A team can reduce interruptions by agreeing on quiet hours and making communication expectations explicit.", chinese: "保护注意力与其说依赖完美的自律，不如说依赖有意识的设计。团队可以约定安静时段，并明确沟通预期，以减少干扰。")],
                estimatedMinutes: 6, cacheKey: nil, isCached: true, translationsVisible: false, completedAt: oldest, createdAt: oldest
            )
        ]
    }

    static var activity: [DailyActivity] {
        let calendar = Calendar(identifier: .gregorian)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return (0..<18).map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: .now) ?? .now
            return DailyActivity(
                activityDate: formatter.string(from: date), learnedCount: 5 + (offset % 5),
                reviewedCount: 14 + (offset % 8), readingCount: offset % 3 == 0 ? 2 : 1,
                practiceCount: 8 + (offset % 7), minutes: 18 + (offset % 6) * 4, completed: true
            )
        }
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
        SaveWordPayload(term: term, lemma: term, phonetic: phonetic, audioUrl: nil, parts: [LexiconPart(partOfSpeech: pos, meaning: meaning)], primaryMeaning: meaning, contextualMeaning: meaning, englishDefinition: nil, exampleEn: en, exampleZh: zh, context: en, sentence: en, sourceUrl: nil, sourceTitle: "词鲸背单词演示词库")
    }
}
