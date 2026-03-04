import SwiftUI

struct QuoteDetailView: View {
    let estimateId: String
    @StateObject private var viewModel = QuoteDetailViewModel()
    @State private var showFullQuote = false

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.quoteResult == nil {
                ProgressView("Loading quote...")
            } else if let error = viewModel.error, viewModel.quoteResult == nil {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(AppTheme.warning)
                    Text("Could not load quote")
                        .font(.headline)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else if let result = viewModel.quoteResult {
                ScrollView {
                    VStack(spacing: 14) {
                        imageGallery
                        headerCard(result: result)
                        tierSelector(result: result)
                        pricingSummary(result: result)
                        actionCard(result: result)
                    }
                    .padding(16)
                }
                .background(AppTheme.bgAlt)
                .sheet(isPresented: $showFullQuote) {
                    QuoteResultView(
                        result: result,
                        selectedTier: $viewModel.selectedTier,
                        onDismiss: { showFullQuote = false },
                        onQuoteSaved: { tier, quote in
                            viewModel.updateQuote(quote, for: tier)
                        }
                    )
                }
            } else {
                ProgressView("Loading quote...")
            }
        }
        .navigationTitle("Quote Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.bgAlt, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            await viewModel.load(estimateId: estimateId)
        }
    }

    @ViewBuilder
    private var imageGallery: some View {
        if viewModel.images.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(viewModel.images.enumerated()), id: \.offset) { _, image in
                        Color.clear
                            .frame(width: 140, height: 100)
                            .overlay {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private func headerCard(result: QuoteResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let estimateNumber = result.estimateNumber {
                    Text(formattedEstimateNumber(estimateNumber))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                Text(viewModel.estimateStatus.displayName)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(viewModel.estimateStatus.color.opacity(0.2))
                    .foregroundStyle(viewModel.estimateStatus.color)
                    .clipShape(Capsule())
            }

            Text(result.issue.subcategory)
                .font(.headline)
            Text(result.issue.description)
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)

            if let customerName = result.customerName, !customerName.isEmpty {
                Text("Customer: \(customerName)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
    }

    private func tierSelector(result: QuoteResult) -> some View {
        VStack(spacing: 8) {
            tierButton(result: result, tier: .good)
            tierButton(result: result, tier: .better)
            tierButton(result: result, tier: .best)
        }
    }

    private func tierButton(result: QuoteResult, tier: QuoteTier) -> some View {
        let quote = result.quote(for: tier)
        return Button {
            viewModel.selectedTier = tier
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tier.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.text)
                    Text(quote.solutionDescription)
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                Text(CurrencyFormatter.usd(quote.computedTotal))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.text)
            }
            .padding(12)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(viewModel.selectedTier == tier ? tier.color : .clear, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }

    private func pricingSummary(result: QuoteResult) -> some View {
        let quote = result.quote(for: viewModel.selectedTier)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Selected \(viewModel.selectedTier.rawValue)")
                .font(.subheadline.weight(.semibold))
            HStack {
                Text("Parts")
                Spacer()
                Text(CurrencyFormatter.usd(quote.computedPartsTotal))
            }
            HStack {
                Text("Labor")
                Spacer()
                Text(CurrencyFormatter.usd(quote.computedLaborTotal))
            }
            HStack {
                Text("Tax")
                Spacer()
                Text(CurrencyFormatter.usd(quote.computedTax))
            }
            Divider()
            HStack {
                Text("Total")
                    .fontWeight(.bold)
                Spacer()
                Text(CurrencyFormatter.usd(quote.computedTotal))
                    .fontWeight(.bold)
            }
        }
        .font(.subheadline)
        .foregroundStyle(AppTheme.text)
        .padding(14)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
    }

    private func actionCard(result: QuoteResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actions")
                .font(.subheadline.weight(.semibold))
            Button {
                showFullQuote = true
            } label: {
                Label("Open Full Quote", systemImage: "doc.text.magnifyingglass")
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .background(AppTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
    }

    private func formattedEstimateNumber(_ number: Int) -> String {
        String(format: "Quote #%03d", number)
    }

}

