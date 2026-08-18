import Foundation
import SwiftUI

enum WordStatus: String, Codable, CaseIterable, Identifiable {
    case new, learning, review, weak, mastered, ignored
    var id: String { rawValue }
    var title: String {
        switch self { case .new: "新词"; case .learning: "学习中"; case .review: "待复习"; case .weak: "薄弱词"; case .mastered: "已掌握"; case .ignored: "已忽略" }
    }
    var icon: String {
        switch self { case .new: "sparkles"; case .learning: "leaf"; case .review: "clock.arrow.circlepath"; case .weak: "bolt.heart"; case .mastered: "checkmark.seal.fill"; case .ignored: "eye.slash" }
    }
    var color: Color {
        switch self { case .new: .blue; case .learning: CiJingTheme.green; case .review: .orange; case .weak: .red; case .mastered: .mint; case .ignored: .gray }
    }
}

struct LexiconPart: Codable, Hashable, Identifiable {
    var id: String { partOfSpeech + meaning }
    let partOfSpeech: String
    let meaning: String
}

struct DictionaryLicense: Codable, Hashable, Identifiable {
    var id: String { url }
    let name: String
    let url: String
}

struct DictionaryAudioAttribution: Codable, Hashable {
    let sourceUrl: String
    let license: DictionaryLicense
}

struct DictionaryAttribution: Codable, Hashable {
    let provider: String
    let providerUrl: String
    let sourceUrls: [String]
    let licenses: [DictionaryLicense]
    let audio: DictionaryAudioAttribution?
}

struct Word: Codable, Hashable, Identifiable {
    let id: UUID
    let userId: UUID?
    var term: String
    var normalizedTerm: String
    var lemma: String
    var phonetic: String?
    var audioUrl: String?
    var parts: [LexiconPart]
    var primaryMeaning: String
    var contextualMeaning: String?
    var englishDefinition: String?
    var exampleEn: String?
    var exampleZh: String?
    var firstContext: String?
    var firstSourceUrl: String?
    var firstSourceTitle: String?
    var dictionaryAttribution: DictionaryAttribution? = nil
    var notes: String
    var customMeaning: String?
    var status: WordStatus
    var strength: Double
    var easeFactor: Double
    var intervalDays: Int
    var repetitions: Int
    var lapses: Int
    var lookupCount: Int
    var errorCount: Int
    var dueAt: String
    var lastReviewedAt: String?
    var masteredAt: String?
    var createdAt: String
    var updatedAt: String

    var displayMeaning: String { customMeaning?.isEmpty == false ? customMeaning! : primaryMeaning }
    var isDue: Bool { ISO8601DateFormatter().date(from: dueAt).map { $0 <= .now } ?? false }
}

struct WordContext: Codable, Identifiable {
    let id: UUID
    let wordId: UUID
    let contextText: String
    let contextualMeaning: String?
    let sentence: String?
    let sourceUrl: String?
    let sourceTitle: String?
    let createdAt: String
}

struct ReviewEvent: Codable, Identifiable {
    let id: UUID
    let wordId: UUID
    let quality: Int
    let exerciseType: String
    let responseTimeMs: Int?
    let answer: String?
    let expectedAnswer: String?
    let createdAt: String
}

struct DailyPlan: Codable {
    var reviewDue: Int = 0
    var newSuggested: Int = 0
    var weakCount: Int = 0
    var learnedCount: Int = 0
    var masteredCount: Int = 0
    var streakDays: Int = 0
    var reviewedToday: Int = 0
    var practiceToday: Int = 0
    var readingToday: Int = 0
    var generationToday: Int = 0
    var readingTotal: Int = 0
    var completedToday: Bool = false
    var dailyNewGoal: Int = 8
    var dailyReviewGoal: Int = 20

    var totalToday: Int { reviewDue + newSuggested }
    var progress: Double { min(1, Double(reviewedToday) / Double(max(1, totalToday))) }
}

struct Profile: Codable {
    let id: UUID
    var displayName: String?
    var dailyNewGoal: Int
    var dailyReviewGoal: Int
    var preferredDifficulty: String
    var preferredTheme: String
    var preferredStyle: String
    var preferredVoiceIdentifier: String
    var timezone: String
}

struct DailyActivity: Codable, Identifiable {
    var id: String { activityDate }
    let activityDate: String
    let learnedCount: Int
    let reviewedCount: Int
    let readingCount: Int
    let practiceCount: Int
    let minutes: Int
    let completed: Bool
}

struct ReadingParagraph: Codable, Hashable, Identifiable {
    var id: String { english }
    let english: String
    let chinese: String
}

struct ReadingSession: Codable, Identifiable {
    let id: UUID
    let userId: UUID?
    let title: String
    let subtitle: String?
    let theme: String
    let style: String
    let difficulty: String
    let targetWordIds: [UUID]
    let targetTerms: [String]
    let paragraphs: [ReadingParagraph]
    let estimatedMinutes: Int
    let cacheKey: String?
    let isCached: Bool
    let translationsVisible: Bool
    let completedAt: String?
    let createdAt: String
}

struct LookupResult: Codable {
    let term: String
    let lemma: String
    let phonetic: String
    let audioUrl: String?
    let parts: [LexiconPart]
    let primaryMeaning: String
    let contextualMeaning: String
    let englishDefinition: String
    let exampleEnglish: String
    let exampleChinese: String
    let sentence: String
    var dictionaryAttribution: DictionaryAttribution? = nil
}

struct ReadingWordExplanation: Codable {
    let term: String
    let lemma: String
    let phonetic: String
    let partOfSpeech: String
    let meaning: String
    let contextualMeaning: String
    let sentence: String
    var dictionaryAttribution: DictionaryAttribution? = nil
}

struct EdgeResponse<T: Codable>: Codable { let data: T; let cached: Bool? }
struct AuthUser: Codable { let id: UUID; let email: String? }
struct AuthSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let expiresAt: Int
    let tokenType: String?
    let user: AuthUser
}

struct EmptyBody: Codable {}
struct SaveWordPayload: Codable {
    let term, lemma: String
    let phonetic: String?
    let audioUrl: String?
    let parts: [LexiconPart]
    let primaryMeaning: String
    let contextualMeaning: String?
    let englishDefinition: String?
    let exampleEn: String?
    let exampleZh: String?
    let context: String?
    let sentence: String?
    let sourceUrl: String?
    let sourceTitle: String?
    var dictionaryAttribution: DictionaryAttribution? = nil
}

struct APIErrorPayload: Codable { let message: String?; let error: String?; let errorDescription: String?; let msg: String? }

enum FeedbackCategory: String, Codable, CaseIterable, Identifiable {
    case bug, suggestion, content, account, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .bug: "问题反馈"
        case .suggestion: "功能建议"
        case .content: "内容纠错"
        case .account: "账号与数据"
        case .other: "其他"
        }
    }

    var icon: String {
        switch self {
        case .bug: "exclamationmark.triangle"
        case .suggestion: "lightbulb"
        case .content: "text.badge.xmark"
        case .account: "person.badge.key"
        case .other: "ellipsis.bubble"
        }
    }

    /// 输入框的占位文案。分类不同，我们需要的信息也不同——提示写在这里，
    /// 比事后回邮件追问「你用的哪个版本」省一个来回。
    var placeholder: String {
        switch self {
        case .bug: "描述你遇到的问题：在哪个页面、点了什么、看到什么结果。版本和机型会自动附上。"
        case .suggestion: "你希望词鲸多做点什么？说说你打算用它解决的问题。"
        case .content: "哪个单词或哪篇短文的内容不对？把原文和你认为正确的说法一起写下来。"
        case .account: "描述账号或数据上的异常。请勿填写密码、验证码或访问令牌。"
        case .other: "你可以描述你遇到的问题"
        }
    }
}

enum FeedbackStatus: String, Codable {
    case open
    case inProgress = "in_progress"
    case resolved

    var title: String {
        switch self {
        case .open: "待处理"
        case .inProgress: "处理中"
        case .resolved: "已回复"
        }
    }
}

/// 客户端提交的一条反馈。`userId` 由数据库默认值 `auth.uid()` 填，不从客户端传。
struct FeedbackDraft: Codable {
    let category: FeedbackCategory
    let content: String
    let contact: String?
    let appVersion: String
    let device: String
    let osVersion: String
}

struct FeedbackItem: Codable, Identifiable {
    let id: UUID
    let category: FeedbackCategory
    let content: String
    let status: FeedbackStatus
    let reply: String?
    let createdAt: String
    let repliedAt: String?
}
