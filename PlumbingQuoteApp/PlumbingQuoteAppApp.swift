import SwiftUI
#if canImport(Sentry)
import Sentry
#endif

@main
struct PlumbingQuoteAppApp: App {
    @StateObject private var authVM = AuthViewModel()

    init() {
        ErrorLogger.start()
        configureCrashReporting()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authVM.isAuthenticated {
                    HomeView()
                } else if AuthViewModel.skipAuthForTesting {
                    ProgressView("Signing in…")
                } else {
                    LoginView()
                }
            }
            .tint(AppTheme.accent)
            .preferredColorScheme(.light)
            .environmentObject(authVM)
        }
    }

    private func configureCrashReporting() {
#if canImport(Sentry)
        let dsn = AppConfig.sentryDSN.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dsn.isEmpty else { return }
        SentrySDK.start { options in
            options.dsn = dsn
            options.enableAppHangTracking = true
            options.tracesSampleRate = 0.1
        }
#endif
    }
}
