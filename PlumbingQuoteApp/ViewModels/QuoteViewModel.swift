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
    @Published var customerAddress: String = ""

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

    init() {
        voiceServiceCancellable = voiceService.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
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
        customerAddress = ""
        quoteResult = nil
        showQuoteResult = false
        error = nil
        generationStep = ""
    }

    func startGenerateQuote(forceOverride: Bool = false) {
        guard analysisTask == nil else { return }
        guard isConnected else {
            error = "No internet connection. Reconnect and tap Retry."
            ErrorLogger.log(
                message: "Quote generation blocked: device offline",
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
}
