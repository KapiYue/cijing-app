import Foundation

enum CiJingAPIError: LocalizedError {
    case invalidResponse
    case unauthenticated
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "服务器返回了无法解析的数据"
        case .unauthenticated: "登录已过期，请重新登录"
        case .server(let message): message
        }
    }
}

/// 请求被取消不是故障：切 Tab 会销毁上一个页面并连带取消它的 `.task`，
/// 下拉刷新连拉两次也会取消前一次。这类错误一律不该弹给用户——1.0 正式版
/// 里它们表现为切 Tab 和下拉刷新时偶发的「用户取消」提示。
func isCancellationError(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return true }
    if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError { return true }
    return false
}

@MainActor
final class SupabaseAPI: ObservableObject {
    @Published private(set) var session: AuthSession?
    @Published var isAuthenticating = false

    private let urlSession: URLSession
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase; return decoder
    }()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase; return encoder
    }()

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        if let data = KeychainStore.load(), let saved = try? decoder.decode(AuthSession.self, from: data) { session = saved }
    }

    var currentEmail: String { session?.user.email ?? "学习者" }
    var currentUserID: UUID? { session?.user.id }
    var isSignedIn: Bool { session != nil }

    func signIn(email: String, password: String) async throws {
        isAuthenticating = true; defer { isAuthenticating = false }
        let credentials = try AuthCredentialRules.validate(email: email, password: password, mode: .signIn)
        do {
            let body = try encoder.encode(Credentials(email: credentials.email, password: credentials.password))
            let value: AuthSession = try await send(path: "/auth/v1/token?grant_type=password", method: "POST", body: body, authenticated: false)
            persist(value)
        } catch {
            let compatiblePassword = AuthCredentialRules.compatibilityPassword(credentials.password)
            guard compatiblePassword != password, Self.isInvalidCredentials(error) else { throw error }
            let body = try encoder.encode(Credentials(email: credentials.email, password: compatiblePassword))
            let value: AuthSession = try await send(path: "/auth/v1/token?grant_type=password", method: "POST", body: body, authenticated: false)
            persist(value)
        }
    }

    func signUp(email: String, password: String) async throws {
        isAuthenticating = true; defer { isAuthenticating = false }
        let credentials = try AuthCredentialRules.validate(email: email, password: password, mode: .signUp)
        let body = try encoder.encode(Credentials(email: credentials.email, password: credentials.password))
        let value: SignupResponse = try await send(path: "/auth/v1/signup", method: "POST", body: body, authenticated: false)
        if value.accessToken != nil || value.refreshToken != nil {
            throw CiJingAPIError.server("邮箱验证服务暂时不可用，为保护账号安全，本次未登录。请稍后重试或联系支持人员。")
        }
    }

    func signOut() async {
        if let token = session?.accessToken {
            _ = try? await sendData(path: "/auth/v1/logout", method: "POST", body: nil, token: token)
        }
        session = nil; KeychainStore.clear()
    }

    func deleteAccount() async throws {
        let token = try await validToken()
        _ = try await sendData(
            path: "/functions/v1/delete-account",
            method: "POST",
            body: try encoder.encode(EmptyBody()),
            token: token
        )
        session = nil
        KeychainStore.clear()
    }

    private func persist(_ value: AuthSession) {
        session = value
        if let data = try? encoder.encode(value) { KeychainStore.save(data) }
    }

    private func validToken() async throws -> String {
        guard let existing = session else { throw CiJingAPIError.unauthenticated }
        if existing.expiresAt > Int(Date().timeIntervalSince1970) + 60 { return existing.accessToken }
        let body = try encoder.encode(RefreshBody(refreshToken: existing.refreshToken))
        do {
            let refreshed: AuthSession = try await send(path: "/auth/v1/token?grant_type=refresh_token", method: "POST", body: body, authenticated: false)
            persist(refreshed); return refreshed.accessToken
        } catch {
            session = nil; KeychainStore.clear(); throw CiJingAPIError.unauthenticated
        }
    }

    private func send<T: Decodable>(path: String, method: String = "GET", body: Data? = nil, authenticated: Bool = true, headers: [String: String] = [:]) async throws -> T {
        let token = authenticated ? try await validToken() : nil
        let (data, _) = try await sendData(path: path, method: method, body: body, token: token, headers: headers)
        do { return try decoder.decode(T.self, from: data) }
        catch { throw CiJingAPIError.server("数据解析失败：\(error.localizedDescription)") }
    }

    @discardableResult
    private func sendData(path: String, method: String, body: Data?, token: String?, headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: path, relativeTo: AppConfig.supabaseURL) else { throw CiJingAPIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 45
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(AppConfig.supabasePublishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CiJingAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let payload = try? decoder.decode(APIErrorPayload.self, from: data)
            let fallback = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            let message = payload?.message ?? payload?.errorDescription ?? payload?.msg ?? payload?.error ?? fallback
            let normalized = message.lowercased()
            if normalized.contains("user already registered") || normalized.contains("already been registered") {
                throw CiJingAPIError.server("该邮箱已注册，请直接登录。")
            }
            if path.contains("/auth/v1/token") {
                if normalized.contains("email not confirmed") {
                    throw CiJingAPIError.server("邮箱尚未验证，请先打开验证邮件完成确认。")
                }
                if normalized.contains("invalid login credentials") {
                    throw CiJingAPIError.server("邮箱或密码不正确。")
                }
            }
            throw http.statusCode == 401 ? CiJingAPIError.unauthenticated : CiJingAPIError.server(message)
        }
        return (data, http)
    }

    private static func isInvalidCredentials(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("invalid login credentials") || message.contains("邮箱或密码不正确")
    }

    func dailyPlan() async throws -> DailyPlan {
        try await send(path: "/rest/v1/rpc/get_daily_plan", method: "POST", body: encoder.encode(EmptyBody()))
    }

    func words() async throws -> [Word] {
        try await send(path: "/rest/v1/words?select=*&order=created_at.desc")
    }

    func profile() async throws -> Profile? {
        let rows: [Profile] = try await send(path: "/rest/v1/profiles?select=*&limit=1")
        return rows.first
    }

    func activity() async throws -> [DailyActivity] {
        try await send(path: "/rest/v1/daily_activity?select=*&order=activity_date.desc&limit=30")
    }

    func updateProfile(_ profile: Profile) async throws -> Profile {
        let body = try encoder.encode(ProfilePatch(displayName: profile.displayName, dailyNewGoal: profile.dailyNewGoal, dailyReviewGoal: profile.dailyReviewGoal, preferredDifficulty: profile.preferredDifficulty, preferredTheme: profile.preferredTheme, preferredStyle: profile.preferredStyle, preferredVoiceIdentifier: profile.preferredVoiceIdentifier, timezone: profile.timezone))
        let rows: [Profile] = try await send(path: "/rest/v1/profiles?id=eq.\(profile.id.uuidString)", method: "PATCH", body: body, headers: ["Prefer": "return=representation"])
        guard let value = rows.first else { throw CiJingAPIError.invalidResponse }; return value
    }

    func learningTargets(limit: Int = 10) async throws -> [Word] {
        try await send(path: "/rest/v1/rpc/get_learning_targets", method: "POST", body: encoder.encode(TargetLimit(pLimit: limit)))
    }

    func contexts(wordID: UUID) async throws -> [WordContext] {
        try await send(path: "/rest/v1/word_contexts?select=*&word_id=eq.\(wordID.uuidString)&order=created_at.desc")
    }

    func reviewEvents(wordID: UUID) async throws -> [ReviewEvent] {
        try await send(path: "/rest/v1/review_events?select=*&word_id=eq.\(wordID.uuidString)&order=created_at.desc&limit=30")
    }

    func saveWord(_ payload: SaveWordPayload) async throws -> Word {
        try await send(path: "/rest/v1/rpc/save_word", method: "POST", body: encoder.encode(SaveRPCPayload(pPayload: payload)), headers: ["Accept": "application/vnd.pgrst.object+json"])
    }

    func updateWord(id: UUID, notes: String? = nil, customMeaning: String? = nil, status: WordStatus? = nil) async throws -> Word {
        let body = try encoder.encode(WordPatch(notes: notes, customMeaning: customMeaning, status: status))
        let rows: [Word] = try await send(path: "/rest/v1/words?id=eq.\(id.uuidString)", method: "PATCH", body: body, headers: ["Prefer": "return=representation"])
        guard let word = rows.first else { throw CiJingAPIError.invalidResponse }; return word
    }

    func deleteWord(id: UUID) async throws {
        let token = try await validToken()
        _ = try await sendData(path: "/rest/v1/words?id=eq.\(id.uuidString)", method: "DELETE", body: nil, token: token)
    }

    func generateReading(targetWordIDs: [UUID], theme: String, style: String, difficulty: String, regenerate: Bool) async throws -> ReadingSession {
        let body = try encoder.encode(GenerateReadingBody(targetWordIds: targetWordIDs, theme: theme, style: style, difficulty: difficulty, regenerate: regenerate, wordCount: min(12, max(5, targetWordIDs.count))))
        let response: EdgeResponse<ReadingSession> = try await send(path: "/functions/v1/generate-reading", method: "POST", body: body)
        return response.data
    }

    func lookupWord(_ term: String, context: String = "", sentence: String = "") async throws -> LookupResult {
        let body = try encoder.encode(LookupBody(word: term, context: context, sentence: sentence))
        let response: EdgeResponse<LookupResult> = try await send(path: "/functions/v1/lookup-word", method: "POST", body: body)
        return response.data
    }

    func explainReadingWord(_ term: String, sentence: String) async throws -> ReadingWordExplanation {
        let body = try encoder.encode(ExplainBody(word: term, sentence: sentence))
        let response: EdgeResponse<ReadingWordExplanation> = try await send(path: "/functions/v1/explain-reading-word", method: "POST", body: body)
        return response.data
    }

    func applyReview(wordID: UUID, quality: Int, exerciseType: String, answer: String?, expected: String?, responseTime: Int?) async throws -> Word {
        let body = try encoder.encode(ReviewBody(pWordId: wordID, pQuality: quality, pExerciseType: exerciseType, pResponseTimeMs: responseTime, pAnswer: answer, pExpectedAnswer: expected))
        return try await send(path: "/rest/v1/rpc/apply_review", method: "POST", body: body, headers: ["Accept": "application/vnd.pgrst.object+json"])
    }

    func completeReading(id: UUID, minutes: Int) async throws {
        let token = try await validToken()
        _ = try await sendData(path: "/rest/v1/rpc/mark_reading_complete", method: "POST", body: encoder.encode(CompleteBody(pReadingId: id, pMinutes: minutes)), token: token)
    }

    func recentReadings() async throws -> [ReadingSession] {
        try await send(path: "/rest/v1/reading_sessions?select=*&order=created_at.desc&limit=20")
    }

    /// 走到练习总结页即视为今日完成。服务端不再自行推断，返回刷新后的今日计划。
    func completeDailySession() async throws -> DailyPlan {
        try await send(path: "/rest/v1/rpc/complete_daily_session", method: "POST", body: encoder.encode(EmptyBody()))
    }

    /// 幂等地记录一次成就解锁；`newlyUnlocked` 为 false 表示这一档早已拿到过。
    func unlockAchievement(track: String, tier: Int) async throws -> AchievementUnlockResult {
        try await send(
            path: "/rest/v1/rpc/unlock_achievement",
            method: "POST",
            body: encoder.encode(UnlockBody(pTrack: track, pTier: tier))
        )
    }
}

private struct Credentials: Codable { let email, password: String }
private struct SignupResponse: Codable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let expiresAt: Int?
    let tokenType: String?
    let user: AuthUser?
}
private struct RefreshBody: Codable { let refreshToken: String }
private struct UnlockBody: Codable { let pTrack: String; let pTier: Int }

struct AchievementUnlockResult: Codable {
    let track: String
    let tier: Int
    let newlyUnlocked: Bool
}
private struct TargetLimit: Codable { let pLimit: Int }
private struct SaveRPCPayload: Codable { let pPayload: SaveWordPayload }
private struct WordPatch: Codable { let notes: String?; let customMeaning: String?; let status: WordStatus? }
private struct GenerateReadingBody: Codable { let targetWordIds: [UUID]; let theme, style, difficulty: String; let regenerate: Bool; let wordCount: Int }
private struct LookupBody: Codable { let word, context, sentence: String }
private struct ExplainBody: Codable { let word, sentence: String }
private struct ReviewBody: Codable { let pWordId: UUID; let pQuality: Int; let pExerciseType: String; let pResponseTimeMs: Int?; let pAnswer: String?; let pExpectedAnswer: String? }
private struct CompleteBody: Codable { let pReadingId: UUID; let pMinutes: Int }
private struct ProfilePatch: Codable { let displayName: String?; let dailyNewGoal, dailyReviewGoal: Int; let preferredDifficulty, preferredTheme, preferredStyle, preferredVoiceIdentifier, timezone: String }
