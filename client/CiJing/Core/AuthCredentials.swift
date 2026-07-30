import Foundation

enum AuthenticationMode: Equatable {
    case signIn
    case signUp
}

struct ValidatedAuthCredentials {
    let email: String
    let password: String
}

enum AuthCredentialError: LocalizedError {
    case invalidEmail
    case emptyPassword
    case passwordTooShort

    var errorDescription: String? {
        switch self {
        case .invalidEmail: "请输入有效邮箱地址。"
        case .emptyPassword: "请输入密码。"
        case .passwordTooShort: "密码至少需要 \(AuthCredentialRules.minimumPasswordLength) 位。"
        }
    }
}

enum AuthCredentialRules {
    static let minimumPasswordLength = 8

    static func normalizeEmail(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping
            .components(separatedBy: CharacterSet(charactersIn: "\u{200B}\u{200C}\u{200D}\u{FEFF}"))
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func isValidEmail(_ value: String) -> Bool {
        let email = normalizeEmail(value)
        guard email.utf8.count <= 254 else { return false }
        return email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }

    static func validate(email: String, password: String, mode: AuthenticationMode) throws -> ValidatedAuthCredentials {
        let normalizedEmail = normalizeEmail(email)
        guard isValidEmail(normalizedEmail) else { throw AuthCredentialError.invalidEmail }
        guard !password.isEmpty else { throw AuthCredentialError.emptyPassword }
        if mode == .signUp, password.count < minimumPasswordLength {
            throw AuthCredentialError.passwordTooShort
        }
        return ValidatedAuthCredentials(email: normalizedEmail, password: password)
    }

    static func compatibilityPassword(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: "。", with: ".")
            .components(separatedBy: CharacterSet(charactersIn: "\u{200B}\u{200C}\u{200D}\u{FEFF}"))
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
