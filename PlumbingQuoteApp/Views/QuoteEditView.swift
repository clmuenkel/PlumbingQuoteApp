import SwiftUI

struct QuoteEditView: View {
    private enum Field: Hashable {
        case unitPrice(String)
    }

    @Environment(\.dismiss) private var dismiss
    @StateObject var viewModel: QuoteEditViewModel
    let tierName: String
    let onSaved: (Quote) -> Void
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("\(tierName) Total")
                            .font(.headline)
                        Spacer()
                        Text(formatCurrency(viewModel.total))
                            .font(.headline)
                    }
                }

                Section("Line Items") {
                    ForEach($viewModel.editableLineItems) { $item in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Item name", text: $item.name)
                                .font(.subheadline.weight(.semibold))

                            HStack {
                                Text("Qty")
                                Spacer()
                                Stepper(value: $item.quantity, in: 0...99, step: 1) {
                                    Text(String(format: "%.0f", item.quantity))
                                }
                                .labelsHidden()
                            }

                            HStack {
                                Text("Unit Price")
                                Spacer()
                                TextField("0.00", value: $item.unitPrice, format: .number.precision(.fractionLength(2)))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .focused($focusedField, equals: .unitPrice(item.id))
                                    .frame(minWidth: 80, idealWidth: 100, maxWidth: 130)
                            }

                            HStack {
                                Text("Line Total")
                                Spacer()
                                Text(formatCurrency(item.lineTotal))
                                    .fontWeight(.semibold)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: viewModel.removeLineItem)

                    Button {
                        viewModel.addLineItem()
                    } label: {
                        Label("Add Line Item", systemImage: "plus.circle.fill")
                    }
                }

                Section("Labor") {
                    Stepper(value: $viewModel.laborHours, in: 0...24, step: 0.25) {
                        HStack {
                            Text("Hours")
                            Spacer()
                            Text(String(format: "%.2f", viewModel.laborHours))
                        }
                    }
                }

                Section("Summary") {
                    summaryRow("Parts", value: viewModel.partsTotal)
                    summaryRow("Labor", value: viewModel.laborTotal)
                    summaryRow("Tax", value: viewModel.tax)
                    summaryRow("Total", value: viewModel.total, bold: true)
                }

                if let error = viewModel.error {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit \(tierName)")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(viewModel.isSaving ? "Saving..." : "Save") {
                        Task {
                            if await viewModel.save() {
                                onSaved(viewModel.buildUpdatedQuote())
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel.isSaving)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func summaryRow(_ title: String, value: Double, bold: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(formatCurrency(value))
                .fontWeight(bold ? .bold : .regular)
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}
