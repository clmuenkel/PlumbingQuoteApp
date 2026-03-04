import Foundation

@MainActor
final class AnalyticsViewModel: ObservableObject {
    enum TimeRange: String, CaseIterable, Identifiable {
        case sevenDays = "7D"
        case thirtyDays = "30D"
        case ninetyDays = "90D"
        case allTime = "All"

        var id: String { rawValue }

        var dayWindow: Int? {
            switch self {
            case .sevenDays: return 7
            case .thirtyDays: return 30
            case .ninetyDays: return 90
            case .allTime: return nil
            }
        }
    }

    struct DailyStat: Identifiable {
        let id = UUID()
        let date: Date
        let totalQuotes: Int
        let accepted: Int
        let sent: Int
        let rejected: Int
        let viewed: Int
        let avgQuoteValue: Double
        let acceptedRevenue: Double
        let pendingSentValue: Double
        let projectedRevenue: Double
    }

    struct CategoryStat: Identifiable {
        let id = UUID()
        let category: String
        let quoteCount: Int
        let avgValue: Double
        let acceptedCount: Int
    }

    struct TechStat: Identifiable {
        let id = UUID()
        let technicianName: String
        let totalQuotes: Int
        let accepted: Int
        let acceptanceRate: Double
        let avgQuoteValue: Double
    }

    @Published var selectedRange: TimeRange = .thirtyDays
    @Published var dailySummary: [DailyStat] = []
    @Published var categoryBreakdown: [CategoryStat] = []
    @Published var techPerformance: [TechStat] = []
    @Published var isLoading = false
    @Published var error: String?

    private let supabase = SupabaseService.shared.client

    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let dailyRows: [DailyRow] = try await supabase
                .from("analytics_quote_summary")
                .select("*")
                .order("quote_date", ascending: false)
                .execute()
                .value
            let categoryRows: [CategoryRow] = try await supabase
                .from("analytics_category_breakdown")
                .select("*")
                .order("quote_count", ascending: false)
                .execute()
                .value
            let techRows: [TechRow] = try await supabase
                .from("analytics_technician_performance")
                .select("*")
                .order("accepted", ascending: false)
                .execute()
                .value

            let minDate = selectedRange.dayWindow.map { days in
                Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
            }

            let allDaily = dailyRows.compactMap { row -> DailyStat? in
                guard let date = row.dateValue else { return nil }
                return DailyStat(
                    date: date,
                    totalQuotes: row.total_quotes ?? 0,
                    accepted: row.accepted ?? 0,
                    sent: row.sent ?? 0,
                    rejected: row.rejected ?? 0,
                    viewed: row.viewed ?? 0,
                    avgQuoteValue: row.avg_quote_value ?? 0,
                    acceptedRevenue: row.accepted_revenue ?? 0,
                    pendingSentValue: row.pending_sent_value ?? 0,
                    projectedRevenue: row.projected_revenue ?? 0
                )
            }

            if let minDate {
                dailySummary = allDaily.filter { $0.date >= minDate }.sorted { $0.date < $1.date }
            } else {
                dailySummary = allDaily.sorted { $0.date < $1.date }
            }

            categoryBreakdown = categoryRows.map {
                CategoryStat(
                    category: $0.category ?? "Uncategorized",
                    quoteCount: $0.quote_count ?? 0,
                    avgValue: $0.avg_value ?? 0,
                    acceptedCount: $0.accepted_count ?? 0
                )
            }

            techPerformance = techRows.map {
                TechStat(
                    technicianName: $0.technician_name ?? "Unknown",
                    totalQuotes: $0.total_quotes ?? 0,
                    accepted: $0.accepted ?? 0,
                    acceptanceRate: $0.acceptance_rate ?? 0,
                    avgQuoteValue: $0.avg_quote_value ?? 0
                )
            }
        } catch {
            ErrorLogger.log(
                message: "Analytics load failed: \(error.localizedDescription)",
                context: ["source": "AnalyticsViewModel.load"]
            )
            self.error = error.localizedDescription
        }
    }
}

private struct DailyRow: Decodable {
    let quote_date: String?
    let total_quotes: Int?
    let accepted: Int?
    let sent: Int?
    let rejected: Int?
    let viewed: Int?
    let avg_quote_value: Double?
    let accepted_revenue: Double?
    let pending_sent_value: Double?
    let projected_revenue: Double?

    var dateValue: Date? {
        guard let quote_date else { return nil }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: quote_date)
            ?? {
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd HH:mm:ssZZZZZ"
                return fmt.date(from: quote_date)
            }()
    }
}

private struct CategoryRow: Decodable {
    let category: String?
    let quote_count: Int?
    let avg_value: Double?
    let accepted_count: Int?
}

private struct TechRow: Decodable {
    let technician_name: String?
    let total_quotes: Int?
    let accepted: Int?
    let acceptance_rate: Double?
    let avg_quote_value: Double?
}
