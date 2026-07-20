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
    let parts: [LexiconPart]
    let primaryMeaning: String
    let contextualMeaning: String
    let englishDefinition: String
    let exampleEnglish: String
    let exampleChinese: String
    let sentence: String
}

struct ReadingWordExplanation: Codable {
    let term: String
    let lemma: String
    let phonetic: String
    let partOfSpeech: String
    let meaning: String
    let contextualMeaning: String
    let sentence: String
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
}

struct APIErrorPayload: Codable { let message: String?; let error: String?; let errorDescription: String?; let msg: String? }
