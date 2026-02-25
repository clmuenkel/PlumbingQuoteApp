import SwiftUI

struct QuoteHistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()
    @State private var searchText = ""
    @State private var selectedFilter: String = "all"

    var filteredItems: [QuoteHistoryItem] {
        let statusFiltered = viewModel.items.filter { item in
            if selectedFilter == "all" { return true }
            return item.status.rawValue == selectedFilter
        }
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return statusFiltered
        }
        let q = searchText.lowercased()
        return statusFiltered.filter {
            $0.category.lowercased().contains(q) ||
            $0.subcategory.lowercased().contains(q) ||
            ($0.customerName?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Picker("Filter", selection: $selectedFilter) {
                Text("All").tag("all")
                Text("Draft").tag("draft")
                Text("Sent").tag("sent")
                Text("Accepted").tag("accepted")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            List(filteredItems) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.subcategory)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(formatCurrency(item.total))
                            .font(.subheadline.weight(.bold))
                    }
                    Text(item.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(item.createdAt, style: .date)
                        Spacer()
                        Text(item.status.displayName)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(item.status.color.opacity(0.2))
                            .foregroundStyle(item.status.color)
                            .clipShape(Capsule())
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button("Accept") {
                        Task { await viewModel.updateStatus(for: item.id, status: .accepted) }
                    }
                    .tint(.green)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Reject") {
                        Task { await viewModel.updateStatus(for: item.id, status: .rejected) }
                    }
                    .tint(.red)
                }
            }
            .navigationTitle("Quote History")
            .searchable(text: $searchText)
            .refreshable {
                await viewModel.loadHistory()
            }
            .overlay {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView("Loading...")
                }
            }
            .task {
                await viewModel.loadHistory()
            }
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}

#Preview {
    NavigationStack {
        QuoteHistoryView()
    }
}
