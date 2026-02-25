import Foundation
import UIKit

struct CompanyInfo {
    let name: String
    let phone: String
    let address: String
    let logo: UIImage?

    static let `default` = CompanyInfo(
        name: "PlumbQuote Services",
        phone: "",
        address: "",
        logo: nil
    )
}

enum PDFQuoteRenderer {
    static func render(
        result: QuoteResult,
        tier: QuoteTier,
        companyInfo: CompanyInfo = .default,
        signature: UIImage? = nil
    ) throws -> (data: Data, url: URL) {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // Letter size at 72 dpi.
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let quote = result.quote(for: tier)

        let data = renderer.pdfData { context in
            context.beginPage()
            let cg = context.cgContext

            var y: CGFloat = 30
            let left: CGFloat = 36
            let right: CGFloat = pageRect.width - 36

            func drawText(_ text: String, font: UIFont, color: UIColor = .label, rect: CGRect) {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color
                ]
                text.draw(in: rect, withAttributes: attrs)
            }

            // Header
            if let logo = companyInfo.logo {
                logo.draw(in: CGRect(x: left, y: y, width: 70, height: 70))
            }
            drawText(companyInfo.name, font: .boldSystemFont(ofSize: 18), rect: CGRect(x: left + 80, y: y, width: 300, height: 24))
            drawText(companyInfo.phone, font: .systemFont(ofSize: 12), color: .secondaryLabel, rect: CGRect(x: left + 80, y: y + 24, width: 300, height: 16))
            drawText(companyInfo.address, font: .systemFont(ofSize: 12), color: .secondaryLabel, rect: CGRect(x: left + 80, y: y + 40, width: 420, height: 16))
            y += 84

            cg.setStrokeColor(UIColor.systemGray4.cgColor)
            cg.stroke(CGRect(x: left, y: y, width: right - left, height: 1))
            y += 12

            let dateText = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
            drawText("Quote #\(result.estimateNumber ?? 0)", font: .boldSystemFont(ofSize: 14), rect: CGRect(x: left, y: y, width: 220, height: 20))
            drawText("Date: \(dateText)", font: .systemFont(ofSize: 12), rect: CGRect(x: right - 180, y: y + 2, width: 180, height: 16))
            y += 24

            if let customerName = result.customerName, !customerName.isEmpty {
                drawText("Customer: \(customerName)", font: .systemFont(ofSize: 12), rect: CGRect(x: left, y: y, width: 300, height: 16))
                y += 16
            }
            if let customerAddress = result.customerAddress, !customerAddress.isEmpty {
                drawText("Address: \(customerAddress)", font: .systemFont(ofSize: 12), rect: CGRect(x: left, y: y, width: 500, height: 16))
                y += 16
            }
            y += 8

            // Diagnosis
            drawText("Diagnosis", font: .boldSystemFont(ofSize: 13), rect: CGRect(x: left, y: y, width: 200, height: 16))
            y += 18
            drawText(result.issue.subcategory, font: .boldSystemFont(ofSize: 12), rect: CGRect(x: left, y: y, width: 400, height: 16))
            y += 16
            drawText(result.issue.description, font: .systemFont(ofSize: 12), color: .secondaryLabel, rect: CGRect(x: left, y: y, width: right - left, height: 32))
            y += 38

            // Option title
            drawText("\(tier.rawValue.uppercased()) OPTION", font: .boldSystemFont(ofSize: 14), rect: CGRect(x: left, y: y, width: 260, height: 18))
            y += 22

            drawText("Item", font: .boldSystemFont(ofSize: 12), rect: CGRect(x: left, y: y, width: 260, height: 16))
            drawText("Qty", font: .boldSystemFont(ofSize: 12), rect: CGRect(x: left + 280, y: y, width: 40, height: 16))
            drawText("Unit", font: .boldSystemFont(ofSize: 12), rect: CGRect(x: left + 340, y: y, width: 90, height: 16))
            drawText("Total", font: .boldSystemFont(ofSize: 12), rect: CGRect(x: right - 90, y: y, width: 90, height: 16))
            y += 18

            for item in quote.lineItems {
                drawText(item.partName, font: .systemFont(ofSize: 11), rect: CGRect(x: left, y: y, width: 260, height: 15))
                drawText(String(format: "%.2f", item.quantity), font: .systemFont(ofSize: 11), rect: CGRect(x: left + 280, y: y, width: 40, height: 15))
                drawText(formatCurrency(item.unitPrice), font: .systemFont(ofSize: 11), rect: CGRect(x: left + 340, y: y, width: 90, height: 15))
                drawText(formatCurrency(item.unitPrice * item.quantity), font: .systemFont(ofSize: 11), rect: CGRect(x: right - 90, y: y, width: 90, height: 15))
                y += 16
                if y > 660 { break }
            }

            y += 10
            drawText("Parts Subtotal", font: .systemFont(ofSize: 12), rect: CGRect(x: right - 180, y: y, width: 100, height: 16))
            drawText(formatCurrency(quote.computedPartsTotal), font: .boldSystemFont(ofSize: 12), rect: CGRect(x: right - 90, y: y, width: 90, height: 16))
            y += 16
            drawText("Labor", font: .systemFont(ofSize: 12), rect: CGRect(x: right - 180, y: y, width: 100, height: 16))
            drawText(formatCurrency(quote.computedLaborTotal), font: .boldSystemFont(ofSize: 12), rect: CGRect(x: right - 90, y: y, width: 90, height: 16))
            y += 16
            drawText("Tax", font: .systemFont(ofSize: 12), rect: CGRect(x: right - 180, y: y, width: 100, height: 16))
            drawText(formatCurrency(quote.computedTax), font: .boldSystemFont(ofSize: 12), rect: CGRect(x: right - 90, y: y, width: 90, height: 16))
            y += 18
            drawText("TOTAL", font: .boldSystemFont(ofSize: 14), rect: CGRect(x: right - 180, y: y, width: 100, height: 18))
            drawText(formatCurrency(quote.computedTotal), font: .boldSystemFont(ofSize: 14), rect: CGRect(x: right - 90, y: y, width: 90, height: 18))
            y += 28

            drawText("Warranty: \(quote.warrantyMonths) months", font: .systemFont(ofSize: 12), rect: CGRect(x: left, y: y, width: 260, height: 16))
            y += 16
            drawText("Scope: \(quote.solutionDescription)", font: .systemFont(ofSize: 11), color: .secondaryLabel, rect: CGRect(x: left, y: y, width: right - left, height: 34))
            y += 42

            drawText("Customer Signature:", font: .systemFont(ofSize: 12), rect: CGRect(x: left, y: y, width: 140, height: 16))
            cg.setStrokeColor(UIColor.systemGray.cgColor)
            cg.stroke(CGRect(x: left + 140, y: y + 12, width: 220, height: 1))
            if let signature {
                signature.draw(in: CGRect(x: left + 150, y: y - 24, width: 180, height: 36))
            }
            y += 26

            drawText("Terms: This quote is valid for 30 days unless otherwise noted.", font: .systemFont(ofSize: 10), color: .secondaryLabel, rect: CGRect(x: left, y: y, width: right - left, height: 14))
        }

        let fileName = "PlumbQuote-\(result.estimateNumber ?? 0)-\(tier.rawValue).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return (data, url)
    }

    private static func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}
