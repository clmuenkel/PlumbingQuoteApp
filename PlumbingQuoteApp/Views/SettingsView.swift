import SwiftUI
import UniformTypeIdentifiers

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
    @State private var importMessage: String?
    @State private var showPriceBookImporter = false
    @State private var isImportingPriceBook = false
    @State private var taxRatePercent: String = "8"
    @State private var pdfTerms: String = CompanySettingsService.defaultPdfTerms
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

            Section("Quote PDF") {
                TextEditor(text: $pdfTerms)
                    .frame(minHeight: 110)
            }

            Section("Price Book") {
                Button {
                    showPriceBookImporter = true
                } label: {
                    HStack {
                        if isImportingPriceBook {
                            ProgressView()
                        }
                        Text(isImportingPriceBook ? "Importing..." : "Import Price Book CSV/XLSX")
                    }
                }
                .disabled(isImportingPriceBook)

                if let importMessage {
                    Text(importMessage)
                        .font(.caption)
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
        .fileImporter(
            isPresented: $showPriceBookImporter,
            allowedContentTypes: [
                .commaSeparatedText,
                UTType(filenameExtension: "csv") ?? .commaSeparatedText,
                UTType(filenameExtension: "xlsx") ?? .data
            ],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { await importPriceBook(from: url) }
        }
    }

    private func loadSettings() async {
        isLoading = true
        defer { isLoading = false }
        error = nil
        settings = await CompanySettingsService.shared.fetchCompanySettings()
        taxRatePercent = String(format: "%.2f", settings.taxRate * 100)
        pdfTerms = UserDefaults.standard.string(forKey: CompanySettingsService.pdfTermsDefaultsKey)
            ?? CompanySettingsService.defaultPdfTerms
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
            UserDefaults.standard.set(pdfTerms, forKey: CompanySettingsService.pdfTermsDefaultsKey)
            saveMessage = "Settings saved."
        } catch {
            self.error = "Could not save settings: \(error.localizedDescription)"
        }
    }

    private func importPriceBook(from url: URL) async {
        isImportingPriceBook = true
        defer { isImportingPriceBook = false }
        importMessage = nil

        guard let fileData = try? Data(contentsOf: url) else {
            importMessage = "Could not read selected file."
            return
        }
        let fileName = url.lastPathComponent

        do {
            let session = try await SupabaseService.shared.client.auth.session
            guard let endpoint = URL(string: "\(AppConfig.supabaseURL)/functions/v1/import-price-book") else {
                importMessage = "Invalid function endpoint."
                return
            }

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 120
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "fileName": fileName,
                "fileBase64": fileData.base64EncodedString()
            ])

            let (responseData, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                importMessage = "Import failed: no server response."
                return
            }
            guard (200...299).contains(http.statusCode) else {
                let message = String(data: responseData, encoding: .utf8) ?? "Unknown import error."
                importMessage = "Import failed: \(message)"
                return
            }
            importMessage = "Price book import completed."
        } catch {
            importMessage = "Import failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
