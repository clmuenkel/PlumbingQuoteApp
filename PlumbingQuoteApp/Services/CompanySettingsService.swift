import Foundation
import Supabase

final class CompanySettingsService {
    static let shared = CompanySettingsService()
    private let supabase = SupabaseService.shared.client

    private init() {}

    private struct CompanySettingsRow: Decodable {
        let company_name: String?
        let company_phone: String?
        let company_address: String?
    }

    func fetchCompanyInfo() async -> CompanyInfo {
        do {
            let rows: [CompanySettingsRow] = try await supabase
                .from("company_settings")
                .select("company_name, company_phone, company_address")
                .eq("id", value: "default")
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else { return .default }
            return CompanyInfo(
                name: (row.company_name?.isEmpty == false ? row.company_name : nil) ?? CompanyInfo.default.name,
                phone: row.company_phone ?? "",
                address: row.company_address ?? "",
                logo: nil
            )
        } catch {
            return .default
        }
    }
}
