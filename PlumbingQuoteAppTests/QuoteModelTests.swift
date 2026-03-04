import XCTest
@testable import PlumbingQuoteApp

final class QuoteModelTests: XCTestCase {
    func testComputedTotalsUseProvidedValues() {
        let quote = Quote(
            tier: "Better",
            lineItems: [
                QuoteLineItem(partName: "Valve", partNumber: "V-1", brand: "BrandX", unitPrice: 50, quantity: 2, category: "part"),
                QuoteLineItem(partName: "Labor", partNumber: "", brand: "", unitPrice: 100, quantity: 1.5, category: "labor")
            ],
            laborHours: 0,
            laborRate: 0,
            laborTotal: 200,
            partsTotal: 120,
            tax: 9.9,
            total: 329.9,
            warrantyMonths: 12,
            solutionDescription: "Replace valve",
            notes: ""
        )

        XCTAssertEqual(quote.computedPartsTotal, 120, accuracy: 0.001)
        XCTAssertEqual(quote.computedLaborTotal, 200, accuracy: 0.001)
        XCTAssertEqual(quote.computedTax, 9.9, accuracy: 0.001)
        XCTAssertEqual(quote.computedTotal, 329.9, accuracy: 0.001)
    }

    func testComputedTaxFallsBackToCompanyRate() {
        let quote = Quote(
            tier: "Good",
            lineItems: [
                QuoteLineItem(partName: "Cartridge", partNumber: "C-1", brand: "Std", unitPrice: 80, quantity: 1, category: "part")
            ],
            laborHours: 1,
            laborRate: 100,
            laborTotal: nil,
            partsTotal: nil,
            tax: nil,
            total: nil,
            warrantyMonths: 3,
            solutionDescription: "Repair",
            notes: ""
        )

        XCTAssertEqual(quote.computedPartsTotal, 80, accuracy: 0.001)
        XCTAssertEqual(quote.computedLaborTotal, 100, accuracy: 0.001)
        XCTAssertEqual(quote.computedTax, 80 * CompanySettingsService.defaultTaxRate, accuracy: 0.001)
        XCTAssertEqual(quote.computedTotal, quote.computedPartsTotal + quote.computedLaborTotal + quote.computedTax, accuracy: 0.001)
    }
}
