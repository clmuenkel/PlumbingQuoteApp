enum AppConfig {
    static let supabaseURL: String = Secrets.supabaseURL
    static let supabaseAnonKey: String = Secrets.supabaseAnonKey
    static let sentryDSN: String = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String ?? ""
}
