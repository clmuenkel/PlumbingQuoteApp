import Foundation
import Supabase

final class CustomerService {
    static let shared = CustomerService()
    private let supabase = SupabaseService.shared.client

    private init() {}

    struct Suggestion: Identifiable, Equatable {
        let id: String
        let fullName: String
        let phone: String?
        let email: String?
        let address: String?
    }

    private struct CustomerRow: Decodable {
        let id: String
        let firstName: String?
        let lastName: String?
        let phone: String?
        let email: String?
        let address: String?
    }

    func searchCustomers(query: String) async -> [Suggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        let escaped = trimmed.replacingOccurrences(of: ",", with: "")
        do {
            let rows: [CustomerRow] = try await supabase
                .from("Customer")
                .select("id, firstName, lastName, phone, email, address")
                .or("firstName.ilike.%\(escaped)%,lastName.ilike.%\(escaped)%")
                .limit(8)
                .execute()
                .value

            return rows.map { row in
                let fullName = [row.firstName, row.lastName]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                return Suggestion(
                    id: row.id,
                    fullName: fullName.isEmpty ? "Unnamed Customer" : fullName,
                    phone: row.phone,
                    email: row.email,
                    address: row.address
                )
            }
        } catch {
            return []
        }
    }
}
