import SwiftUI

struct QuoteResultView: View {
    let result: QuoteResult
    @Binding var selectedTier: QuoteTier
    let onDismiss: () -> Void

    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var showBreakdown = false
    @State private var estimateStatus: EstimateStatus = .draft
    @State private var statusError: String?
    @State private var isUpdatingStatus = false
    @State private var companyInfo: CompanyInfo = .default
    @State private var showSignaturePad = false
    @State private var signatureImage: UIImage?
    @State private var showEditQuote = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    headerCard
                    if !result.failedUploads.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("Some photos failed to upload. Quote was saved.")
                                .font(.caption.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.orange.opacity(0.16))
                        .foregroundStyle(.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    tierCard(for: .good)
                    tierCard(for: .better)
                    tierCard(for: .best)

                    if showBreakdown {
                        quoteBreakdownCard(for: result.quote(for: selectedTier))
                    }

                    actionButtons

                    if let statusError {
                        Text(statusError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Your Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { onDismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        prepareAndSharePDF()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: shareItems)
            }
            .sheet(isPresented: $showSignaturePad) {
                SignaturePadView(
                    onCancel: { showSignaturePad = false },
                    onDone: { image in
                        signatureImage = image
                        showSignaturePad = false
                        Task { await updateEstimateStatus(.accepted, signature: image) }
                    }
                )
            }
            .sheet(isPresented: $showEditQuote) {
                if let estimateId = result.remoteId,
                   let optionId = selectedOptionId(for: selectedTier) {
                    QuoteEditView(
                        viewModel: QuoteEditViewModel(
                            estimateId: estimateId,
                            optionId: optionId,
                            quote: result.quote(for: selectedTier)
                        ),
                        tierName: selectedTier.rawValue,
                        onSaved: {
                            statusError = "Quote line items saved. Reopen to refresh totals."
                        }
                    )
                } else {
                    Text("Cannot edit this quote right now.")
                        .padding()
                }
            }
            .onAppear {
                estimateStatus = .draft
                Task {
                    companyInfo = await CompanySettingsService.shared.fetchCompanyInfo()
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let estimateNumber = result.estimateNumber {
                HStack {
                    Text("Quote #\(estimateNumber)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(estimateStatus.displayName)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(estimateStatus.color.opacity(0.2))
                        .foregroundStyle(estimateStatus.color)
                        .clipShape(Capsule())
                }
            }
            Text(result.issue.subcategory)
                .font(.title3.weight(.semibold))
            Text(result.issue.description)
                .font(.subheadline)
                .foregroundColor(.secondary)

            if let customerName = result.customerName, !customerName.isEmpty {
                Text("Customer: \(customerName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let customerAddress = result.customerAddress, !customerAddress.isEmpty {
                Text("Address: \(customerAddress)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let transcript = result.voiceTranscript, !transcript.isEmpty, showBreakdown {
                Divider()
                Text(transcript)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func tierCard(for tier: QuoteTier) -> some View {
        let quote = result.quote(for: tier)

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTier = tier
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(tier.rawValue)
                        .font(.headline)
                        .foregroundStyle(tier.color)
                    if tier == .better {
                        Text("Most Popular")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Text(formatCurrency(quote.computedTotal))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                }

                Text(quote.solutionDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)

                Text("\(quote.warrantyMonths)-month warranty")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selectedTier == tier ? tier.color : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func quoteBreakdownCard(for quote: Quote) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(selectedTier.rawValue) Breakdown")
                .font(.headline)

            ForEach(quote.lineItems) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.partName)
                            .font(.subheadline)
                        Text("\(item.brand) • \(item.partNumber)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(formatCurrency(item.unitPrice * item.quantity))
                        .font(.subheadline.weight(.medium))
                }
            }

            Divider()

            HStack {
                Text("Parts")
                Spacer()
                Text(formatCurrency(quote.computedPartsTotal))
            }
            HStack {
                Text("Labor")
                Spacer()
                Text(formatCurrency(quote.computedLaborTotal))
            }
            HStack {
                Text("Tax")
                Spacer()
                Text(formatCurrency(quote.computedTax))
            }
            HStack {
                Text("Total")
                    .fontWeight(.bold)
                Spacer()
                Text(formatCurrency(quote.computedTotal))
                    .fontWeight(.bold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                prepareAndSharePDF()
                Task { await updateEstimateStatus(.sent) }
            } label: {
                HStack {
                    Image(systemName: "paperplane.fill")
                    Text(isUpdatingStatus ? "Updating..." : "Send to Customer")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(selectedTier.color)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isUpdatingStatus)

            HStack(spacing: 12) {
                Button {
                    showSignaturePad = true
                } label: {
                    Text("Mark Accepted")
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.green.opacity(0.15))
                        .foregroundStyle(.green)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isUpdatingStatus)

                Button {
                    Task { await updateEstimateStatus(.rejected) }
                } label: {
                    Text("Mark Rejected")
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.red.opacity(0.15))
                        .foregroundStyle(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isUpdatingStatus)
            }

            Button {
                showEditQuote = true
            } label: {
                HStack {
                    Image(systemName: "square.and.pencil")
                    Text("Edit Quote")
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color(.systemGray5))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button {
                withAnimation {
                    showBreakdown.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "list.bullet.rectangle")
                    Text(showBreakdown ? "Hide Full Breakdown" : "See Full Breakdown")
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color(.systemGray5))
                .foregroundColor(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
    
    private func generateShareText() -> String {
        let quote = result.quote(for: selectedTier)
        let quoteNumber = result.estimateNumber.map { "Quote #\($0)\n" } ?? ""
        return """
PlumbQuote - \(selectedTier.rawValue) Option
\(quoteNumber)Issue: \(result.issue.subcategory)
\(result.issue.description)

Includes:
\(quote.solutionDescription)

\(result.customerName.map { "Customer: \($0)\n" } ?? "")\(result.customerAddress.map { "Address: \($0)\n" } ?? "")
Parts: \(formatCurrency(quote.computedPartsTotal))
Labor: \(formatCurrency(quote.computedLaborTotal))
Tax: \(formatCurrency(quote.computedTax))
Total: \(formatCurrency(quote.computedTotal))

Warranty: \(quote.warrantyMonths) months
"""
    }

    private func prepareAndSharePDF() {
        do {
            let rendered = try PDFQuoteRenderer.render(
                result: result,
                tier: selectedTier,
                companyInfo: companyInfo,
                signature: signatureImage
            )
            shareItems = [rendered.url]
            showShareSheet = true
        } catch {
            statusError = "Could not generate PDF: \(error.localizedDescription)"
        }
    }

    private func selectedOptionId(for tier: QuoteTier) -> String? {
        let quote = result.quote(for: tier)
        if let optionId = quote.optionId, !optionId.isEmpty {
            return optionId
        }
        let prefix = "EstimateOptionId:"
        guard let range = quote.notes.range(of: prefix) else { return nil }
        return quote.notes[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updateEstimateStatus(_ status: EstimateStatus, signature: UIImage? = nil) async {
        guard let estimateId = result.remoteId else { return }
        isUpdatingStatus = true
        statusError = nil
        defer { isUpdatingStatus = false }

        do {
            let optionId = selectedOptionId(for: selectedTier)
            _ = try await EstimateService.shared.updateStatus(
                estimateId: estimateId,
                status: status,
                selectedOptionId: optionId,
                signatureImage: signature
            )
            estimateStatus = status
        } catch {
            ErrorLogger.log(
                message: "Quote status update failed: \(error.localizedDescription)",
                context: [
                    "source": "QuoteResultView.updateEstimateStatus",
                    "estimateId": estimateId,
                    "status": status.rawValue
                ]
            )
            statusError = error.localizedDescription
        }
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    QuoteResultView(
        result: QuoteResult(
            issue: PlumbingIssue(
                category: "Faucet",
                subcategory: "Kitchen Faucet Repair",
                description: "Leaking kitchen faucet — water dripping from handle area.",
                severity: .moderate,
                confidence: 0.85,
                recommendedSolutions: [:]
            ),
            good: Quote(
                tier: "Good",
                lineItems: [
                    QuoteLineItem(partName: "Faucet Cartridge", partNumber: "FC-1202", brand: "Standard", unitPrice: 45, quantity: 1, category: "part")
                ],
                laborHours: 1.0,
                laborRate: 95,
                warrantyMonths: 3,
                solutionDescription: "Resolve the immediate leak with standard parts.",
                notes: ""
            ),
            better: Quote(
                tier: "Better",
                lineItems: [
                    QuoteLineItem(partName: "Faucet Cartridge", partNumber: "FC-1202", brand: "OEM", unitPrice: 89, quantity: 1, category: "part")
                ],
                laborHours: 1.2,
                laborRate: 110,
                warrantyMonths: 12,
                solutionDescription: "Fix root cause with higher-grade parts and extended warranty.",
                notes: ""
            ),
            best: Quote(
                tier: "Best",
                lineItems: [
                    QuoteLineItem(partName: "Faucet Cartridge", partNumber: "FC-1202", brand: "Premium", unitPrice: 129, quantity: 1, category: "part")
                ],
                laborHours: 1.5,
                laborRate: 130,
                warrantyMonths: 24,
                solutionDescription: "Future-proof repair with premium parts and full preventive inspection.",
                notes: ""
            ),
            voiceTranscript: "Kitchen faucet is leaking under the handle"
        ),
        selectedTier: .constant(.better)
    ) { }
}
