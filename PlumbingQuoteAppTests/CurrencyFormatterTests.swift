import XCTest
@testable import PlumbingQuoteApp

final class CurrencyFormatterTests: XCTestCase {
    func testUsdFormatting() {
        XCTAssertEqual(CurrencyFormatter.usd(0), "$0.00")
        XCTAssertEqual(CurrencyFormatter.usd(1234.5), "$1,234.50")
    }
}
