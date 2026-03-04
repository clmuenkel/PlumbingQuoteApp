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
                Text("Rejected").tag("rejected")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .tint(AppTheme.accent)

            List(filteredItems) { item in
                NavigationLink(destination: QuoteDetailView(estimateId: item.id)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text((item.customerName?.isEmpty == false) ? (item.customerName ?? "") : "On-Site Customer")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.text)
                                Text(item.subcategory)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.muted)
                                    .lineLimit(2)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("~\(CurrencyFormatter.usd(item.total))")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(AppTheme.text)
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(AppTheme.muted.opacity(0.8))
                            }
                        }

                        HStack {
                            Text(relativeDate(item.createdAt))
                                .font(.caption2)
                                .foregroundStyle(AppTheme.muted)
                            Spacer()
                            Text(item.status.displayName)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(item.status.color.opacity(0.2))
                                .foregroundStyle(item.status.color)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(AppTheme.surface)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button("Accept") {
                        Task { await viewModel.updateStatus(for: item.id, status: .accepted) }
                    }
                    .tint(AppTheme.success)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Reject") {
                        Task { await viewModel.updateStatus(for: item.id, status: .rejected) }
                    }
                    .tint(AppTheme.error)
                }
            }
            .navigationTitle("Quote History")
            .toolbarBackground(AppTheme.bgAlt, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .scrollContentBackground(.hidden)
            .background(AppTheme.bg)
            .searchable(text: $searchText)
            .refreshable {
                await viewModel.loadHistory()
            }
            .overlay {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView("Loading...")
                } else if !viewModel.isLoading && filteredItems.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.title3)
                            .foregroundStyle(AppTheme.muted)
                        Text("No quotes yet")
                            .font(.headline)
                        Text("Create a quote from Home to see it here.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.muted)
                    }
                }
            }
            .task {
                await viewModel.loadHistory()
            }
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    NavigationStack {
        QuoteHistoryView()
    }
}
