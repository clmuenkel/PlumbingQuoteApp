import Foundation
import UIKit
import SwiftUI
import Combine

struct DeveloperAlertInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

// MARK: - Main ViewModel
@MainActor
class QuoteViewModel: ObservableObject {
    #if DEBUG
    static let developerMode = true
    #else
    static let developerMode = false
    #endif
    static let minTextSignalLength = 12

    // Input state
    @Published var capturedImages: [UIImage] = []
    let voiceService = VoiceService()
    @Published var additionalNotes: String = ""
    @Published var customerName: String = ""
    @Published var customerPhone: String = ""
    @Published var customerEmail: String = ""
    @Published var customerAddress: String = ""
    @Published var queuedQuoteCount: Int = 0
    @Published var customerSuggestions: [CustomerService.Suggestion] = []

    // Output state
    @Published var quoteResult: QuoteResult?
    @Published var selectedTier: QuoteTier = .better

    // UI state
    @Published var isAnalyzing = false
    @Published var error: String?
    @Published var showQuoteResult = false
    @Published var generationStep: String = ""
    @Published var developerAlert: DeveloperAlertInfo?
    @Published var showOverridePrompt = false
    @Published var overridePromptReasons: [String] = []

    private let aiService = AIQuoteService()
    private var analysisTask: Task<Void, Never>?
    private var voiceServiceCancellable: AnyCancellable?
    private var networkCancellable: AnyCancellable?
    private var queueProcessingTask: Task<Void, Never>?

    init() {
        queuedQuoteCount = OfflineQueueService.shared.pendingCount()
        voiceServiceCancellable = voiceService.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        networkCancellable = NetworkMonitor.shared.$isConnected
            .removeDuplicates()
            .sink { [weak self] isConnected in
                guard let self else { return }
                if isConnected {
                    self.queueProcessingTask = Task { await self.processQueuedQuotesIfNeeded() }
                }
            }
    }

    var isConnected: Bool {
        NetworkMonitor.shared.isConnected
    }

    var canSubmit: Bool {
        !capturedImages.isEmpty
    }

    func clearInputs() {
        capturedImages.removeAll()
        voiceService.clearTranscript()
        additionalNotes = ""
        customerName = ""
        customerPhone = ""
        customerEmail = ""
        customerAddress = ""
        customerSuggestions = []
        quoteResult = nil
        showQuoteResult = false
        error = nil
        generationStep = ""
    }

    func startGenerateQuote(forceOverride: Bool = false) {
        guard analysisTask == nil else { return }
        guard isConnected else {
            enqueueCurrentInputForLater()
            queuedQuoteCount = OfflineQueueService.shared.pendingCount()
            error = "No internet connection. Quote saved to offline queue and will auto-submit when reconnected."
            ErrorLogger.log(
                message: "Quote generation queued: device offline",
                context: ["source": "QuoteViewModel.startGenerateQuote"]
            )
            showDeveloperAlert(
                title: "Developer Mode: Offline",
                message: "Quote generation blocked because device is offline."
            )
            HapticsService.error()
            return
        }
        if !forceOverride, let reasons = localSignalWarningReasons {
            overridePromptReasons = reasons
            showOverridePrompt = true
            error = "Input may be too weak for a reliable quote."
            return
        }
        analysisTask = Task { [weak self] in
            guard let self else { return }
            await self.generateQuote(forceOverride: forceOverride)
            await MainActor.run { self.analysisTask = nil }
        }
    }

    func retryQuoteGeneration() {
        startGenerateQuote()
    }

    func cancelQuoteGeneration() {
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
        generationStep = ""
        error = "Quote generation was cancelled."
        ErrorLogger.log(
            message: "Quote generation cancelled by user",
            severity: "warning",
            context: ["source": "QuoteViewModel.cancelQuoteGeneration"]
        )
        showDeveloperAlert(
            title: "Developer Mode: Generation Cancelled",
            message: "Quote generation task was cancelled by the user."
        )
        HapticsService.error()
    }

    private func generateQuote(forceOverride: Bool) async {
        guard canSubmit else {
            error = "Please add at least one photo to generate a quote."
            ErrorLogger.log(
                message: "Quote generation blocked: no photos",
                context: ["source": "QuoteViewModel.generateQuote"]
            )
            showDeveloperAlert(
                title: "Developer Mode: Missing Input",
                message: "Cannot generate quote because no photos were provided."
            )
            return
        }

        isAnalyzing = true
        error = nil
        generationStep = "Uploading photos..."

        do {
            try await Task.sleep(nanoseconds: 300_000_000)
        } catch {
            generationStep = ""
            return
        }
        generationStep = "Analyzing issue..."

        let audioPayload = voiceService.audioPayload()

        let result = await aiService.analyzeAndQuote(
            images: capturedImages,
            audioBase64: audioPayload?.base64,
            audioMimeType: audioPayload?.mimeType,
            voiceTranscript: voiceService.transcript.isEmpty ? nil : voiceService.transcript,
            additionalNotes: additionalNotes.isEmpty ? nil : additionalNotes,
            customerName: customerName.isEmpty ? nil : customerName,
            customerPhone: customerPhone.isEmpty ? nil : customerPhone,
            customerEmail: customerEmail.isEmpty ? nil : customerEmail,
            customerAddress: customerAddress.isEmpty ? nil : customerAddress,
            allowOverride: forceOverride
        )
        generationStep = "Building quote options..."

        isAnalyzing = false
        generationStep = ""

        if Task.isCancelled {
            error = "Quote generation was cancelled."
            ErrorLogger.log(
                message: "Quote generation cancelled during async execution",
                severity: "warning",
                context: ["source": "QuoteViewModel.generateQuote"]
            )
            showDeveloperAlert(
                title: "Developer Mode: Task Cancelled",
                message: "Task cancellation occurred before quote result completed."
            )
            HapticsService.error()
            return
        }

        if let result = result {
            quoteResult = result
            showQuoteResult = true
            HapticsService.quoteGenerated()
        } else {
            if let feedback = aiService.lastGatingFeedback, feedback.canOverride, !forceOverride {
                overridePromptReasons = feedback.reasons
                showOverridePrompt = true
                error = "Input quality warning. Review and choose how to proceed."
            }
            error = aiService.error ?? "Failed to generate quote. Please try again."
            ErrorLogger.log(
                message: "Quote generation failed: \(error ?? "Unknown error")",
                context: [
                    "source": "QuoteViewModel.generateQuote",
                    "imageCount": String(capturedImages.count),
                    "hasTranscript": String(voiceService.hasTranscript),
                    "gatingStatus": aiService.lastGatingFeedback?.status ?? "none",
                    "gatingReasons": aiService.lastGatingFeedback?.reasons.joined(separator: " | ") ?? "none"
                ]
            )
            showDeveloperAlert(
                title: "Developer Mode: Quote Generation Failed",
                message: error ?? "Unknown quote generation failure."
            )
            HapticsService.error()
        }
    }

    private var localSignalWarningReasons: [String]? {
        let transcriptLength = voiceService.transcript.trimmingCharacters(in: .whitespacesAndNewlines).count
        let notesLength = additionalNotes.trimmingCharacters(in: .whitespacesAndNewlines).count
        if transcriptLength >= Self.minTextSignalLength || notesLength >= Self.minTextSignalLength {
            return nil
        }
        return [
            "Description is too short. Add more detail by voice or notes."
        ]
    }

    private func showDeveloperAlert(title: String, message: String) {
        guard Self.developerMode else { return }
        developerAlert = DeveloperAlertInfo(title: title, message: message)
    }

    func refreshCustomerSuggestions(for query: String) {
        Task {
            let suggestions = await CustomerService.shared.searchCustomers(query: query)
            await MainActor.run {
                self.customerSuggestions = suggestions
            }
        }
    }

    func applyCustomerSuggestion(_ suggestion: CustomerService.Suggestion) {
        customerName = suggestion.fullName
        customerPhone = suggestion.phone ?? customerPhone
        customerEmail = suggestion.email ?? customerEmail
        customerAddress = suggestion.address ?? customerAddress
        customerSuggestions = []
    }

    func clearCustomerSuggestions() {
        customerSuggestions = []
    }

    func applyJobTemplate(_ template: String) {
        let existing = additionalNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if existing.isEmpty {
            additionalNotes = template
        } else {
            additionalNotes = existing + "\n" + template
        }
    }

    private func enqueueCurrentInputForLater() {
        let payload = voiceService.audioPayload()
        OfflineQueueService.shared.enqueue(
            images: capturedImages,
            audioBase64: payload?.base64,
            audioMimeType: payload?.mimeType,
            voiceTranscript: voiceService.transcript.isEmpty ? nil : voiceService.transcript,
            additionalNotes: additionalNotes.isEmpty ? nil : additionalNotes,
            customerName: customerName.isEmpty ? nil : customerName,
            customerPhone: customerPhone.isEmpty ? nil : customerPhone,
            customerEmail: customerEmail.isEmpty ? nil : customerEmail,
            customerAddress: customerAddress.isEmpty ? nil : customerAddress
        )
    }

    private func processQueuedQuotesIfNeeded() async {
        guard !isAnalyzing else { return }
        let queued = OfflineQueueService.shared.drain()
        guard !queued.isEmpty else {
            queuedQuoteCount = 0
            return
        }

        var failed: [OfflineQueueService.QueuedQuoteInput] = []

        for item in queued {
            let images = item.imagesBase64.compactMap { Data(base64Encoded: $0) }.compactMap { UIImage(data: $0) }
            if images.isEmpty {
                continue
            }
            let result = await aiService.analyzeAndQuote(
                images: images,
                audioBase64: item.audioBase64,
                audioMimeType: item.audioMimeType,
                voiceTranscript: item.voiceTranscript,
                additionalNotes: item.additionalNotes,
                customerName: item.customerName,
                customerPhone: item.customerPhone,
                customerEmail: item.customerEmail,
                customerAddress: item.customerAddress,
                allowOverride: true
            )
            if result == nil {
                failed.append(item)
            } else if quoteResult == nil {
                quoteResult = result
                showQuoteResult = true
            }
        }

        if !failed.isEmpty {
            OfflineQueueService.shared.putBack(failed)
        }
        queuedQuoteCount = OfflineQueueService.shared.pendingCount()
    }
}
