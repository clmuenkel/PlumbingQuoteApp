import SwiftUI
import MessageUI

struct QuoteResultView: View {
    let result: QuoteResult
    var jobPhotos: [UIImage] = []
    @Binding var selectedTier: QuoteTier
    let onDismiss: () -> Void
    var onQuoteSaved: ((QuoteTier, Quote) -> Void)? = nil

    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var showBreakdown = false
    @State private var showComparison = false
    @State private var estimateStatus: EstimateStatus = .draft
    @State private var statusError: String?
    @State private var isUpdatingStatus = false
    @State private var companyInfo: CompanyInfo = .default
    @State private var showSignaturePad = false
    @State private var signatureImage: UIImage?
    @State private var showEditQuote = false
    @State private var quoteOverrides: [QuoteTier: Quote] = [:]
    @State private var showMessageComposer = false
    @State private var showMailComposer = false
    @State private var deliveryDraft: DeliveryDraft?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    if !result.failedUploads.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("Some photos failed to upload. Quote was saved.")
                                .font(.caption.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(AppTheme.warning.opacity(0.16))
                        .foregroundStyle(AppTheme.text)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    tierCard(for: .good)
                    tierCard(for: .better)
                    tierCard(for: .best)
                    pricingIntelligenceCard(for: quote(for: selectedTier))

                    if showComparison {
                        comparisonCard
                    }

                    if showBreakdown {
                        quoteBreakdownCard(for: quote(for: selectedTier))
                    }

                    actionButtons

                    if let statusError {
                        Text(statusError)
                            .font(.caption)
                            .foregroundStyle(AppTheme.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 10)
                .padding(.bottom, 20)
            }
            .background(AppTheme.bgAlt)
            .navigationTitle("Your Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.bgAlt, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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
            .sheet(isPresented: $showMessageComposer) {
                if let draft = deliveryDraft {
                    MessageComposer(
                        recipients: draft.phone.map { [$0] } ?? [],
                        body: draft.body,
                        attachmentData: draft.pdfData,
                        attachmentName: draft.fileName
                    )
                } else {
                    Text("Could not prepare SMS.")
                        .padding()
                }
            }
            .sheet(isPresented: $showMailComposer) {
                if let draft = deliveryDraft {
                    MailComposer(
                        subject: draft.subject,
                        recipients: draft.email.map { [$0] } ?? [],
                        body: draft.body,
                        attachmentData: draft.pdfData,
                        attachmentName: draft.fileName
                    )
                } else {
                    Text("Could not prepare email.")
                        .padding()
                }
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
                    let editingTier = selectedTier
                    QuoteEditView(
                        viewModel: QuoteEditViewModel(
                            estimateId: estimateId,
                            optionId: optionId,
                            quote: quote(for: selectedTier)
                        ),
                        tierName: selectedTier.rawValue,
                        onSaved: { updatedQuote in
                            quoteOverrides[editingTier] = updatedQuote
                            onQuoteSaved?(editingTier, updatedQuote)
                            statusError = "Quote line items saved."
                        }
                    )
                } else {
                    Text("Cannot edit this quote right now.")
                        .padding()
                }
            }
            .onAppear {
                Task {
                    companyInfo = await CompanySettingsService.shared.fetchCompanyInfo()
                    await loadEstimateStatusIfNeeded()
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let estimateNumber = result.estimateNumber {
                HStack {
                    Text(formattedEstimateNumber(estimateNumber))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
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
                .foregroundColor(AppTheme.muted)

            if let customerName = result.customerName, !customerName.isEmpty {
                Text("Customer: \(customerName)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }

            if let customerEmail = result.customerEmail, !customerEmail.isEmpty {
                Text("Email: \(customerEmail)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }

            if let customerAddress = result.customerAddress, !customerAddress.isEmpty {
                Text("Address: \(customerAddress)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }

            if let transcript = result.voiceTranscript, !transcript.isEmpty, showBreakdown {
                Divider()
                Text(transcript)
                    .font(.caption)
                    .foregroundColor(AppTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
    }

    private func tierCard(for tier: QuoteTier) -> some View {
        let quote = quote(for: tier)

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTier = tier
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        if selectedTier == tier {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(tier.color)
                        }
                        Text(tier.rawValue)
                            .font(.headline)
                            .foregroundStyle(tier.color)
                    }
                    if tier == .better {
                        Text("Most Popular")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AppTheme.accentLight.opacity(0.6))
                            .foregroundStyle(AppTheme.accent)
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Text(CurrencyFormatter.usd(quote.computedTotal))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.text)
                }

                Text(quote.solutionDescription)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
                    .multilineTextAlignment(.leading)

                Text("\(quote.warrantyMonths)-month warranty")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .fill(tier == .better ? AppTheme.accentLight.opacity(0.25) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selectedTier == tier ? tier.color : .clear, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
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
                            .foregroundStyle(AppTheme.muted)
                    }
                    Spacer()
                    Text(CurrencyFormatter.usd(item.unitPrice * item.quantity))
                        .font(.subheadline.weight(.medium))
                }
            }

            Divider()

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
            HStack {
                Text("Total")
                    .fontWeight(.bold)
                Spacer()
                Text(CurrencyFormatter.usd(quote.computedTotal))
                    .fontWeight(.bold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
    }

    private func pricingIntelligenceCard(for quote: Quote) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pricing Intelligence")
                .font(.headline)

            HStack {
                Text("Recommended")
                Spacer()
                Text(CurrencyFormatter.usd(quote.computedTotal))
                    .font(.headline.weight(.semibold))
            }

            if let priceBookPrice = quote.priceBookPrice {
                HStack {
                    Text("Your price book")
                    Spacer()
                    Text(CurrencyFormatter.usd(priceBookPrice))
                        .foregroundStyle(AppTheme.muted)
                }
            }

            if let marketAverage = quote.marketAverage {
                HStack {
                    Text("DFW market average")
                    Spacer()
                    Text(CurrencyFormatter.usd(marketAverage))
                        .foregroundStyle(AppTheme.muted)
                }
            }

            if let marketRange = quote.marketRange {
                HStack {
                    Text("DFW market range")
                    Spacer()
                    Text("\(CurrencyFormatter.usd(marketRange.low)) - \(CurrencyFormatter.usd(marketRange.high))")
                        .foregroundStyle(AppTheme.muted)
                }
            }

            if let confidence = quote.confidenceScore {
                HStack {
                    Text("Confidence")
                    Spacer()
                    Text("\(Int((confidence * 100).rounded()))%")
                        .foregroundStyle(confidence >= 0.8 ? AppTheme.success : AppTheme.warning)
                }
            }

            if let marketPositionPercent = quote.marketPositionPercent {
                Text(marketPositionPercent >= 0
                     ? "You are \(Int(marketPositionPercent.rounded()))% above market average."
                     : "You are \(Int(abs(marketPositionPercent).rounded()))% below market average.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }

            if let reasoning = quote.reasoning, !reasoning.isEmpty {
                Text(reasoning)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }

            if let flags = quote.validationFlags, !flags.isEmpty {
                Divider()
                ForEach(flags, id: \.self) { flag in
                    Label(flag, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.warning)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if estimateStatus == .draft || estimateStatus == .sent {
                Button {
                    if estimateStatus == .draft {
                        prepareAndSharePDF()
                        Task { await updateEstimateStatus(.sent) }
                    } else {
                        showSignaturePad = true
                    }
                } label: {
                    HStack {
                        Image(systemName: estimateStatus == .draft ? "paperplane.fill" : "checkmark.circle.fill")
                        Text(
                            isUpdatingStatus
                            ? "Updating..."
                            : (estimateStatus == .draft ? "Send to Customer" : "Mark Accepted")
                        )
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: primaryButtonHeight)
                    .background(estimateStatus == .draft ? selectedTier.color : AppTheme.success)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isUpdatingStatus)
            }

            VStack(alignment: .leading, spacing: 10) {
                if estimateStatus == .sent {
                    rejectButton
                }
                contactActionButtons
                editQuoteButton
                comparisonButton
                breakdownButton
            }
        }
    }

    private var rejectButton: some View {
        Button {
            Task { await updateEstimateStatus(.rejected) }
        } label: {
            Label("Reject", systemImage: "xmark.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.error)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
                .padding(.horizontal, 12)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isUpdatingStatus)
        .buttonStyle(.plain)
    }

    private var editQuoteButton: some View {
        Button {
            showEditQuote = true
        } label: {
            Label("Edit Quote", systemImage: "square.and.pencil")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
                .padding(.horizontal, 12)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var contactActionButtons: some View {
        if MFMessageComposeViewController.canSendText() {
            Button {
                sendViaText()
            } label: {
                Label("Text Customer", systemImage: "message")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 12)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }

        if MFMailComposeViewController.canSendMail() {
            Button {
                sendViaEmail()
            } label: {
                Label("Email Quote", systemImage: "envelope")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 12)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    private var breakdownButton: some View {
        Button {
            withAnimation {
                showBreakdown.toggle()
            }
        } label: {
            Label(
                showBreakdown ? "Hide Breakdown" : "Full Breakdown",
                systemImage: "list.bullet.rectangle"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.text)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var comparisonButton: some View {
        Button {
            withAnimation {
                showComparison.toggle()
            }
        } label: {
            Label(
                showComparison ? "Hide Comparison" : "Compare Options",
                systemImage: "rectangle.split.3x1"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.text)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var comparisonCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Side-by-Side Comparison")
                .font(.headline)
            comparisonMetricRow(title: "Total", values: [
                CurrencyFormatter.usd(quote(for: .good).computedTotal),
                CurrencyFormatter.usd(quote(for: .better).computedTotal),
                CurrencyFormatter.usd(quote(for: .best).computedTotal)
            ])
            comparisonMetricRow(title: "Warranty", values: [
                "\(quote(for: .good).warrantyMonths) mo",
                "\(quote(for: .better).warrantyMonths) mo",
                "\(quote(for: .best).warrantyMonths) mo"
            ])
            comparisonMetricRow(title: "Labor Hours", values: [
                String(format: "%.1f", quote(for: .good).laborHours),
                String(format: "%.1f", quote(for: .better).laborHours),
                String(format: "%.1f", quote(for: .best).laborHours)
            ])

            Divider()

            Text("What you get")
                .font(.subheadline.weight(.semibold))
            Text("Better adds: \(deltaSummary(from: quote(for: .good), to: quote(for: .better)))")
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
            Text("Best adds: \(deltaSummary(from: quote(for: .better), to: quote(for: .best)))")
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
    }

    private func comparisonMetricRow(title: String, values: [String]) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .frame(width: 90, alignment: .leading)
            Text("Good: \(values[0])")
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Better: \(values[1])")
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Best: \(values[2])")
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func deltaSummary(from base: Quote, to upgraded: Quote) -> String {
        let baseItems = Set(base.lineItems.map { $0.partName.lowercased() })
        let added = upgraded.lineItems
            .map { $0.partName }
            .filter { !baseItems.contains($0.lowercased()) }
        if added.isEmpty {
            return "expanded labor scope and upgraded warranty."
        }
        return added.prefix(3).joined(separator: ", ") + (added.count > 3 ? ", and more." : ".")
    }

    private var isCompactWidth: Bool {
        horizontalSizeClass == .compact
    }

    private var horizontalPadding: CGFloat {
        isCompactWidth ? 16 : 20
    }

    private var secondaryButtonHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 50 : 44
    }

    private var primaryButtonHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 54 : 48
    }

    private func generateShareText() -> String {
        let quote = quote(for: selectedTier)
        let quoteNumber = result.estimateNumber.map { "\(formattedEstimateNumber($0))\n" } ?? ""
        return """
PlumbQuote - \(selectedTier.rawValue) Option
\(quoteNumber)Issue: \(result.issue.subcategory)
\(result.issue.description)

Includes:
\(quote.solutionDescription)

\(result.customerName.map { "Customer: \($0)\n" } ?? "")\(result.customerAddress.map { "Address: \($0)\n" } ?? "")
Parts: \(CurrencyFormatter.usd(quote.computedPartsTotal))
Labor: \(CurrencyFormatter.usd(quote.computedLaborTotal))
Tax: \(CurrencyFormatter.usd(quote.computedTax))
Total: \(CurrencyFormatter.usd(quote.computedTotal))

Warranty: \(quote.warrantyMonths) months
"""
    }

    private func sendViaText() {
        guard let phone = result.customerPhone, !phone.isEmpty else {
            statusError = "Add a customer phone number before sending text."
            return
        }
        guard MFMessageComposeViewController.canSendText() else {
            statusError = "Text messaging is not available on this device."
            return
        }
        guard let draft = prepareDeliveryDraft() else { return }
        deliveryDraft = DeliveryDraft(
            pdfData: draft.pdfData,
            fileName: draft.fileName,
            body: draft.body,
            subject: draft.subject,
            phone: phone,
            email: draft.email
        )
        showMessageComposer = true
    }

    private func sendViaEmail() {
        guard let email = result.customerEmail, !email.isEmpty else {
            statusError = "Add a customer email before sending."
            return
        }
        guard MFMailComposeViewController.canSendMail() else {
            statusError = "Mail is not configured on this device."
            return
        }
        guard var draft = prepareDeliveryDraft() else { return }
        draft.email = email
        deliveryDraft = draft
        showMailComposer = true
    }

    private func prepareAndSharePDF() {
        guard let draft = prepareDeliveryDraft() else { return }
        shareItems = [draft.fileURL]
        showShareSheet = true
    }

    private func prepareDeliveryDraft() -> DeliveryDraft? {
        do {
            let rendered = try PDFQuoteRenderer.render(
                result: result,
                tier: selectedTier,
                companyInfo: companyInfo,
                signature: signatureImage,
                jobPhotos: jobPhotos
            )
            let quoteNumber = result.estimateNumber.map { String(format: "#%03d", $0) } ?? "#000"
            return DeliveryDraft(
                pdfData: rendered.data,
                fileName: rendered.url.lastPathComponent,
                body: "Here is your plumbing estimate \(quoteNumber) from \(companyInfo.name).",
                subject: "Your Plumbing Estimate \(quoteNumber)",
                phone: result.customerPhone,
                email: result.customerEmail,
                fileURL: rendered.url
            )
        } catch {
            statusError = "Could not generate PDF: \(error.localizedDescription)"
            return nil
        }
    }

    private func selectedOptionId(for tier: QuoteTier) -> String? {
        let quote = quote(for: tier)
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
            estimateStatus = EstimateStatus(rawValue: status.rawValue) ?? status
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

    private func quote(for tier: QuoteTier) -> Quote {
        quoteOverrides[tier] ?? result.quote(for: tier)
    }

    private func formattedEstimateNumber(_ number: Int) -> String {
        String(format: "Quote #%03d", number)
    }

    private func loadEstimateStatusIfNeeded() async {
        guard let estimateId = result.remoteId else {
            estimateStatus = .draft
            return
        }
        do {
            let row: [EstimateStatusRow] = try await SupabaseService.shared.client
                .from("Estimate")
                .select("status")
                .eq("id", value: estimateId)
                .limit(1)
                .execute()
                .value
            if let statusValue = row.first?.status,
               let status = EstimateStatus(rawValue: statusValue) {
                estimateStatus = status
            } else {
                estimateStatus = .draft
            }
        } catch {
            estimateStatus = .draft
        }
    }
}

private struct EstimateStatusRow: Decodable {
    let status: String
}

private struct DeliveryDraft {
    let pdfData: Data
    let fileName: String
    let body: String
    let subject: String
    let phone: String?
    var email: String?
    let fileURL: URL

    init(
        pdfData: Data,
        fileName: String,
        body: String,
        subject: String,
        phone: String?,
        email: String?,
        fileURL: URL? = nil
    ) {
        self.pdfData = pdfData
        self.fileName = fileName
        self.body = body
        self.subject = subject
        self.phone = phone
        self.email = email
        if let fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
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

struct MessageComposer: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    let attachmentData: Data
    let attachmentName: String
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.recipients = recipients
        controller.body = body
        if MFMessageComposeViewController.canSendAttachments() {
            controller.addAttachmentData(
                attachmentData,
                typeIdentifier: "com.adobe.pdf",
                filename: attachmentName
            )
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        private let dismissAction: DismissAction

        init(dismiss: DismissAction) {
            self.dismissAction = dismiss
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            dismissAction()
        }
    }
}

struct MailComposer: UIViewControllerRepresentable {
    let subject: String
    let recipients: [String]
    let body: String
    let attachmentData: Data
    let attachmentName: String
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setSubject(subject)
        controller.setToRecipients(recipients)
        controller.setMessageBody(body, isHTML: false)
        controller.addAttachmentData(attachmentData, mimeType: "application/pdf", fileName: attachmentName)
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let dismissAction: DismissAction

        init(dismiss: DismissAction) {
            self.dismissAction = dismiss
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            dismissAction()
        }
    }
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
    ) { } onQuoteSaved: { _, _ in }
}
