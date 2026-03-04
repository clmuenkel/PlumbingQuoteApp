import SwiftUI

@main
struct PlumbingQuoteAppApp: App {
    @StateObject private var authVM = AuthViewModel()

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
}
