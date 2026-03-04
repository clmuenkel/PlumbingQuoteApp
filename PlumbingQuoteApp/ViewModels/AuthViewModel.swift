import Foundation
import Supabase

@MainActor
final class AuthViewModel: ObservableObject {
    /// Set to `true` to skip the login screen and auto sign-in as QA user for quick testing. Set to `false` for production.
    #if DEBUG
    static let skipAuthForTesting = true
    #else
    static let skipAuthForTesting = false
    #endif

    @Published var isAuthenticated = false
    @Published var currentTechnician: Technician?
    @Published var isLoading = false
    @Published var error: String?

    private let supabase = SupabaseService.shared.client

    init() {
        if let configurationError = SupabaseService.shared.configurationError {
            error = configurationError
            isAuthenticated = false
            return
        }

        Task {
            if Self.skipAuthForTesting {
                await signIn(email: "qa@plumbquote.test", password: "QATest")
            } else {
                await refreshSession()
            }
        }
    }

    func refreshSession() async {
        if let configurationError = SupabaseService.shared.configurationError {
            error = configurationError
            isAuthenticated = false
            currentTechnician = nil
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await supabase.auth.session
            try await loadCurrentTechnician()
            isAuthenticated = currentTechnician != nil
        } catch {
            ErrorLogger.log(
                message: "Session refresh failed: \(error.localizedDescription)",
                context: ["source": "AuthViewModel.refreshSession"]
            )
            isAuthenticated = false
            currentTechnician = nil
        }
    }

    func signIn(email: String, password: String) async {
        if let configurationError = SupabaseService.shared.configurationError {
            error = configurationError
            isAuthenticated = false
            return
        }

        guard !email.isEmpty, !password.isEmpty else {
            error = "Enter both email and password."
            return
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            _ = try await supabase.auth.signIn(
                email: email,
                password: password
            )
            try await loadCurrentTechnician()
            isAuthenticated = currentTechnician != nil
        } catch {
            ErrorLogger.log(
                message: "Sign in failed: \(error.localizedDescription)",
                context: ["source": "AuthViewModel.signIn", "email": email]
            )
            self.error = userFacingError(for: error)
            isAuthenticated = false
        }
    }

    func signOut() async {
        do {
            try await supabase.auth.signOut()
            currentTechnician = nil
            isAuthenticated = false
        } catch {
            ErrorLogger.log(
                message: "Sign out failed: \(error.localizedDescription)",
                context: ["source": "AuthViewModel.signOut"]
            )
            self.error = error.localizedDescription
        }
    }

    private func loadCurrentTechnician() async throws {
        let session = try await supabase.auth.session
        let user = session.user
        // PostgreSQL uuid::text produces lowercase; Swift UUID.uuidString is uppercase.
        // Normalize to lowercase so the .eq() query matches the DB value.
        let authId = user.id.uuidString.lowercased()

        if let existing = try await fetchTechnician(authId: authId) {
            currentTechnician = existing
            return
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let newUser = NewUserPayload(
            id: "usr_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())",
            authId: authId,
            name: user.email?.split(separator: "@").first.map(String.init) ?? "Technician",
            email: user.email ?? "unknown@example.com",
            role: "technician",
            active: true,
            createdAt: now,
            updatedAt: now
        )

        do {
            let inserted: TechnicianDTO = try await supabase
                .from("User")
                .insert(newUser)
                .select()
                .single()
                .execute()
                .value
            currentTechnician = inserted.toModel()
        } catch {
            if isUniqueConstraintError(error),
               let existingAfterConflict = try await retryFetchTechnician(authId: authId) {
                currentTechnician = existingAfterConflict
                return
            }
            throw error
        }
    }

    private func fetchTechnician(authId: String) async throws -> Technician? {
        let existing: [TechnicianDTO] = try await supabase
            .from("User")
            .select()
            .eq("authId", value: authId)
            .limit(1)
            .execute()
            .value
        return existing.first?.toModel()
    }

    private func retryFetchTechnician(authId: String) async throws -> Technician? {
        for _ in 0..<3 {
            if let existing = try await fetchTechnician(authId: authId) {
                return existing
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        return nil
    }

    private func isUniqueConstraintError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("duplicate key")
            || message.contains("unique constraint")
            || message.contains("23505")
    }

    private func userFacingError(for error: Error) -> String {
        let message = error.localizedDescription.lowercased()
        if message.contains("invalid login credentials") {
            return "Incorrect email or password."
        }
        if message.contains("email not confirmed") {
            return "Email not confirmed. Check your inbox for the confirmation link."
        }
        if message.contains("rate limit") || message.contains("too many requests") {
            return "Too many attempts. Please wait a minute and try again."
        }
        if message.contains("network")
            || message.contains("timed out")
            || message.contains("offline")
            || message.contains("internet") {
            return "Network issue. Check your connection and try again."
        }
        if isUniqueConstraintError(error) {
            return "Your account is syncing. Please try again."
        }
        return "Sign in failed. Please try again."
    }
}

private struct NewUserPayload: Encodable {
    let id: String
    let authId: String
    let name: String
    let email: String
    let role: String
    let active: Bool
    let createdAt: String
    let updatedAt: String
}

private struct TechnicianDTO: Decodable {
    let id: String
    let authId: String
    let name: String
    let email: String
    let role: String
    let active: Bool

    func toModel() -> Technician {
        Technician(
            id: id,
            authId: authId,
            fullName: name,
            email: email,
            role: role,
            isActive: active
        )
    }
}
