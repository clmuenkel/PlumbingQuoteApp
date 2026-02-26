import Foundation

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var items: [QuoteHistoryItem] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var statusFilter: EstimateStatus?

    private let supabase = SupabaseService.shared.client

    func loadHistory() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let session = try await supabase.auth.session
            let userRows: [HistoryUserRow] = try await supabase
                .from("User")
                .select("id")
                .eq("authId", value: session.user.id.uuidString.lowercased())
                .limit(1)
                .execute()
                .value
            guard let appUserId = userRows.first?.id else {
                throw NSError(domain: "HistoryViewModel", code: 404, userInfo: [NSLocalizedDescriptionKey: "Technician profile not found"])
            }
            let rows: [QuoteHistoryRow] = try await supabase
                .from("Estimate")
                .select("id, status, createdAt, aiDiagnosisNote, Customer(firstName,lastName), EstimateOption(tier,total,recommended)")
                .eq("createdById", value: appUserId)
                .order("createdAt", ascending: false)
                .limit(100)
                .execute()
                .value

            var historyItems: [QuoteHistoryItem] = []
            historyItems.reserveCapacity(rows.count)

            for row in rows {
                let sortedOptions = row.options.sorted { lhs, rhs in
                    if lhs.recommended == rhs.recommended { return lhs.tier < rhs.tier }
                    return lhs.recommended && !rhs.recommended
                }
                let pickedOption = sortedOptions.first
                let customerName = row.customer.map { "\($0.firstName) \($0.lastName)" }

                historyItems.append(
                    QuoteHistoryItem(
                        id: row.id,
                        category: "Estimate",
                        subcategory: row.aiDiagnosisNote ?? "Plumbing Service",
                        selectedTier: pickedOption?.tier.capitalized,
                        status: EstimateStatus(rawValue: row.status) ?? .draft,
                        createdAt: row.createdAtDate,
                        total: pickedOption?.total ?? 0,
                        customerName: customerName
                    )
                )
            }

            items = historyItems
        } catch {
            ErrorLogger.log(
                message: "Failed loading history: \(error.localizedDescription)",
                context: ["source": "HistoryViewModel.loadHistory"]
            )
            self.error = error.localizedDescription
        }
    }

    func updateStatus(for estimateId: String, status: EstimateStatus) async {
        do {
            _ = try await EstimateService.shared.updateStatus(
                estimateId: estimateId,
                status: status
            )
            if let idx = items.firstIndex(where: { $0.id == estimateId }) {
                let item = items[idx]
                items[idx] = QuoteHistoryItem(
                    id: item.id,
                    category: item.category,
                    subcategory: item.subcategory,
                    selectedTier: item.selectedTier,
                    status: status,
                    createdAt: item.createdAt,
                    total: item.total,
                    customerName: item.customerName
                )
            }
        } catch {
            ErrorLogger.log(
                message: "Failed updating estimate status: \(error.localizedDescription)",
                context: [
                    "source": "HistoryViewModel.updateStatus",
                    "estimateId": estimateId,
                    "status": status.rawValue
                ]
            )
            self.error = error.localizedDescription
        }
    }
}

private struct QuoteHistoryRow: Decodable {
    let id: String
    let status: String
    let createdAt: String
    let aiDiagnosisNote: String?
    let customer: CustomerRow?
    let options: [EstimateOptionRow]

    var createdAtDate: Date {
        Self.iso8601WithFractions.date(from: createdAt)
            ?? Self.iso8601.date(from: createdAt)
            ?? Date()
    }

    private static let iso8601WithFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case createdAt
        case aiDiagnosisNote
        case customer = "Customer"
        case options = "EstimateOption"
    }
}

private struct EstimateOptionRow: Decodable {
    let tier: String
    let total: Double
    let recommended: Bool
}

private struct HistoryUserRow: Decodable {
    let id: String
}

private struct CustomerRow: Decodable {
    let firstName: String
    let lastName: String
}
