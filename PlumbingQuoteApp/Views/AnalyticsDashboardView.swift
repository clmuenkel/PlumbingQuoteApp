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
        let acceptanceRate = totalQuotes > 0 ? (Double(accepted) / Double(totalQuotes)) * 100 : 0

        return VStack(spacing: 10) {
            cardRow(title: "Total Quotes", value: "\(totalQuotes)")
            cardRow(title: "Acceptance Rate", value: String(format: "%.1f%%", acceptanceRate))
            cardRow(title: "Revenue", value: CurrencyFormatter.usd(revenue))
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

    private func cardRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.headline)
        }
        .padding()
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
    }

}

#Preview {
    NavigationStack {
        AnalyticsDashboardView()
    }
}
