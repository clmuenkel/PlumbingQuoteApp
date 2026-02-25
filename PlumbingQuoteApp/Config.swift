enum AppConfig {
    static let supabaseURL: String = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              !value.isEmpty else {
            fatalError("Missing SUPABASE_URL in Info.plist/.xcconfig")
        }
        return value
    }()

    static let supabaseAnonKey: String = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !value.isEmpty else {
            fatalError("Missing SUPABASE_ANON_KEY in Info.plist/.xcconfig")
        }
        return value
    }()
}
