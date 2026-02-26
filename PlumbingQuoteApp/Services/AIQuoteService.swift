import Foundation
import UIKit
import Supabase

// MARK: - AI Quote Service
// This service sends the image + voice transcript to an AI (OpenAI GPT-4 Vision or Claude)
// which identifies the plumbing issue, then matches it against the local pricing database
// to generate Good/Better/Best quotes.

final class AIQuoteService: ObservableObject {
    @Published var isAnalyzing = false
    @Published var error: String?

    private let supabase = SupabaseService.shared.client

    private struct EdgeError: Decodable {
        let error: String
        let code: String?
        let gateStatus: String?
        let gateReasons: [String]?
        let canOverride: Bool?
    }

    struct GatingFeedback {
        let status: String
        let reasons: [String]
        let canOverride: Bool
    }

    @Published var lastGatingFeedback: GatingFeedback?

    func analyzeAndQuote(
        images: [UIImage],
        voiceTranscript: String?,
        additionalNotes: String?,
        customerName: String?,
        customerPhone: String?,
        customerAddress: String?,
        allowOverride: Bool = false
    ) async -> QuoteResult? {
        await MainActor.run {
            isAnalyzing = true
            error = nil
            lastGatingFeedback = nil
        }

        defer {
            Task { @MainActor in
                self.isAnalyzing = false
            }
        }

        let encodedImages = images.compactMap { image -> String? in
            guard let data = image.compressed() else { return nil }
            return data.base64EncodedString()
        }

        guard !encodedImages.isEmpty else {
            await MainActor.run {
                error = "Please add at least one image."
            }
            return nil
        }

        struct AnalyzeIssueRequest: Encodable {
            let images: [String]
            let voiceTranscript: String?
            let additionalNotes: String?
            let customerName: String?
            let customerPhone: String?
            let customerAddress: String?
            let allowOverride: Bool?
        }

        let request = AnalyzeIssueRequest(
            images: encodedImages,
            voiceTranscript: voiceTranscript,
            additionalNotes: additionalNotes,
            customerName: customerName,
            customerPhone: customerPhone,
            customerAddress: customerAddress,
            allowOverride: allowOverride ? true : nil
        )

        do {
            let session = try await supabase.auth.session
            guard let url = URL(string: "\(AppConfig.supabaseURL)/functions/v1/analyze-issue") else {
                throw URLError(.badURL)
            }
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.timeoutInterval = 60
            urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.addValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            urlRequest.httpBody = try JSONEncoder().encode(request)

            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            guard (200...299).contains(http.statusCode) else {
                if let edgeError = try? JSONDecoder().decode(EdgeError.self, from: data) {
                    if let gateStatus = edgeError.gateStatus {
                        await MainActor.run {
                            self.lastGatingFeedback = GatingFeedback(
                                status: gateStatus,
                                reasons: edgeError.gateReasons ?? [],
                                canOverride: edgeError.canOverride ?? false
                            )
                        }
                    }
                    throw NSError(
                        domain: "AIQuoteService",
                        code: http.statusCode,
                        userInfo: [
                            NSLocalizedDescriptionKey: edgeError.error,
                            "error_code": edgeError.code ?? "unknown_error"
                        ]
                    )
                }
                let serverMessage = String(data: data, encoding: .utf8) ?? "Server error"
                throw NSError(domain: "AIQuoteService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: serverMessage])
            }
            let decoded = try JSONDecoder().decode(AnalyzeResponse.self, from: data)
            if let status = decoded.gateStatus {
                await MainActor.run {
                    self.lastGatingFeedback = GatingFeedback(
                        status: status,
                        reasons: decoded.gateReasons ?? [],
                        canOverride: decoded.canOverride ?? false
                    )
                }
            }
            return decoded.toQuoteResult(voiceTranscript: voiceTranscript)
        } catch is CancellationError {
            await MainActor.run {
                self.error = "Quote generation was cancelled."
            }
            return nil
        } catch let urlError as URLError where urlError.code == .notConnectedToInternet {
            ErrorLogger.log(
                message: "Network disconnected during quote generation",
                severity: "warning",
                context: ["source": "AIQuoteService", "code": "\(urlError.code.rawValue)"]
            )
            await MainActor.run {
                self.error = "No internet connection. Please reconnect and retry."
            }
            return nil
        } catch {
            ErrorLogger.log(
                message: "Quote analysis failed: \(error.localizedDescription)",
                context: ["source": "AIQuoteService"]
            )
            await MainActor.run {
                self.error = "Quote analysis failed: \(error.localizedDescription)"
            }
            return nil
        }
    }
}
