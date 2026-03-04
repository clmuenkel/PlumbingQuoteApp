import SwiftUI
import Charts

struct AnalyticsDashboardView: View {
    @StateObject private var viewModel = AnalyticsViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Range", selection: $viewModel.selectedRange) {
                    ForEach(AnalyticsViewModel.TimeRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .tint(AppTheme.accent)
                .onChange(of: viewModel.selectedRange) { _ in
                    Task { await viewModel.load() }
                }

                topCards
                quotesChart
                categoryChart
                technicianTable
            }
            .padding()
        }
        .background(AppTheme.bg)
        .navigationTitle("Analytics")
        .toolbarBackground(AppTheme.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .refreshable {
            await viewModel.load()
        }
        .overlay {
            if viewModel.isLoading && viewModel.dailySummary.isEmpty {
                ProgressView("Loading analytics...")
            }
        }
        .task {
            await viewModel.load()
        }
    }

    private var topCards: some View {
        let totalQuotes = viewModel.dailySummary.reduce(0) { $0 + $1.totalQuotes }
        let accepted = viewModel.dailySummary.reduce(0) { $0 + $1.accepted }
        let revenue = viewModel.dailySummary.reduce(0) { $0 + $1.acceptedRevenue }
        let projected = viewModel.dailySummary.reduce(0) { $0 + $1.projectedRevenue }
        let viewed = viewModel.dailySummary.reduce(0) { $0 + $1.viewed }
        let monthSplit = splitCurrentVsPreviousMonth()
        let currentMonthRevenue = monthSplit.current.reduce(0) { $0 + $1.acceptedRevenue }
        let currentMonthProjected = monthSplit.current.reduce(0) { $0 + $1.projectedRevenue }
        let acceptanceRate = totalQuotes > 0 ? (Double(accepted) / Double(totalQuotes)) * 100 : 0
        let viewRate = totalQuotes > 0 ? (Double(viewed) / Double(totalQuotes)) * 100 : 0

        return VStack(spacing: 10) {
            cardRow(title: "Total Quotes", value: "\(totalQuotes)")
            cardRow(title: "Acceptance Rate", value: String(format: "%.1f%%", acceptanceRate))
            cardRow(title: "Viewed Rate", value: String(format: "%.1f%%", viewRate))
            cardRow(
                title: "Revenue",
                value: CurrencyFormatter.usd(revenue),
                trend: monthTrend(current: currentMonthRevenue, previous: previousMonthRevenue)
            )
            cardRow(
                title: "Projected Revenue",
                value: CurrencyFormatter.usd(projected),
                trend: monthTrend(current: currentMonthProjected, previous: previousMonthProjectedRevenue)
            )
        }
    }

    private var quotesChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quotes by Day")
                .font(.headline)

            Chart(viewModel.dailySummary) { item in
                BarMark(
                    x: .value("Day", item.date, unit: .day),
                    y: .value("Quotes", item.totalQuotes)
                )
                .foregroundStyle(AppTheme.accent)
            }
            .frame(height: 220)
        }
        .padding()
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
    }

    private var categoryChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Category Breakdown")
                .font(.headline)

            Group {
                if #available(iOS 17.0, *) {
                    Chart(viewModel.categoryBreakdown.prefix(6)) { item in
                        SectorMark(
                            angle: .value("Quotes", item.quoteCount),
                            innerRadius: .ratio(0.5),
                            angularInset: 1.5
                        )
                        .foregroundStyle(by: .value("Category", item.category))
                    }
                } else {
                    Chart(viewModel.categoryBreakdown.prefix(6)) { item in
                        BarMark(
                            x: .value("Category", item.category),
                            y: .value("Quotes", item.quoteCount)
                        )
                        .foregroundStyle(by: .value("Category", item.category))
                    }
                }
            }
            .frame(height: 220)
        }
        .padding()
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
    }

    private var technicianTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Technician Leaderboard")
                .font(.headline)

            ForEach(viewModel.techPerformance) { tech in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tech.technicianName)
                            .font(.subheadline.weight(.semibold))
                        Text("\(tech.totalQuotes) quotes")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.1f%%", tech.acceptanceRate))
                            .font(.subheadline.weight(.semibold))
                        Text(CurrencyFormatter.usd(tech.avgQuoteValue))
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .padding()
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
    }

    private func cardRow(title: String, value: String, trend: (icon: String, text: String, positive: Bool)? = nil) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                if let trend {
                    Label(trend.text, systemImage: trend.icon)
                        .font(.caption2)
                        .foregroundStyle(trend.positive ? AppTheme.success : AppTheme.error)
                }
            }
            Spacer()
            Text(value)
                .font(.headline)
        }
        .padding()
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
    }

    private var previousMonthRevenue: Double {
        let split = splitCurrentVsPreviousMonth()
        return split.previous.reduce(0) { $0 + $1.acceptedRevenue }
    }

    private var previousMonthProjectedRevenue: Double {
        let split = splitCurrentVsPreviousMonth()
        return split.previous.reduce(0) { $0 + $1.projectedRevenue }
    }

    private func splitCurrentVsPreviousMonth() -> (current: [AnalyticsViewModel.DailyStat], previous: [AnalyticsViewModel.DailyStat]) {
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.dateComponents([.year, .month], from: now)
        let previousDate = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        let previousMonth = calendar.dateComponents([.year, .month], from: previousDate)

        let current = viewModel.dailySummary.filter {
            calendar.dateComponents([.year, .month], from: $0.date) == currentMonth
        }
        let previous = viewModel.dailySummary.filter {
            calendar.dateComponents([.year, .month], from: $0.date) == previousMonth
        }
        return (current, previous)
    }

    private func monthTrend(current: Double, previous: Double) -> (icon: String, text: String, positive: Bool)? {
        guard previous > 0 else { return nil }
        let pct = ((current - previous) / previous) * 100
        let positive = pct >= 0
        let icon = positive ? "arrow.up.right" : "arrow.down.right"
        return (icon, String(format: "%.1f%% vs last month", abs(pct)), positive)
    }

}

#Preview {
    NavigationStack {
        AnalyticsDashboardView()
    }
}
