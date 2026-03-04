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

    private func userFacingErrorMessage(edgeError: EdgeError) -> String {
        let normalized = edgeError.error.lowercased()
        if edgeError.code == "claude_timeout" || edgeError.code == "whisper_timeout" || edgeError.code == "upstream_timeout" {
            return "The AI service is taking too long. Please try again."
        }
        if edgeError.code == "claude_truncated_json" {
            return "The AI returned an incomplete result. Please try again."
        }
        if edgeError.code == "upstream_failure" || normalized.contains("unexpected end of json input") {
            return "The AI service had an upstream failure. Please try again."
        }
        return edgeError.error
    }

    private func userFacingErrorMessage(from error: Error) -> String {
        let nsError = error as NSError
        let localized = nsError.localizedDescription.lowercased()
        let errorCode = nsError.userInfo["error_code"] as? String

        if errorCode == "claude_timeout" || errorCode == "whisper_timeout" || errorCode == "upstream_timeout" {
            return "The AI service is taking too long. Please try again."
        }

        if errorCode == "claude_truncated_json"
            || localized.contains("unexpected end of json input")
        {
            return "The AI returned an incomplete result. Please try again."
        }

        if errorCode == "upstream_failure"
            || localized.contains("ended prematurely")
            || localized.contains("truncated json")
        {
            return "The AI service had an upstream failure. Please try again."
        }

        if localized.contains("empty response") {
            return "The server returned an empty response. Please retry."
        }

        return "Quote analysis failed: \(nsError.localizedDescription)"
    }

    func analyzeAndQuote(
        images: [UIImage],
        audioBase64: String?,
        audioMimeType: String?,
        voiceTranscript: String?,
        additionalNotes: String?,
        customerName: String?,
        customerPhone: String?,
        customerEmail: String?,
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
            let audioBase64: String?
            let audioMimeType: String?
            let voiceTranscript: String?
            let additionalNotes: String?
            let customerName: String?
            let customerPhone: String?
            let customerEmail: String?
            let customerAddress: String?
            let allowOverride: Bool?
        }

        let request = AnalyzeIssueRequest(
            images: encodedImages,
            audioBase64: audioBase64,
            audioMimeType: audioMimeType,
            voiceTranscript: voiceTranscript,
            additionalNotes: additionalNotes,
            customerName: customerName,
            customerPhone: customerPhone,
            customerEmail: customerEmail,
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
            urlRequest.timeoutInterval = 120
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
                            NSLocalizedDescriptionKey: userFacingErrorMessage(edgeError: edgeError),
                            "raw_error": edgeError.error,
                            "error_code": edgeError.code ?? "unknown_error"
                        ]
                    )
                }
                let serverMessage = data.isEmpty
                    ? "Server returned an empty response."
                    : (String(data: data, encoding: .utf8) ?? "Server error")
                throw NSError(domain: "AIQuoteService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: serverMessage])
            }
            guard !data.isEmpty else {
                throw NSError(
                    domain: "AIQuoteService",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "Server returned an empty response."]
                )
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
            let message = userFacingErrorMessage(from: error)
            ErrorLogger.log(
                message: "Quote analysis failed: \(error.localizedDescription)",
                context: ["source": "AIQuoteService", "user_message": message]
            )
            await MainActor.run {
                self.error = message
            }
            return nil
        }
    }
}
