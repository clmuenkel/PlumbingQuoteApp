import Foundation
import Supabase
import UIKit

final class EstimateService {
    static let shared = EstimateService()
    private let supabase = SupabaseService.shared.client

    private init() {}

    struct UpdateStatusRequest: Encodable {
        let estimateId: String
        let status: String
        let selectedOptionId: String?
        let signatureBase64: String?
    }

    struct UpdateStatusResponse: Decodable {
        struct EstimateDTO: Decodable {
            let id: String
            let status: String
        }

        let ok: Bool
        let estimate: EstimateDTO
        let signaturePath: String?
    }

    struct UpdateOptionLineItem: Encodable {
        let id: String?
        let name: String
        let description: String
        let unitPrice: Double
        let quantity: Double
        let unit: String
    }

    struct UpdateOptionPayload: Encodable {
        let optionId: String
        let lineItems: [UpdateOptionLineItem]
        let laborHours: Double
    }

    struct UpdateOptionsRequest: Encodable {
        let estimateId: String
        let options: [UpdateOptionPayload]
    }

    struct UpdateOptionsResponse: Decodable {
        struct UpdatedOption: Decodable {
            let id: String
            let tier: String
            let subtotal: Double
            let laborTotal: Double
            let tax: Double
            let total: Double
            let laborHours: Double
            let laborRate: Double
        }

        let ok: Bool
        let estimateId: String
        let options: [UpdatedOption]
    }

    func updateStatus(
        estimateId: String,
        status: EstimateStatus,
        selectedOptionId: String? = nil,
        signatureImage: UIImage? = nil
    ) async throws -> UpdateStatusResponse {
        do {
            let session = try await supabase.auth.session
            guard let url = URL(string: "\(AppConfig.supabaseURL)/functions/v1/update-estimate") else {
                throw URLError(.badURL)
            }

            let signatureBase64: String?
            if let signatureImage, let data = signatureImage.pngData() {
                signatureBase64 = data.base64EncodedString()
            } else {
                signatureBase64 = nil
            }

            let requestPayload = UpdateStatusRequest(
                estimateId: estimateId,
                status: status.rawValue,
                selectedOptionId: selectedOptionId,
                signatureBase64: signatureBase64
            )

            var request = URLRequest(url: url)
            request.httpMethod = "PATCH"
            request.timeoutInterval = 30
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(requestPayload)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            guard (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "Unknown server error"
                throw NSError(domain: "EstimateService", code: http.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: body
                ])
            }

            return try JSONDecoder().decode(UpdateStatusResponse.self, from: data)
        } catch {
            ErrorLogger.log(
                message: "updateStatus failed: \(error.localizedDescription)",
                context: ["source": "EstimateService.updateStatus", "estimateId": estimateId, "status": status.rawValue]
            )
            throw error
        }
    }

    func updateOptions(estimateId: String, payload: UpdateOptionPayload) async throws -> UpdateOptionsResponse {
        do {
            let session = try await supabase.auth.session
            guard let url = URL(string: "\(AppConfig.supabaseURL)/functions/v1/update-estimate-options") else {
                throw URLError(.badURL)
            }

            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.timeoutInterval = 45
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(
                UpdateOptionsRequest(estimateId: estimateId, options: [payload])
            )

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            guard (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "Unknown server error"
                throw NSError(domain: "EstimateService", code: http.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: body
                ])
            }

            return try JSONDecoder().decode(UpdateOptionsResponse.self, from: data)
        } catch {
            ErrorLogger.log(
                message: "updateOptions failed: \(error.localizedDescription)",
                context: ["source": "EstimateService.updateOptions", "estimateId": estimateId]
            )
            throw error
        }
    }
}
