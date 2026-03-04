import Foundation
import Supabase

final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient
    let configurationError: String?

    private init() {
        guard let url = URL(string: AppConfig.supabaseURL) else {
            configurationError = "Configuration error: invalid Supabase URL. Please reinstall or contact support."
            client = SupabaseClient(
                supabaseURL: URL(string: "https://example.invalid")!,
                supabaseKey: "invalid"
            )
            return
        }
        configurationError = nil
        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: AppConfig.supabaseAnonKey
        )
    }
}
