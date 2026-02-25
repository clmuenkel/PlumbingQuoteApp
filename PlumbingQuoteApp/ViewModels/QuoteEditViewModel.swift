import Foundation

@MainActor
final class QuoteEditViewModel: ObservableObject {
    @Published var editableLineItems: [EditableLineItem]
    @Published var laborHours: Double
    @Published var laborRate: Double
    @Published var isSaving = false
    @Published var error: String?

    private let estimateId: String
    private let optionId: String

    init(estimateId: String, optionId: String, quote: Quote) {
        self.estimateId = estimateId
        self.optionId = optionId
        self.editableLineItems = quote.lineItems.map { item in
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
        self.laborRate = quote.laborRate
    }

    var partsTotal: Double {
        editableLineItems.reduce(0) { $0 + $1.lineTotal }
    }

    var laborTotal: Double {
        laborHours * laborRate
    }

    var tax: Double {
        partsTotal * 0.08
    }

    var total: Double {
        partsTotal + laborTotal + tax
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

    func save() async -> Bool {
        isSaving = true
        error = nil
        defer { isSaving = false }

        do {
            let payload = EstimateService.UpdateOptionPayload(
                optionId: optionId,
                lineItems: editableLineItems.map { item in
                    EstimateService.UpdateOptionLineItem(
                        id: item.id,
                        name: item.name,
                        description: item.description,
                        unitPrice: item.unitPrice,
                        quantity: item.quantity,
                        unit: item.unit
                    )
                },
                laborHours: laborHours
            )
            try await EstimateService.shared.updateOptions(
                estimateId: estimateId,
                payload: payload
            )
            return true
        } catch {
            ErrorLogger.log(
                message: "Quote edit save failed: \(error.localizedDescription)",
                context: ["source": "QuoteEditViewModel.save", "estimateId": estimateId, "optionId": optionId]
            )
            self.error = error.localizedDescription
            return false
        }
    }
}
