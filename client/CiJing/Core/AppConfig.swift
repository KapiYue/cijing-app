import Foundation

enum AppConfig {
    static var supabaseURL: URL {
        URL(string: GeneratedClientConfig.SUPABASE_URL)!
    }

    static var supabasePublishableKey: String {
        GeneratedClientConfig.SUPABASE_PUBLISHABLE_KEY
    }
}
