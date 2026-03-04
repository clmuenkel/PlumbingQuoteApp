import SwiftUI

struct SettingsView: View {
    private enum Field {
        case companyPhone
        case laborRate
        case taxRate
    }

    @State private var settings = CompanySettingsService.CompanySettingsData(
        companyName: CompanyInfo.default.name,
        companyPhone: "",
        companyAddress: "",
        laborRatePerHour: 95,
        taxRate: 0.08
    )
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var error: String?
    @State private var saveMessage: String?
    @State private var taxRatePercent: String = "8"
    @FocusState private var focusedField: Field?

    var body: some View {
        Form {
            Section("Company") {
                TextField("Company name", text: $settings.companyName)
                TextField("Phone", text: $settings.companyPhone)
                    .keyboardType(.phonePad)
                    .focused($focusedField, equals: .companyPhone)
                TextField("Address", text: $settings.companyAddress)
            }

            Section("Pricing") {
                HStack {
                    Text("Labor Rate / Hour")
                    Spacer()
                    TextField(
                        "0.00",
                        value: $settings.laborRatePerHour,
                        format: .number.precision(.fractionLength(2))
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .laborRate)
                    .frame(minWidth: 90, idealWidth: 110, maxWidth: 140)
                }

                HStack {
                    Text("Tax Rate")
                    Spacer()
                    TextField("0", text: $taxRatePercent)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .taxRate)
                    .frame(minWidth: 90, idealWidth: 110, maxWidth: 140)
                    Text("%")
                        .foregroundStyle(AppTheme.muted)
                }
            }

            Section {
                Button {
                    Task { await saveSettings() }
                } label: {
                    HStack {
                        if isSaving {
                            ProgressView()
                        }
                        Text(isSaving ? "Saving..." : "Save Settings")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(isSaving || isLoading)
            }

            if let saveMessage {
                Section {
                    Text(saveMessage)
                        .foregroundStyle(AppTheme.success)
                        .font(.caption)
                }
            }

            if let error {
                Section {
                    Text(error)
                        .foregroundStyle(AppTheme.error)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Settings")
        .scrollContentBackground(.hidden)
        .background(AppTheme.bg)
        .toolbarBackground(AppTheme.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .disabled(isLoading)
        .overlay {
            if isLoading {
                ProgressView("Loading...")
            }
        }
        .task {
            await loadSettings()
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
            }
        }
    }

    private func loadSettings() async {
        isLoading = true
        defer { isLoading = false }
        error = nil
        settings = await CompanySettingsService.shared.fetchCompanySettings()
        taxRatePercent = String(format: "%.2f", settings.taxRate * 100)
    }

    private func saveSettings() async {
        isSaving = true
        defer { isSaving = false }
        error = nil
        saveMessage = nil

        settings.laborRatePerHour = max(0, settings.laborRatePerHour)
        let parsedPercent = Double(taxRatePercent.replacingOccurrences(of: ",", with: ".")) ?? 0
        settings.taxRate = parsedPercent / 100
        settings.taxRate = min(max(0, settings.taxRate), 1)

        do {
            try await CompanySettingsService.shared.updateCompanySettings(settings)
            saveMessage = "Settings saved."
        } catch {
            self.error = "Could not save settings: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
