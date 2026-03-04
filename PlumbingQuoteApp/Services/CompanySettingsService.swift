import Foundation
import Supabase

final class CompanySettingsService {
    static let shared = CompanySettingsService()
    static let defaultTaxRate: Double = 0.0825
    static let defaultPdfTerms: String = "This quote is valid for 30 days unless otherwise noted."
    static let pdfTermsDefaultsKey = "plumbquote.company.pdfterms.v1"
    private let supabase = SupabaseService.shared.client

    private init() {}

    private struct CompanySettingsRow: Decodable {
        let company_name: String?
        let company_phone: String?
        let company_address: String?
        let labor_rate_per_hour: Double?
        let tax_rate: Double?
    }

    struct CompanySettingsData {
        var companyName: String
        var companyPhone: String
        var companyAddress: String
        var laborRatePerHour: Double
        var taxRate: Double
    }

    private struct UpdateCompanySettingsPayload: Encodable {
        let company_name: String
        let company_phone: String
        let company_address: String
        let labor_rate_per_hour: Double
        let tax_rate: Double
        let updated_at: String
    }

    func fetchCompanyInfo() async -> CompanyInfo {
        do {
            let rows: [CompanySettingsRow] = try await supabase
                .from("company_settings")
                .select("company_name, company_phone, company_address, labor_rate_per_hour, tax_rate")
                .eq("id", value: "default")
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else { return .default }
            return CompanyInfo(
                name: (row.company_name?.isEmpty == false ? row.company_name : nil) ?? CompanyInfo.default.name,
                phone: row.company_phone ?? "",
                address: row.company_address ?? "",
                logo: nil,
                terms: UserDefaults.standard.string(forKey: Self.pdfTermsDefaultsKey) ?? Self.defaultPdfTerms
            )
        } catch {
            return .default
        }
    }

    func fetchCompanySettings() async -> CompanySettingsData {
        do {
            let rows: [CompanySettingsRow] = try await supabase
                .from("company_settings")
                .select("company_name, company_phone, company_address, labor_rate_per_hour, tax_rate")
                .eq("id", value: "default")
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else {
                return CompanySettingsData(
                    companyName: CompanyInfo.default.name,
                    companyPhone: "",
                    companyAddress: "",
                    laborRatePerHour: 95,
                    taxRate: Self.defaultTaxRate
                )
            }
            return CompanySettingsData(
                companyName: (row.company_name?.isEmpty == false ? row.company_name : nil) ?? CompanyInfo.default.name,
                companyPhone: row.company_phone ?? "",
                companyAddress: row.company_address ?? "",
                laborRatePerHour: row.labor_rate_per_hour ?? 95,
                taxRate: row.tax_rate ?? Self.defaultTaxRate
            )
        } catch {
            return CompanySettingsData(
                companyName: CompanyInfo.default.name,
                companyPhone: "",
                companyAddress: "",
                laborRatePerHour: 95,
                taxRate: Self.defaultTaxRate
            )
        }
    }

    func updateCompanySettings(_ settings: CompanySettingsData) async throws {
        let payload = UpdateCompanySettingsPayload(
            company_name: settings.companyName.trimmingCharacters(in: .whitespacesAndNewlines),
            company_phone: settings.companyPhone.trimmingCharacters(in: .whitespacesAndNewlines),
            company_address: settings.companyAddress.trimmingCharacters(in: .whitespacesAndNewlines),
            labor_rate_per_hour: settings.laborRatePerHour,
            tax_rate: settings.taxRate,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )

        _ = try await supabase
            .from("company_settings")
            .update(payload)
            .eq("id", value: "default")
            .execute()
    }
}
