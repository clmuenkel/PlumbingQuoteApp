import Foundation

@MainActor
final class QuoteEditViewModel: ObservableObject {
    @Published var editableLineItems: [EditableLineItem]
    @Published var laborHours: Double
    @Published var laborRate: Double
    @Published var taxRate: Double
    @Published var isSaving = false
    @Published var error: String?

    private let estimateId: String
    private let optionId: String
    private let originalQuote: Quote

    init(estimateId: String, optionId: String, quote: Quote) {
        self.estimateId = estimateId
        self.optionId = optionId
        self.originalQuote = quote
        self.editableLineItems = quote.lineItems
            .filter { !$0.isLabor }
            .map { item in
            EditableLineItem(
                id: item.id,
                name: item.partName,
                description: "",
                unitPrice: item.unitPrice,
                quantity: item.quantity,
                unit: "each"
            )
        }
        self.laborHours = quote.laborHours
        self.laborRate = quote.laborRate > 0 ? quote.laborRate : 95
        self.taxRate = 0.08

        Task {
            await loadCompanyPricing()
        }
    }

    var partsTotal: Double {
        rounded2(editableLineItems.reduce(0) { sum, item in
            sum + rounded2(rounded2(item.unitPrice) * max(0, item.quantity))
        })
    }

    var laborTotal: Double {
        rounded2(max(0, laborHours) * laborRate)
    }

    var tax: Double {
        rounded2(partsTotal * taxRate)
    }

    var total: Double {
        rounded2(partsTotal + laborTotal + tax)
    }

    func addLineItem() {
        editableLineItems.append(
            EditableLineItem(
                id: UUID().uuidString,
                name: "New Item",
                description: "",
                unitPrice: 0,
                quantity: 1,
                unit: "each"
            )
        )
    }

    func removeLineItem(at offsets: IndexSet) {
        editableLineItems.remove(atOffsets: offsets)
    }

    func save() async -> Quote? {
        isSaving = true
        error = nil
        defer { isSaving = false }

        do {
            let partItems = editableLineItems.map(makeUpdateLineItem)
            let laborLineItem = EstimateService.UpdateOptionLineItem(
                id: nil,
                name: "Labor",
                description: "\(String(format: "%.2f", laborHours)) hours @ \(String(format: "%.2f", laborRate))/hr",
                unitPrice: laborRate,
                quantity: max(0, laborHours),
                unit: "hour"
            )
            let payload = EstimateService.UpdateOptionPayload(
                optionId: optionId,
                lineItems: partItems + [laborLineItem],
                laborHours: laborHours
            )
            let response = try await EstimateService.shared.updateOptions(
                estimateId: estimateId,
                payload: payload
            )

            guard let option = response.options.first(where: { $0.id == optionId }) else {
                return buildUpdatedQuote()
            }

            return buildUpdatedQuote(using: option)
        } catch {
            ErrorLogger.log(
                message: "Quote edit save failed: \(error.localizedDescription)",
                context: ["source": "QuoteEditViewModel.save", "estimateId": estimateId, "optionId": optionId]
            )
            self.error = error.localizedDescription
            return nil
        }
    }

    func buildUpdatedQuote() -> Quote {
        let fallback = EstimateService.UpdateOptionsResponse.UpdatedOption(
            id: optionId,
            tier: originalQuote.tier,
            subtotal: partsTotal,
            laborTotal: laborTotal,
            tax: tax,
            total: total,
            laborHours: laborHours,
            laborRate: laborRate
        )
        return buildUpdatedQuote(using: fallback)
    }

    private func buildUpdatedQuote(using option: EstimateService.UpdateOptionsResponse.UpdatedOption) -> Quote {
        var updatedLineItems = editableLineItems.map { item in
            QuoteLineItem(
                id: item.id,
                partName: item.name,
                partNumber: item.id,
                brand: "Custom",
                unitPrice: rounded2(item.unitPrice),
                quantity: max(0, item.quantity),
                category: "part"
            )
        }

        updatedLineItems.append(
            QuoteLineItem(
                partName: "Labor",
                partNumber: "labor",
                brand: "\(String(format: "%.2f", option.laborHours)) hours @ \(String(format: "%.2f", option.laborRate))/hr",
                unitPrice: option.laborRate,
                quantity: option.laborHours,
                category: "labor"
            )
        )

        return Quote(
            id: originalQuote.id,
            optionId: option.id,
            tier: originalQuote.tier,
            lineItems: updatedLineItems,
            laborHours: option.laborHours,
            laborRate: option.laborRate,
            laborTotal: option.laborTotal,
            partsTotal: option.subtotal,
            tax: option.tax,
            total: option.total,
            warrantyMonths: originalQuote.warrantyMonths,
            solutionDescription: originalQuote.solutionDescription,
            notes: originalQuote.notes
        )
    }

    private func makeUpdateLineItem(_ item: EditableLineItem) -> EstimateService.UpdateOptionLineItem {
        EstimateService.UpdateOptionLineItem(
            id: item.id,
            name: item.name,
            description: item.description,
            unitPrice: rounded2(item.unitPrice),
            quantity: max(0, item.quantity),
            unit: item.unit
        )
    }

    private func rounded2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private func loadCompanyPricing() async {
        let settings = await CompanySettingsService.shared.fetchCompanySettings()
        laborRate = rounded2(settings.laborRatePerHour)
        taxRate = max(0, settings.taxRate)
    }
}
