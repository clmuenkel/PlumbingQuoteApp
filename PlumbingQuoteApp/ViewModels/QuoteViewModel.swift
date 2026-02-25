import Foundation
import UIKit
import SwiftUI

// MARK: - Main ViewModel
@MainActor
class QuoteViewModel: ObservableObject {
    // Input state
    @Published var capturedImages: [UIImage] = []
    @Published var voiceService = VoiceService()
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

    private let aiService = AIQuoteService()
    private var analysisTask: Task<Void, Never>?

    var isConnected: Bool {
        NetworkMonitor.shared.isConnected
    }

    var canSubmit: Bool {
        !capturedImages.isEmpty || voiceService.hasTranscript
    }

    func clearInputs() {
        capturedImages.removeAll()
        voiceService.transcript = ""
        additionalNotes = ""
        customerName = ""
        customerPhone = ""
        customerAddress = ""
        quoteResult = nil
        showQuoteResult = false
        error = nil
    }

    func startGenerateQuote() {
        guard analysisTask == nil else { return }
        guard isConnected else {
            error = "No internet connection. Reconnect and tap Retry."
            HapticsService.error()
            return
        }
        analysisTask = Task { [weak self] in
            guard let self else { return }
            await self.generateQuote()
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
        error = "Quote generation was cancelled."
        HapticsService.error()
    }

    private func generateQuote() async {
        guard canSubmit else {
            error = "Please add photos or record a voice description."
            return
        }

        isAnalyzing = true
        error = nil

        let result = await aiService.analyzeAndQuote(
            images: capturedImages,
            voiceTranscript: voiceService.transcript.isEmpty ? nil : voiceService.transcript,
            additionalNotes: additionalNotes.isEmpty ? nil : additionalNotes,
            customerName: customerName.isEmpty ? nil : customerName,
            customerPhone: customerPhone.isEmpty ? nil : customerPhone,
            customerAddress: customerAddress.isEmpty ? nil : customerAddress
        )

        isAnalyzing = false

        if Task.isCancelled {
            error = "Quote generation was cancelled."
            HapticsService.error()
            return
        }

        if let result = result {
            quoteResult = result
            showQuoteResult = true
            HapticsService.quoteGenerated()
        } else {
            error = aiService.error ?? "Failed to generate quote. Please try again."
            HapticsService.error()
        }
    }
}
