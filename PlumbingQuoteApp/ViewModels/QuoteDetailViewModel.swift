import Foundation
import Supabase
import UIKit

@MainActor
final class QuoteDetailViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var error: String?
    @Published var quoteResult: QuoteResult?
    @Published var estimateStatus: EstimateStatus = .draft
    @Published var images: [UIImage] = []
    @Published var selectedTier: QuoteTier = .better

    private let supabase = SupabaseService.shared.client

    func updateQuote(_ quote: Quote, for tier: QuoteTier) {
        guard var current = quoteResult else { return }
        switch tier {
        case .good:
            current.good = quote
        case .better:
            current.better = quote
        case .best:
            current.best = quote
        }
        quoteResult = current
    }

    func load(estimateId: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let session = try await supabase.auth.session
            let rows: [EstimateDetailRow] = try await supabase
                .from("Estimate")
                .select("""
                    id,
                    estimateNumber,
                    status,
                    aiDiagnosisNote,
                    voiceTranscript,
                    customerNote,
                    internalNote,
                    createdAt,
                    Customer(firstName,lastName),
                    EstimateOption(
                        id,
                        tier,
                        description,
                        total,
                        recommended,
                        LineItem(id,name,description,unitPrice,quantity,total,sortOrder)
                    )
                """)
                .eq("id", value: estimateId)
                .limit(1)
                .execute()
                .value

            guard let row = rows.first else {
                throw NSError(
                    domain: "QuoteDetailViewModel",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: "Quote was not found."]
                )
            }

            let mapped = mapEstimateToQuoteResult(row)
            quoteResult = mapped
            estimateStatus = EstimateStatus(rawValue: row.status) ?? .draft
            images = await fetchEstimateImages(
                accessToken: session.accessToken,
                authUserId: session.user.id.uuidString.lowercased(),
                estimateId: estimateId
            )
        } catch {
            ErrorLogger.log(
                message: "Quote detail load failed: \(error.localizedDescription)",
                context: ["source": "QuoteDetailViewModel.load"]
            )
            self.error = "Unable to load quote details right now."
        }
    }

    private func mapEstimateToQuoteResult(_ row: EstimateDetailRow) -> QuoteResult {
        let options = row.options
        let fallback = options.first
        let goodQuote = makeQuote(from: option(for: "good", in: options) ?? fallback, tierName: "Good")
        let betterQuote = makeQuote(from: option(for: "better", in: options) ?? fallback, tierName: "Better")
        let bestQuote = makeQuote(from: option(for: "best", in: options) ?? fallback, tierName: "Best")

        let customerName = [row.customer?.firstName, row.customer?.lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return QuoteResult(
            remoteId: row.id,
            estimateNumber: row.estimateNumber,
            issue: PlumbingIssue(
                category: "Estimate",
                subcategory: row.aiDiagnosisNote ?? "Plumbing Service",
                description: row.customerNote ?? row.aiDiagnosisNote ?? "Saved estimate",
                severity: .moderate,
                confidence: 0.8,
                recommendedSolutions: [:]
            ),
            good: goodQuote,
            better: betterQuote,
            best: bestQuote,
            createdAt: row.createdAtDate,
            voiceTranscript: row.voiceTranscript,
            customerName: customerName.isEmpty ? nil : customerName,
            customerPhone: nil,
            customerAddress: nil,
            failedUploads: []
        )
    }

    private func option(for tier: String, in options: [EstimateOptionDetailRow]) -> EstimateOptionDetailRow? {
        options.first { $0.tier.caseInsensitiveCompare(tier) == .orderedSame }
    }

    private func makeQuote(from option: EstimateOptionDetailRow?, tierName: String) -> Quote {
        guard let option else {
            return Quote(
                optionId: nil,
                tier: tierName,
                lineItems: [],
                laborHours: 0,
                laborRate: 0,
                laborTotal: 0,
                partsTotal: 0,
                tax: 0,
                total: 0,
                priceBookPrice: nil,
                marketAverage: nil,
                marketRange: nil,
                confidenceScore: nil,
                reasoning: nil,
                validationFlags: nil,
                marketPositionPercent: nil,
                warrantyMonths: 0,
                solutionDescription: "No details available",
                notes: ""
            )
        }

        let sortedLines = option.lineItems.sorted { $0.sortOrder < $1.sortOrder }
        let laborLine = sortedLines.first(where: \.isLabor)
        let partsLines = sortedLines.filter { !$0.isLabor }

        let lineItems = sortedLines.map { line in
            QuoteLineItem(
                id: line.id,
                partName: line.name,
                partNumber: "",
                brand: line.description ?? "",
                unitPrice: line.unitPrice,
                quantity: line.quantity,
                category: line.isLabor ? "labor" : "part"
            )
        }

        let partsTotal = partsLines.reduce(0) { $0 + $1.total }
        let laborTotal = laborLine?.total ?? 0
        let total = option.total
        let tax = max(0, total - (partsTotal + laborTotal))
        let laborRate = laborLine?.unitPrice ?? 0
        let laborHours = laborLine?.quantity ?? 0

        return Quote(
            optionId: option.id,
            tier: tierName,
            lineItems: lineItems,
            laborHours: laborHours,
            laborRate: laborRate,
            laborTotal: laborTotal,
            partsTotal: partsTotal,
            tax: tax,
            total: total,
            priceBookPrice: nil,
            marketAverage: nil,
            marketRange: nil,
            confidenceScore: nil,
            reasoning: nil,
            validationFlags: nil,
            marketPositionPercent: nil,
            warrantyMonths: tierName == "Good" ? 3 : (tierName == "Better" ? 12 : 24),
            solutionDescription: option.description ?? "Scope not provided",
            notes: ""
        )
    }

    private func fetchEstimateImages(accessToken: String, authUserId: String, estimateId: String) async -> [UIImage] {
        var loaded: [UIImage] = []
        var misses = 0

        for index in 1...5 {
            guard let url = URL(string: "\(AppConfig.supabaseURL)/storage/v1/object/authenticated/quote-images/\(authUserId)/\(estimateId)/\(index).jpg") else {
                continue
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200...299).contains(status), let image = UIImage(data: data) else {
                    misses += 1
                    if misses >= 2 && !loaded.isEmpty { break }
                    continue
                }
                loaded.append(image)
            } catch {
                misses += 1
                if misses >= 2 && !loaded.isEmpty { break }
            }
        }

        return loaded
    }
}

private struct EstimateDetailRow: Decodable {
    let id: String
    let estimateNumber: Int?
    let status: String
    let aiDiagnosisNote: String?
    let voiceTranscript: String?
    let customerNote: String?
    let internalNote: String?
    let createdAt: String
    let customer: EstimateCustomerRow?
    let options: [EstimateOptionDetailRow]

    var createdAtDate: Date {
        Self.iso8601WithFractions.date(from: createdAt)
            ?? Self.iso8601.date(from: createdAt)
            ?? Date()
    }

    private static let iso8601WithFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    enum CodingKeys: String, CodingKey {
        case id
        case estimateNumber
        case status
        case aiDiagnosisNote
        case voiceTranscript
        case customerNote
        case internalNote
        case createdAt
        case customer = "Customer"
        case options = "EstimateOption"
    }
}

private struct EstimateCustomerRow: Decodable {
    let firstName: String?
    let lastName: String?
}

private struct EstimateOptionDetailRow: Decodable {
    let id: String
    let tier: String
    let description: String?
    let total: Double
    let recommended: Bool
    let lineItems: [EstimateLineItemDetailRow]

    enum CodingKeys: String, CodingKey {
        case id
        case tier
        case description
        case total
        case recommended
        case lineItems = "LineItem"
    }
}

private struct EstimateLineItemDetailRow: Decodable {
    let id: String
    let name: String
    let description: String?
    let unitPrice: Double
    let quantity: Double
    let total: Double
    let sortOrder: Int

    var isLabor: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("labor") == .orderedSame
    }
}
