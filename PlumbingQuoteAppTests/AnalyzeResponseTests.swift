import XCTest
@testable import PlumbingQuoteApp

final class AnalyzeResponseTests: XCTestCase {
    func testAnalyzeResponseDecodesAndMapsQuoteResult() throws {
        let json = """
        {
          "quoteId": "est_123",
          "estimateNumber": 42,
          "customerName": "Alex Johnson",
          "customerPhone": "5551234567",
          "customerEmail": "alex@example.com",
          "customerAddress": "123 Main St",
          "issue": {
            "category": "Fixture",
            "subcategory": "Kitchen Faucet Repair",
            "description": "Dripping faucet",
            "severity": "Moderate",
            "confidence": 0.91,
            "recommendedSolutions": {
              "good": "Repair seals",
              "better": "Replace cartridge",
              "best": "Replace faucet"
            }
          },
          "quotes": {
            "good": {
              "tier": "Good",
              "lineItems": [],
              "laborHours": 1,
              "laborRate": 95,
              "warrantyMonths": 3,
              "solutionDescription": "Good scope",
              "notes": ""
            },
            "better": {
              "tier": "Better",
              "lineItems": [],
              "laborHours": 1.5,
              "laborRate": 95,
              "warrantyMonths": 12,
              "solutionDescription": "Better scope",
              "notes": ""
            },
            "best": {
              "tier": "Best",
              "lineItems": [],
              "laborHours": 2,
              "laborRate": 95,
              "warrantyMonths": 24,
              "solutionDescription": "Best scope",
              "notes": ""
            }
          }
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(AnalyzeResponse.self, from: data)
        let mapped = decoded.toQuoteResult(voiceTranscript: "Tech note")

        XCTAssertEqual(mapped.remoteId, "est_123")
        XCTAssertEqual(mapped.estimateNumber, 42)
        XCTAssertEqual(mapped.customerName, "Alex Johnson")
        XCTAssertEqual(mapped.customerPhone, "5551234567")
        XCTAssertEqual(mapped.customerEmail, "alex@example.com")
        XCTAssertEqual(mapped.customerAddress, "123 Main St")
        XCTAssertEqual(mapped.issue.subcategory, "Kitchen Faucet Repair")
        XCTAssertEqual(mapped.good.tier, "Good")
        XCTAssertEqual(mapped.better.warrantyMonths, 12)
        XCTAssertEqual(mapped.voiceTranscript, "Tech note")
    }
}
