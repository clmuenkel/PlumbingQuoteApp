import Foundation
import SwiftUI

enum QuoteTier: String, CaseIterable, Identifiable {
    case good = "Good"
    case better = "Better"
    case best = "Best"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .good: return AppTheme.success
        case .better: return AppTheme.accent
        case .best: return AppTheme.accentDark
        }
    }
}

enum IssueSeverity: String, Codable {
    case minor = "Minor"
    case moderate = "Moderate"
    case major = "Major"
    case emergency = "Emergency"
}

enum EstimateStatus: String, Codable, CaseIterable {
    case draft
    case sent
    case accepted
    case rejected

    var displayName: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .draft: return AppTheme.muted
        case .sent: return AppTheme.warning
        case .accepted: return AppTheme.success
        case .rejected: return AppTheme.error
        }
    }
}

struct PlumbingIssue: Identifiable, Codable {
    var id: String = UUID().uuidString
    let category: String
    let subcategory: String
    let description: String
    let severity: IssueSeverity
    let confidence: Double
    let recommendedSolutions: [String: String]
}

struct QuoteLineItem: Identifiable, Codable {
    var id: String = UUID().uuidString
    let partName: String
    let partNumber: String
    let brand: String
    let unitPrice: Double
    let quantity: Double
    let category: String

    enum CodingKeys: String, CodingKey {
        case partName
        case partNumber
        case brand
        case unitPrice
        case quantity
        case category
    }

    var isLabor: Bool {
        category.caseInsensitiveCompare("labor") == .orderedSame
            || partName.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("labor") == .orderedSame
    }
}

struct EditableLineItem: Identifiable {
    let id: String
    var name: String
    var description: String
    var unitPrice: Double
    var quantity: Double
    var unit: String

    var lineTotal: Double {
        unitPrice * quantity
    }
}

struct MarketRange: Codable {
    let low: Double
    let high: Double
}

struct Quote: Identifiable, Codable {
    var id: String = UUID().uuidString
    var optionId: String? = nil
    let tier: String
    let lineItems: [QuoteLineItem]
    let laborHours: Double
    let laborRate: Double
    var laborTotal: Double? = nil
    var partsTotal: Double? = nil
    var tax: Double? = nil
    var total: Double? = nil
    var priceBookPrice: Double? = nil
    var marketAverage: Double? = nil
    var marketRange: MarketRange? = nil
    var confidenceScore: Double? = nil
    var reasoning: String? = nil
    var validationFlags: [String]? = nil
    var marketPositionPercent: Double? = nil
    let warrantyMonths: Int
    let solutionDescription: String
    let notes: String

    enum CodingKeys: String, CodingKey {
        case optionId
        case tier
        case lineItems
        case laborHours
        case laborRate
        case laborTotal
        case partsTotal
        case tax
        case total
        case priceBookPrice
        case marketAverage
        case marketRange
        case confidenceScore
        case reasoning
        case validationFlags
        case marketPositionPercent
        case warrantyMonths
        case solutionDescription
        case notes
    }

    var computedPartsTotal: Double {
        partsTotal ?? lineItems
            .filter { !$0.isLabor }
            .reduce(0) { $0 + ($1.unitPrice * $1.quantity) }
    }

    var computedLaborTotal: Double {
        if let laborTotal {
            return laborTotal
        }

        let hoursBasedLabor = laborHours * laborRate
        if hoursBasedLabor > 0 {
            return hoursBasedLabor
        }

        return lineItems
            .filter(\.isLabor)
            .reduce(0) { $0 + ($1.unitPrice * $1.quantity) }
    }

    var computedTax: Double {
        if let tax {
            return tax
        }
        return computedPartsTotal * CompanySettingsService.defaultTaxRate
    }

    var computedTotal: Double {
        total ?? (computedPartsTotal + computedLaborTotal + computedTax)
    }
}

struct QuoteResult: Identifiable {
    let id: String
    let remoteId: String?
    let estimateNumber: Int?
    let issue: PlumbingIssue
    var good: Quote
    var better: Quote
    var best: Quote
    let createdAt: Date
    let voiceTranscript: String?
    let customerName: String?
    let customerPhone: String?
    let customerEmail: String?
    let customerAddress: String?
    let failedUploads: [String]

    init(
        id: String = UUID().uuidString,
        remoteId: String? = nil,
        estimateNumber: Int? = nil,
        issue: PlumbingIssue,
        good: Quote,
        better: Quote,
        best: Quote,
        createdAt: Date = Date(),
        voiceTranscript: String? = nil,
        customerName: String? = nil,
        customerPhone: String? = nil,
        customerEmail: String? = nil,
        customerAddress: String? = nil,
        failedUploads: [String] = []
    ) {
        self.id = id
        self.remoteId = remoteId
        self.estimateNumber = estimateNumber
        self.issue = issue
        self.good = good
        self.better = better
        self.best = best
        self.createdAt = createdAt
        self.voiceTranscript = voiceTranscript
        self.customerName = customerName
        self.customerPhone = customerPhone
        self.customerEmail = customerEmail
        self.customerAddress = customerAddress
        self.failedUploads = failedUploads
    }

    func quote(for tier: QuoteTier) -> Quote {
        switch tier {
        case .good: return good
        case .better: return better
        case .best: return best
        }
    }

    mutating func updateQuote(_ quote: Quote, for tier: QuoteTier) {
        switch tier {
        case .good:
            good = quote
        case .better:
            better = quote
        case .best:
            best = quote
        }
    }
}

struct Technician: Identifiable, Codable {
    let id: String
    let authId: String
    let fullName: String
    let email: String
    let role: String
    let isActive: Bool
}

struct QuoteHistoryItem: Identifiable, Codable {
    let id: String
    let category: String
    let subcategory: String
    let selectedTier: String?
    let status: EstimateStatus
    let createdAt: Date
    let total: Double
    let customerName: String?
}

struct AnalyzeResponse: Decodable {
    struct IssuePayload: Decodable {
        let category: String
        let subcategory: String
        let description: String
        let severity: String
        let confidence: Double
        let recommendedSolutions: [String: String]?
    }

    struct QuotesPayload: Decodable {
        let good: Quote
        let better: Quote
        let best: Quote
    }

    let gateStatus: String?
    let gateReasons: [String]?
    let canOverride: Bool?
    let quoteId: String
    let estimateNumber: Int?
    let customerName: String?
    let customerPhone: String?
    let customerEmail: String?
    let customerAddress: String?
    let failedUploads: [String]?
    let issue: IssuePayload
    let quotes: QuotesPayload

    func toQuoteResult(voiceTranscript: String?) -> QuoteResult {
        QuoteResult(
            remoteId: quoteId,
            estimateNumber: estimateNumber,
            issue: PlumbingIssue(
                category: issue.category,
                subcategory: issue.subcategory,
                description: issue.description,
                severity: IssueSeverity(rawValue: issue.severity) ?? .moderate,
                confidence: issue.confidence,
                recommendedSolutions: issue.recommendedSolutions ?? [:]
            ),
            good: quotes.good,
            better: quotes.better,
            best: quotes.best,
            voiceTranscript: voiceTranscript,
            customerName: customerName,
            customerPhone: customerPhone,
            customerEmail: customerEmail,
            customerAddress: customerAddress,
            failedUploads: failedUploads ?? []
        )
    }
}
