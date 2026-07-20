import SwiftUI

private enum ExerciseKind: String { case meaningChoice, clozeChoice, spelling, contextChoice, selfRating
    var title: String { switch self { case .meaningChoice: "释义辨认"; case .clozeChoice: "语境完形"; case .spelling: "拼写回忆"; case .contextChoice: "语境含义"; case .selfRating: "主动回忆" } }
}

private struct PracticeQuestion: Identifiable {
    let id = UUID(); let word: Word; let kind: ExerciseKind; let prompt: String; let options: [String]; let answer: String; let sentence: String?
}

struct PracticeSessionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let reading: ReadingSession
    @State private var questions: [PracticeQuestion] = []
    @State private var index = 0
    @State private var selected: String?
    @State private var typed = ""
    @State private var revealed = false
    @State private var correctCount = 0
    @State private var startedAt = Date()

    private var done: Bool { index >= questions.count }
    private var question: PracticeQuestion? { done ? nil : questions[index] }

    var body: some View {
        ZStack {
            PaperBackground()
            if questions.isEmpty { ProgressView("正在准备练习…") }
            else if done { summary }
            else if let question { questionView(question) }
        }
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("退出") { dismiss() } } }
        .onAppear { buildQuestions() }
    }

    private func questionView(_ item: PracticeQuestion) -> some View {
        VStack(alignment: .leading, spacing: 21) {
            HStack { Text(item.kind.title).font(.caption.bold()).foregroundStyle(CiJingTheme.green); Spacer(); Text("\(index + 1) / \(questions.count)").font(.caption.bold()).foregroundStyle(CiJingTheme.secondary) }
            ProgressView(value: Double(index), total: Double(questions.count)).tint(CiJingTheme.green)
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                Text(item.prompt).font(.system(size: item.kind == .clozeChoice ? 22 : 27, weight: .bold, design: .serif)).lineSpacing(6)
                if item.kind == .selfRating && revealed { Text(item.answer).font(.title3.bold()).foregroundStyle(CiJingTheme.green); if let sentence = item.sentence { Text(sentence).foregroundStyle(CiJingTheme.secondary) } }
            }.frame(maxWidth: .infinity, minHeight: 160, alignment: .leading).cijingCard()
            answerArea(item)
            if revealed && item.kind != .selfRating { feedback(item) }
            Spacer()
            if revealed && item.kind != .selfRating { Button(index == questions.count - 1 ? "查看结果" : "下一题") { next() }.buttonStyle(PrimaryButtonStyle()) }
        }.padding(20)
    }

    @ViewBuilder private func answerArea(_ item: PracticeQuestion) -> some View {
        switch item.kind {
        case .meaningChoice, .clozeChoice, .contextChoice:
            VStack(spacing: 10) { ForEach(item.options, id: \.self) { option in Button { if !revealed { selected = option; submit(item, answer: option, quality: option == item.answer ? 4 : 1) } } label: { HStack { Text(option).multilineTextAlignment(.leading); Spacer(); if revealed && option == item.answer { Image(systemName: "checkmark.circle.fill") } else if revealed && selected == option { Image(systemName: "xmark.circle.fill") } }.padding(14).frame(maxWidth: .infinity).background(optionBackground(option, item: item), in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(CiJingTheme.ink) }.buttonStyle(.plain) } }
        case .spelling:
            VStack(spacing: 12) { TextField("输入英文单词", text: $typed).textInputAutocapitalization(.never).autocorrectionDisabled().font(.title2.bold()).padding(15).background(.white, in: RoundedRectangle(cornerRadius: 14)); Button("检查拼写") { let normalized = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(); submit(item, answer: typed, quality: normalized == item.answer.lowercased() ? 5 : 1) }.buttonStyle(PrimaryButtonStyle()).disabled(typed.isEmpty || revealed) }
        case .selfRating:
            if !revealed { Button("显示答案") { revealed = true }.buttonStyle(PrimaryButtonStyle()) }
            else { HStack(spacing: 8) { RatingButton(title: "忘了", color: .red) { submitRating(item, 1) }; RatingButton(title: "困难", color: .orange) { submitRating(item, 3) }; RatingButton(title: "记得", color: CiJingTheme.green) { submitRating(item, 4) }; RatingButton(title: "轻松", color: .teal) { submitRating(item, 5) } } }
        }
    }

    private func feedback(_ item: PracticeQuestion) -> some View {
        VStack(alignment: .leading, spacing: 7) { Label(selected == item.answer || (item.kind == .spelling && typed.lowercased() == item.answer.lowercased()) ? "答对了" : "再记一下", systemImage: selected == item.answer || typed.lowercased() == item.answer.lowercased() ? "checkmark.circle.fill" : "arrow.counterclockwise.circle.fill").font(.headline).foregroundStyle(selected == item.answer || typed.lowercased() == item.answer.lowercased() ? CiJingTheme.green : .orange); Text("答案：\(item.answer)").font(.subheadline); Text(item.word.displayMeaning).font(.subheadline).foregroundStyle(CiJingTheme.secondary) }.cijingCard()
    }

    private var summary: some View {
        VStack(spacing: 22) { Spacer(); Image(systemName: "checkmark.seal.fill").font(.system(size: 70)).foregroundStyle(CiJingTheme.green); Text("今日学习完成").font(.system(size: 32, weight: .bold, design: .serif)); Text("你完成了 \(questions.count) 道练习，\(correctCount) 次直接答对。复习计划已根据本次表现更新。 ").multilineTextAlignment(.center).foregroundStyle(CiJingTheme.secondary); HStack { PracticeStatCard(value: correctCount, title: "直接正确", icon: "checkmark", tint: CiJingTheme.green); PracticeStatCard(value: questions.count - correctCount, title: "继续巩固", icon: "arrow.clockwise", tint: .orange) }; Button("回到首页") { dismiss() }.buttonStyle(PrimaryButtonStyle()); Spacer() }.padding(24)
    }

    private func buildQuestions() {
        let targetWords = reading.targetWordIds.compactMap { id in store.words.first { $0.id == id } }
        let meanings = targetWords.map(\.displayMeaning)
        questions = targetWords.enumerated().map { offset, word in
            let kind: ExerciseKind = [.meaningChoice, .clozeChoice, .spelling, .contextChoice, .selfRating][offset % 5]
            let paragraph = reading.paragraphs.first { $0.english.localizedCaseInsensitiveContains(word.lemma) || $0.english.localizedCaseInsensitiveContains(word.term) }
            let sentence = paragraph?.english.split(whereSeparator: { ".!?".contains($0) }).map(String.init).first { $0.localizedCaseInsensitiveContains(word.lemma) || $0.localizedCaseInsensitiveContains(word.term) }?.trimmingCharacters(in: .whitespaces)
            switch kind {
            case .meaningChoice:
                return PracticeQuestion(word: word, kind: kind, prompt: word.term, options: choices(correct: word.displayMeaning, pool: meanings), answer: word.displayMeaning, sentence: sentence)
            case .clozeChoice:
                let cloze = (sentence ?? word.exampleEn ?? word.term).replacingOccurrences(of: word.term, with: "______", options: .caseInsensitive)
                return PracticeQuestion(word: word, kind: kind, prompt: cloze, options: choices(correct: word.term, pool: targetWords.map(\.term)), answer: word.term, sentence: sentence)
            case .spelling:
                return PracticeQuestion(word: word, kind: kind, prompt: word.displayMeaning, options: [], answer: word.term, sentence: sentence)
            case .contextChoice:
                let expected = word.contextualMeaning ?? word.displayMeaning
                return PracticeQuestion(word: word, kind: kind, prompt: sentence ?? word.term, options: choices(correct: expected, pool: targetWords.map { $0.contextualMeaning ?? $0.displayMeaning }), answer: expected, sentence: sentence)
            case .selfRating:
                return PracticeQuestion(word: word, kind: kind, prompt: "回忆 \(word.term) 的意思和一个使用场景", options: [], answer: word.displayMeaning, sentence: sentence)
            }
        }
    }

    private func choices(correct: String, pool: [String]) -> [String] { ([correct] + Array(pool.filter { $0 != correct }.shuffled().prefix(3))).shuffled() }
    private func optionBackground(_ option: String, item: PracticeQuestion) -> Color { if revealed && option == item.answer { return CiJingTheme.lightGreen }; if revealed && selected == option { return Color.red.opacity(0.12) }; return .white }
    private func submit(_ item: PracticeQuestion, answer: String, quality: Int) { guard !revealed else { return }; selected = answer; revealed = true; if quality >= 4 { correctCount += 1 }; let ms = Int(Date().timeIntervalSince(startedAt) * 1000); Task { await store.recordReview(word: item.word, quality: quality, type: item.kind.rawValue, answer: answer, expected: item.answer, milliseconds: ms) } }
    private func submitRating(_ item: PracticeQuestion, _ quality: Int) { if quality >= 4 { correctCount += 1 }; Task { await store.recordReview(word: item.word, quality: quality, type: item.kind.rawValue, answer: nil, expected: item.answer, milliseconds: Int(Date().timeIntervalSince(startedAt) * 1000)) }; next() }
    private func next() { index += 1; selected = nil; typed = ""; revealed = false; startedAt = .now }
}

private struct RatingButton: View { let title: String; let color: Color; let action: () -> Void; var body: some View { Button(action: action) { Text(title).font(.caption.bold()).frame(maxWidth: .infinity).padding(.vertical, 12).background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 11)).foregroundStyle(color) }.buttonStyle(.plain) } }
private struct PracticeStatCard: View { let value: Int; let title, icon: String; let tint: Color; var body: some View { VStack(alignment: .leading, spacing: 8) { Image(systemName: icon).foregroundStyle(tint); Text("\(value)").font(.title2.bold()); Text(title).font(.caption2).foregroundStyle(CiJingTheme.secondary) }.frame(maxWidth: .infinity, alignment: .leading).cijingCard() } }
