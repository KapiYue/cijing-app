import SwiftUI
// `requestReview` 环境值由 StoreKit 提供，不导入就取不到。
import StoreKit

private enum ExerciseKind: String, Hashable {
    case meaningChoice, clozeChoice, spelling, contextChoice, selfRating

    var title: String {
        switch self {
        case .meaningChoice: "看词选义"
        case .clozeChoice: "语境完形"
        case .spelling: "拼写回忆"
        case .contextChoice: "语境含义"
        case .selfRating: "主动回忆"
        }
    }
}

private enum PracticeStage { case questions, wrongReview, summary }

private struct PracticeQuestion: Identifiable, Hashable {
    let id = UUID()
    let word: Word
    let kind: ExerciseKind
    let prompt: String
    let options: [String]
    let answer: String
    let sentence: String?
}

struct PracticeSessionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechService()
    let reading: ReadingSession
    private let onFinish: (() -> Void)?

    @State private var questions: [PracticeQuestion] = []
    @State private var activeQuestions: [PracticeQuestion] = []
    @State private var stage: PracticeStage = .questions
    @State private var index = 0
    @State private var selected: String?
    @State private var typed = ""
    @State private var revealed = false
    @State private var feedbackPresented = false
    @State private var lastWasCorrect = false
    @State private var retrying = false
    @State private var retryRound = 0
    @State private var pendingWrong: [PracticeQuestion] = []
    @State private var missedWords: [Word] = []
    @State private var directCorrect = Set<UUID>()
    @State private var attemptsByKind: [ExerciseKind: Int] = [:]
    @State private var correctByKind: [ExerciseKind: Int] = [:]
    @State private var startedAt = Date()
    /// 只在真的跨过一档时才有值——没升级就没有弹窗。
    @State private var unlockedAchievement: AchievementUnlock?
    @Environment(\.requestReview) private var requestReview

    init(reading: ReadingSession, onFinish: (() -> Void)? = nil) {
        self.reading = reading
        self.onFinish = onFinish
    }

    private var question: PracticeQuestion? {
        activeQuestions.indices.contains(index) ? activeQuestions[index] : nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            PaperBackground()
            content

            if feedbackPresented, let question {
                Color.black.opacity(0.08).ignoresSafeArea().transition(.opacity)
                feedbackSheet(question)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
            }

            if let unlockedAchievement {
                badgeOverlay(unlockedAchievement)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(3)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: feedbackPresented)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: unlockedAchievement?.id)
        .navigationTitle("巩固练习")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("退出") { dismiss() } }
        }
        .onAppear { if questions.isEmpty { buildQuestions() } }
        .onDisappear { speech.stop() }
    }

    @ViewBuilder private var content: some View {
        if questions.isEmpty {
            VStack(spacing: 16) {
                ProgressView()
                Text("正在准备练习…").foregroundStyle(CiJingTheme.secondary)
            }
        } else {
            switch stage {
            case .questions:
                if let question { questionView(question) }
            case .wrongReview:
                wrongReviewView
            case .summary:
                summaryView
            }
        }
    }

    private func questionView(_ item: PracticeQuestion) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(item.kind.title)
                        .font(.caption.bold())
                        .foregroundStyle(CiJingTheme.purple)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(CiJingTheme.purpleSoft, in: Capsule())
                    Spacer()
                    Text("\(index + 1) / \(activeQuestions.count)")
                        .font(.caption.bold()).foregroundStyle(CiJingTheme.secondary)
                    if retrying {
                        Text("第 \(retryRound + 1) 轮").font(.caption2.bold()).foregroundStyle(.orange)
                    }
                }
                ProgressView(value: Double(index), total: Double(max(1, activeQuestions.count)))
                    .tint(CiJingTheme.purple)

                promptCard(item)
                answerArea(item)
            }
            .padding(20)
            .padding(.bottom, feedbackPresented ? 230 : 30)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func promptCard(_ item: PracticeQuestion) -> some View {
        VStack(alignment: item.kind == .meaningChoice ? .center : .leading, spacing: 13) {
            Text(promptEyebrow(item))
                .font(.subheadline)
                .foregroundStyle(CiJingTheme.secondary)
                .frame(maxWidth: .infinity, alignment: item.kind == .meaningChoice ? .center : .leading)

            if item.kind == .meaningChoice {
                HStack(spacing: 11) {
                    Text(item.word.term).font(.system(size: 33, weight: .bold, design: .serif))
                    Button { speech.speak(item.word.term) } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(CiJingTheme.purple)
                            .frame(width: 39, height: 39)
                            .background(CiJingTheme.purpleSoft, in: Circle())
                    }.buttonStyle(.plain)
                }
                Text("/\(item.word.phonetic ?? "")/").font(.caption).foregroundStyle(CiJingTheme.secondary)
            } else {
                Text(item.prompt)
                    .font(.system(size: item.kind == .clozeChoice || item.kind == .contextChoice ? 21 : 27, weight: .bold, design: .serif))
                    .lineSpacing(6)
                if item.kind == .selfRating {
                    Button { speech.speak(item.word.term) } label: { Label("听发音", systemImage: "speaker.wave.2.fill") }
                        .font(.caption.bold()).foregroundStyle(CiJingTheme.purple)
                }
            }

            if item.kind == .selfRating && revealed {
                Divider()
                Text(item.answer).font(.title3.bold()).foregroundStyle(CiJingTheme.purpleDark)
                if let sentence = item.sentence { Text(sentence).font(.subheadline).foregroundStyle(CiJingTheme.secondary) }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 155, alignment: item.kind == .meaningChoice ? .center : .leading)
        .cijingCard(padding: 20)
    }

    private func promptEyebrow(_ item: PracticeQuestion) -> String {
        switch item.kind {
        case .meaningChoice: "这个单词是什么意思？"
        case .clozeChoice: "选择最适合填入空白的单词"
        case .spelling: "根据中文释义拼出英文单词"
        case .contextChoice: "这个词在句子中是什么意思？"
        case .selfRating: "先在脑海里回忆，再查看答案"
        }
    }

    @ViewBuilder private func answerArea(_ item: PracticeQuestion) -> some View {
        switch item.kind {
        case .meaningChoice, .clozeChoice, .contextChoice:
            VStack(spacing: 10) {
                ForEach(item.options, id: \.self) { option in
                    Button {
                        if !revealed { submit(item, answer: option, quality: option == item.answer ? 4 : 1) }
                    } label: {
                        HStack(spacing: 12) {
                            Text(option).multilineTextAlignment(.leading)
                            Spacer()
                            if revealed && option == item.answer { Image(systemName: "checkmark.circle.fill").foregroundStyle(CiJingTheme.success) }
                            else if revealed && selected == option { Image(systemName: "xmark.circle.fill").foregroundStyle(CiJingTheme.danger) }
                        }
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 57)
                        .background(optionBackground(option, item: item), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(optionBorder(option, item: item)))
                        .foregroundStyle(CiJingTheme.ink)
                    }
                    .buttonStyle(.plain)
                    .disabled(revealed)
                }
            }
        case .spelling:
            VStack(spacing: 12) {
                TextField("输入英文单词", text: $typed)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.title2.bold())
                    .padding(16)
                    .background(CiJingTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(CiJingTheme.line))
                    .disabled(revealed)
                Button("检查拼写") {
                    let normalized = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    submit(item, answer: typed, quality: normalized == item.answer.lowercased() ? 5 : 1)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(typed.isEmpty || revealed)
            }
        case .selfRating:
            if !revealed {
                Button("显示答案") { revealed = true }.buttonStyle(PrimaryButtonStyle())
            } else {
                HStack(spacing: 8) {
                    RatingButton(title: "忘了", color: .red) { submitRating(item, 1) }
                    RatingButton(title: "困难", color: .orange) { submitRating(item, 3) }
                    RatingButton(title: "记得", color: CiJingTheme.purple) { submitRating(item, 4) }
                    RatingButton(title: "轻松", color: .teal) { submitRating(item, 5) }
                }
                .disabled(feedbackPresented)
            }
        }
    }

    private func feedbackSheet(_ item: PracticeQuestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Capsule().fill(CiJingTheme.line).frame(width: 38, height: 5).frame(maxWidth: .infinity)
            Label(lastWasCorrect ? "太棒了！" : "再记一下", systemImage: lastWasCorrect ? "checkmark.circle.fill" : "arrow.counterclockwise.circle.fill")
                .font(.title3.bold())
                .foregroundStyle(lastWasCorrect ? CiJingTheme.success : .orange)
            Text("\(item.word.term)：\(item.word.displayMeaning)")
                .font(.subheadline.bold()).foregroundStyle(CiJingTheme.ink)
            if let example = item.word.exampleEn ?? item.sentence {
                Text("例句：\(example)").font(.caption).foregroundStyle(CiJingTheme.secondary).lineLimit(2)
            }
            Button(index == activeQuestions.count - 1 ? "完成本轮" : "继续") { next() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(18)
        .background(CiJingTheme.surface, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 25).stroke(CiJingTheme.line))
        .shadow(color: CiJingTheme.purpleDark.opacity(0.18), radius: 24, y: 8)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var wrongReviewView: some View {
        VStack(spacing: 22) {
            Spacer()
            VStack(spacing: 15) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 67, height: 67)
                    .background(CiJingTheme.roseFill, in: Circle())
                Text("错题回顾").font(.system(size: 24, weight: .bold, design: .rounded))
                Text("再来一遍，直到全对").font(.subheadline).foregroundStyle(CiJingTheme.secondary)
                Text("还有 \(pendingWrong.count) 道题需要攻克 · 第 \(retryRound + 1) 轮")
                    .font(.caption.bold()).foregroundStyle(CiJingTheme.purple)
                    .padding(.horizontal, 13).padding(.vertical, 7)
                    .background(CiJingTheme.purpleSoft, in: Capsule())
            }
            .frame(maxWidth: .infinity)
            .cijingCard(padding: 26)
            Spacer()
            Button { startRetry() } label: { Label("再来一遍", systemImage: "arrow.counterclockwise") }
                .buttonStyle(PrimaryButtonStyle())
            Button("跳过剩余，查看总结") { showSummary() }
                .font(.subheadline.bold()).foregroundStyle(CiJingTheme.secondary)
        }
        .padding(24)
    }

    private var summaryView: some View {
        ScrollView {
            VStack(spacing: 17) {
                VStack(spacing: 7) {
                    Image(systemName: "flame.fill").font(.system(size: 48)).foregroundStyle(.orange)
                    Text("今日学习完成！").font(.system(size: 28, weight: .bold, design: .rounded))
                    Label("连续学习 \(max(1, store.plan.streakDays)) 天，火苗越烧越旺！", systemImage: "flame")
                        .font(.subheadline.bold()).foregroundStyle(.orange)
                }

                HStack {
                    Label("今日挑战 · 攻克 \(missedWords.count) 个错题词", systemImage: "shield.lefthalf.filled")
                        .font(.caption.bold()).foregroundStyle(CiJingTheme.ink)
                    Spacer()
                    Text("\(max(0, missedWords.count - pendingWrong.count))/\(missedWords.count)")
                        .font(.caption.bold()).foregroundStyle(CiJingTheme.purple)
                }.cijingCard()

                HStack(spacing: 18) {
                    AccuracyRing(progress: overallAccuracy)
                    VStack(alignment: .leading, spacing: 8) {
                        SummaryLegend(color: CiJingTheme.purple, text: "今日新学  \(reading.targetTerms.count)")
                        SummaryLegend(color: CiJingTheme.rose, text: "复习  \(questions.count)")
                        SummaryLegend(color: CiJingTheme.success, text: "答对  \(directCorrect.count)")
                        SummaryLegend(color: CiJingTheme.danger, text: "待加强  \(missedWords.count)")
                    }
                    Spacer()
                }.cijingCard()

                VStack(alignment: .leading, spacing: 14) {
                    Text("各项能力表现").font(.headline)
                    AbilityRow(title: "认读", progress: performance(.meaningChoice), color: .orange)
                    AbilityRow(title: "拼写", progress: performance(.spelling), color: .orange)
                    AbilityRow(title: "听力", progress: performance(.clozeChoice), color: .orange)
                    AbilityRow(title: "口语", progress: performance(.selfRating), color: CiJingTheme.success)
                    AbilityRow(title: "语境", progress: performance(.contextChoice), color: .orange)
                    Text("对比的是你最近的整体正确率").font(.caption2).foregroundStyle(CiJingTheme.secondary)
                }.cijingCard()

                if !missedWords.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Label("需要加强的词", systemImage: "heart.slash")
                            .font(.headline).foregroundStyle(CiJingTheme.danger).padding(.bottom, 8)
                        ForEach(Array(missedWords.prefix(5).enumerated()), id: \.element.id) { offset, word in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(word.term).font(.subheadline.bold())
                                    Text(word.displayMeaning).font(.caption).foregroundStyle(CiJingTheme.secondary)
                                }
                                Spacer()
                                Text("待加强").font(.caption.bold()).foregroundStyle(CiJingTheme.danger)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(CiJingTheme.secondary)
                            }
                            .padding(.vertical, 10)
                            if offset < min(4, missedWords.count - 1) { Divider() }
                        }
                    }.cijingCard()
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lightbulb.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("下次建议").font(.subheadline.bold())
                        Text(missedWords.isEmpty ? "保持现在的节奏，明天会加入更多语境练习。" : "优先复习上面的薄弱词，并安排更多拼写与语境练习。")
                            .font(.caption).foregroundStyle(CiJingTheme.secondary)
                    }
                }.cijingCard()

            }
            .padding(20)
            .padding(.bottom, 86)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button { finish() } label: { Label("完成", systemImage: "checkmark") }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
        }
    }

    private func badgeOverlay(_ unlock: AchievementUnlock) -> some View {
        let tint = unlock.tier.color
        return ZStack {
            Color.black.opacity(0.34).ignoresSafeArea()
            VStack(spacing: 17) {
                Text(unlock.tier == .bronze ? "徽章解锁！" : "徽章升级！")
                    .font(.title2.bold())
                    .foregroundStyle(CiJingTheme.secondary)
                ZStack {
                    Circle().fill(tint.opacity(0.14)).frame(width: 132, height: 132)
                    Circle().stroke(tint.opacity(0.7), lineWidth: 3).frame(width: 112, height: 112)
                    Image(systemName: unlock.track.icon).font(.system(size: 46, weight: .bold)).foregroundStyle(tint)
                }
                HStack(spacing: 7) {
                    Text(unlock.title).font(.system(size: 25, weight: .bold, design: .rounded))
                    Text(unlock.tier.title)
                        .font(.caption.bold())
                        .foregroundStyle(tint)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(tint.opacity(0.12), in: Capsule())
                }
                Text(unlock.requirement).foregroundStyle(CiJingTheme.secondary)
                if let next = unlock.track.next(after: unlock.tier) {
                    Text("下一档 · \(unlock.track.title(for: next.tier))（\(unlock.track.requirement(next.threshold))）")
                        .font(.caption)
                        .foregroundStyle(CiJingTheme.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("这条线已经满级").font(.caption).foregroundStyle(tint)
                }
                Button("收下徽章") {
                    unlockedAchievement = nil
                    requestReviewIfEarned()
                }.buttonStyle(PrimaryButtonStyle())
            }
            .padding(28)
            .frame(maxWidth: 330)
            .background(CiJingTheme.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 30, y: 12)
            .padding(24)
        }
    }

    /// 徽章弹窗刚给完正反馈，这是整个流程里用户最愿意打分的一刻，转化率最高。
    ///
    /// 等 0.8 秒是为了让徽章弹窗的收起动画走完：两个弹层叠在一起时系统弹窗会被顶掉，
    /// 而配额照扣——那是最亏的一种失败。
    private func requestReviewIfEarned() {
        guard AppReviewPrompt.shouldRequest(streakDays: store.plan.streakDays) else { return }
        AppReviewPrompt.recordRequest()
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            requestReview()
        }
    }

    private var overallAccuracy: Double {
        Double(directCorrect.count) / Double(max(1, questions.count))
    }

    private func performance(_ kind: ExerciseKind) -> Double {
        Double(correctByKind[kind, default: 0]) / Double(max(1, attemptsByKind[kind, default: 0]))
    }

    private func buildQuestions() {
        let targetWords = reading.targetWordIds.compactMap { id in store.words.first { $0.id == id } }
        let meanings = targetWords.map(\.displayMeaning)
        questions = targetWords.enumerated().map { offset, word in
            let kind: ExerciseKind = [.meaningChoice, .clozeChoice, .spelling, .contextChoice, .selfRating][offset % 5]
            let paragraph = reading.paragraphs.first { $0.english.localizedCaseInsensitiveContains(word.lemma) || $0.english.localizedCaseInsensitiveContains(word.term) }
            let sentence = paragraph?.english.split(whereSeparator: { ".!?".contains($0) }).map(String.init)
                .first { $0.localizedCaseInsensitiveContains(word.lemma) || $0.localizedCaseInsensitiveContains(word.term) }?
                .trimmingCharacters(in: .whitespaces)
            switch kind {
            case .meaningChoice:
                return PracticeQuestion(word: word, kind: kind, prompt: word.term, options: choices(correct: word.displayMeaning, pool: meanings), answer: word.displayMeaning, sentence: sentence)
            case .clozeChoice:
                let source = sentence ?? word.exampleEn ?? word.term
                let cloze = source.replacingOccurrences(of: word.term, with: "______", options: .caseInsensitive)
                    .replacingOccurrences(of: word.lemma, with: "______", options: .caseInsensitive)
                return PracticeQuestion(word: word, kind: kind, prompt: cloze, options: choices(correct: word.term, pool: targetWords.map(\.term)), answer: word.term, sentence: sentence)
            case .spelling:
                return PracticeQuestion(word: word, kind: kind, prompt: word.displayMeaning, options: [], answer: word.term, sentence: sentence)
            case .contextChoice:
                let expected = word.contextualMeaning ?? word.displayMeaning
                return PracticeQuestion(word: word, kind: kind, prompt: sentence ?? word.term, options: choices(correct: expected, pool: targetWords.map { $0.contextualMeaning ?? $0.displayMeaning }), answer: expected, sentence: sentence)
            case .selfRating:
                return PracticeQuestion(word: word, kind: kind, prompt: word.term, options: [], answer: word.displayMeaning, sentence: sentence)
            }
        }
        activeQuestions = questions
    }

    private func choices(correct: String, pool: [String]) -> [String] {
        ([correct] + Array(pool.filter { $0 != correct }.shuffled().prefix(3))).shuffled()
    }

    private func optionBackground(_ option: String, item: PracticeQuestion) -> Color {
        if revealed && option == item.answer { return CiJingTheme.success.opacity(0.12) }
        if revealed && selected == option { return CiJingTheme.danger.opacity(0.12) }
        // Keep the surface and `CiJingTheme.ink` adaptive as a pair. A hard-coded
        // white background made the dark-mode ink (also light) nearly invisible.
        return CiJingTheme.surface
    }

    private func optionBorder(_ option: String, item: PracticeQuestion) -> Color {
        if revealed && option == item.answer { return CiJingTheme.success.opacity(0.55) }
        if revealed && selected == option { return CiJingTheme.danger.opacity(0.55) }
        return CiJingTheme.line
    }

    private func submit(_ item: PracticeQuestion, answer: String, quality: Int) {
        guard !feedbackPresented else { return }
        selected = answer
        revealed = true
        recordOutcome(item, quality: quality)
        feedbackPresented = true
        let ms = Int(Date().timeIntervalSince(startedAt) * 1000)
        Task { await store.recordReview(word: item.word, quality: quality, type: item.kind.rawValue, answer: answer, expected: item.answer, milliseconds: ms) }
    }

    private func submitRating(_ item: PracticeQuestion, _ quality: Int) {
        guard !feedbackPresented else { return }
        selected = quality >= 4 ? "记得" : "需要复习"
        recordOutcome(item, quality: quality)
        feedbackPresented = true
        Task {
            await store.recordReview(word: item.word, quality: quality, type: item.kind.rawValue, answer: selected, expected: item.answer, milliseconds: Int(Date().timeIntervalSince(startedAt) * 1000))
        }
    }

    private func recordOutcome(_ item: PracticeQuestion, quality: Int) {
        let correct = quality >= 4
        lastWasCorrect = correct
        store.playHaptic(correct ? .answerCorrect : .answerIncorrect)
        attemptsByKind[item.kind, default: 0] += 1
        if correct { correctByKind[item.kind, default: 0] += 1 }

        if !retrying && correct { directCorrect.insert(item.id) }
        if correct && retrying {
            pendingWrong.removeAll { $0.id == item.id }
        } else if !correct {
            if !pendingWrong.contains(where: { $0.id == item.id }) { pendingWrong.append(item) }
            if !missedWords.contains(where: { $0.id == item.word.id }) { missedWords.append(item.word) }
        }
    }

    private func next() {
        feedbackPresented = false
        if index < activeQuestions.count - 1 {
            index += 1
            resetAnswer()
        } else if pendingWrong.isEmpty {
            showSummary()
        } else {
            stage = .wrongReview
            resetAnswer()
        }
    }

    private func startRetry() {
        retryRound += 1
        retrying = true
        activeQuestions = pendingWrong.shuffled()
        index = 0
        stage = .questions
        resetAnswer()
    }

    private func showSummary() {
        feedbackPresented = false
        stage = .summary
        store.playHaptic(.completion)
        // 走到总结页就是今日完成——包括「跳过剩余，查看总结」。这是唯一的判定点，
        // 服务端不再按题量推断，页面文案与首页卡片自此不会再互相矛盾。
        Task {
            let unlock = await store.markDailySessionComplete()
            // 只有真的跨过一档才弹。以前这里无条件弹同一枚硬编码的「初来乍到」，
            // 从第二次学习起就是假的。
            guard let unlock else { return }
            try? await Task.sleep(for: .milliseconds(280))
            unlockedAchievement = unlock
        }
    }

    private func resetAnswer() {
        selected = nil
        typed = ""
        revealed = false
        startedAt = .now
    }

    private func finish() {
        if let onFinish { onFinish() }
        else { dismiss() }
    }
}

private struct RatingButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.caption.bold()).frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(color)
        }.buttonStyle(.plain)
    }
}

private struct AccuracyRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.orange.opacity(0.16), lineWidth: 10)
            Circle().trim(from: 0, to: progress).stroke(.orange, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90))
            Text("\(Int(progress * 100))%\n正确")
                .font(.system(size: 15, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
        }.frame(width: 104, height: 104)
    }
}

private struct SummaryLegend: View {
    let color: Color
    let text: String
    var body: some View { HStack(spacing: 8) { Circle().fill(color).frame(width: 7, height: 7); Text(text).font(.caption) } }
}

private struct AbilityRow: View {
    let title: String
    let progress: Double
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.caption).foregroundStyle(CiJingTheme.secondary).frame(width: 32, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(CiJingTheme.canvas)
                    Capsule().fill(color).frame(width: proxy.size.width * progress)
                }
            }.frame(height: 7)
            Text("\(Int(progress * 100))%").font(.caption.bold()).frame(width: 40, alignment: .trailing)
        }
    }
}
