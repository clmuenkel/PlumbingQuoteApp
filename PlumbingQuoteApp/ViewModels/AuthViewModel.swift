import Foundation
import Supabase

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentTechnician: Technician?
    @Published var isLoading = false
    @Published var error: String?

    private let supabase = SupabaseService.shared.client

    init() {
        Task { await refreshSession() }
    }

    func refreshSession() async {
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
            self.error = error.localizedDescription
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
        let existing: [TechnicianDTO] = try await supabase
            .from("User")
            .select()
            .eq("authId", value: user.id.uuidString)
            .limit(1)
            .execute()
            .value

        if let dto = existing.first {
            currentTechnician = dto.toModel()
            return
        }

        let inserted: TechnicianDTO = try await supabase
            .from("User")
            .insert([
                "id": "usr_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))",
                "authId": user.id.uuidString,
                "name": user.email?.split(separator: "@").first.map(String.init) ?? "Technician",
                "email": user.email ?? "unknown@example.com",
                "role": "technician",
                "active": true
            ])
            .select()
            .single()
            .execute()
            .value

        currentTechnician = inserted.toModel()
    }
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
