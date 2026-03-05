import Foundation
import UIKit

struct CompanyInfo {
    let name: String
    let phone: String
    let address: String
    let logo: UIImage?
    let terms: String

    static let `default` = CompanyInfo(
        name: "PlumbQuote Services",
        phone: "",
        address: "",
        logo: nil,
        terms: CompanySettingsService.defaultPdfTerms
    )
}

enum PDFQuoteRenderer {
    static func render(
        result: QuoteResult,
        tier: QuoteTier,
        companyInfo: CompanyInfo = .default,
        signature: UIImage? = nil,
        jobPhotos: [UIImage] = []
    ) throws -> (data: Data, url: URL) {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US letter at 72 dpi.
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let quote = result.quote(for: tier)
        let topMargin: CGFloat = 30
        let left: CGFloat = 36
        let right: CGFloat = pageRect.width - 36
        let contentTop: CGFloat = 88
        let contentBottom: CGFloat = pageRect.height - 56

        let data = renderer.pdfData { context in
            let cg = context.cgContext
            var pageNumber = 0
            var y: CGFloat = contentTop

            func drawHeader() {
                cg.setStrokeColor(UIColor.systemGray4.cgColor)
                cg.stroke(CGRect(x: left, y: 72, width: right - left, height: 1))
                if let logo = companyInfo.logo {
                    logo.draw(in: CGRect(x: left, y: topMargin, width: 34, height: 34))
                }
                drawText(
                    companyInfo.name,
                    font: .boldSystemFont(ofSize: 14),
                    rect: CGRect(x: left + 42, y: topMargin + 2, width: 320, height: 18)
                )
                drawText(
                    [companyInfo.phone, companyInfo.address]
                        .filter { !$0.isEmpty }
                        .joined(separator: " • "),
                    font: .systemFont(ofSize: 10),
                    color: .secondaryLabel,
                    rect: CGRect(x: left + 42, y: topMargin + 20, width: right - left - 42, height: 14)
                )
            }

            func drawFooter() {
                cg.setStrokeColor(UIColor.systemGray4.cgColor)
                cg.stroke(CGRect(x: left, y: pageRect.height - 42, width: right - left, height: 1))
                drawText(
                    "Page \(pageNumber)",
                    font: .systemFont(ofSize: 10),
                    color: .secondaryLabel,
                    rect: CGRect(x: right - 70, y: pageRect.height - 34, width: 70, height: 14)
                )
            }

            func beginPage() {
                context.beginPage()
                pageNumber += 1
                y = contentTop
                drawHeader()
            }

            func ensureSpace(_ neededHeight: CGFloat) {
                if y + neededHeight > contentBottom {
                    drawFooter()
                    beginPage()
                }
            }

            @discardableResult
            func drawWrappedText(
                _ text: String,
                font: UIFont,
                color: UIColor = .label,
                width: CGFloat,
                minHeight: CGFloat = 14
            ) -> CGFloat {
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let box = NSString(string: text).boundingRect(
                    with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attrs,
                    context: nil
                )
                let height = max(minHeight, ceil(box.height))
                ensureSpace(height + 2)
                drawText(text, font: font, color: color, rect: CGRect(x: left, y: y, width: width, height: height))
                y += height + 2
                return height
            }

            func drawText(_ text: String, font: UIFont, color: UIColor = .label, rect: CGRect) {
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                text.draw(in: rect, withAttributes: attrs)
            }

            beginPage()

            let dateText = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
            ensureSpace(24)
            drawText("Quote #\(result.estimateNumber ?? 0)", font: .boldSystemFont(ofSize: 14), rect: CGRect(x: left, y: y, width: 220, height: 20))
            drawText("Date: \(dateText)", font: .systemFont(ofSize: 12), rect: CGRect(x: right - 180, y: y + 2, width: 180, height: 16))
            y += 24

            if let customerName = result.customerName, !customerName.isEmpty {
                drawWrappedText("Customer: \(customerName)", font: .systemFont(ofSize: 12), width: right - left)
            }
            if let customerPhone = result.customerPhone, !customerPhone.isEmpty {
                drawWrappedText("Phone: \(customerPhone)", font: .systemFont(ofSize: 12), width: right - left)
            }
            if let customerEmail = result.customerEmail, !customerEmail.isEmpty {
                drawWrappedText("Email: \(customerEmail)", font: .systemFont(ofSize: 12), width: right - left)
            }
            if let customerAddress = result.customerAddress, !customerAddress.isEmpty {
                drawWrappedText("Address: \(customerAddress)", font: .systemFont(ofSize: 12), width: right - left)
            }
            y += 8

            ensureSpace(22)
            drawText("Diagnosis", font: .boldSystemFont(ofSize: 13), rect: CGRect(x: left, y: y, width: 200, height: 16))
            y += 18
            drawWrappedText(result.issue.subcategory, font: .boldSystemFont(ofSize: 12), width: right - left)
            drawWrappedText(result.issue.description, font: .systemFont(ofSize: 12), color: .secondaryLabel, width: right - left)
            y += 6

            ensureSpace(22)
            drawText("\(tier.rawValue.uppercased()) OPTION", font: .boldSystemFont(ofSize: 14), rect: CGRect(x: left, y: y, width: 260, height: 18))
            y += 22

            ensureSpace(18)
            drawText("Item", font: .boldSystemFont(ofSize: 12), rect: CGRect(x: left, y: y, width: 250, height: 16))
            drawText("Qty", font: .boldSystemFont(ofSize: 12), rect: CGRect(x: left + 258, y: y, width: 36, height: 16))
            drawText("Unit", font: .boldSystemFont(ofSize: 12), rect: CGRect(x: left + 304, y: y, width: 90, height: 16))
            drawText("Total", font: .boldSystemFont(ofSize: 12), rect: CGRect(x: right - 90, y: y, width: 90, height: 16))
            y += 18

            for item in quote.lineItems {
                let itemText = item.partName + (item.brand.isEmpty ? "" : " - \(item.brand)")
                let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11)]
                let itemHeight = ceil(NSString(string: itemText).boundingRect(
                    with: CGSize(width: 250, height: CGFloat.greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attrs,
                    context: nil
                ).height)
                let rowHeight = max(15, itemHeight)
                ensureSpace(rowHeight + 4)
                drawText(itemText, font: .systemFont(ofSize: 11), rect: CGRect(x: left, y: y, width: 250, height: rowHeight))
                drawText(String(format: "%.2f", item.quantity), font: .systemFont(ofSize: 11), rect: CGRect(x: left + 258, y: y, width: 36, height: rowHeight))
                drawText(CurrencyFormatter.usd(item.unitPrice), font: .systemFont(ofSize: 11), rect: CGRect(x: left + 304, y: y, width: 90, height: rowHeight))
                drawText(CurrencyFormatter.usd(item.unitPrice * item.quantity), font: .systemFont(ofSize: 11), rect: CGRect(x: right - 90, y: y, width: 90, height: rowHeight))
                y += rowHeight + 2
            }

            y += 10
            ensureSpace(120)
            drawText("Parts Subtotal", font: .systemFont(ofSize: 12), rect: CGRect(x: right - 180, y: y, width: 100, height: 16))
            drawText(CurrencyFormatter.usd(quote.computedPartsTotal), font: .boldSystemFont(ofSize: 12), rect: CGRect(x: right - 90, y: y, width: 90, height: 16))
            y += 16
            drawText("Labor", font: .systemFont(ofSize: 12), rect: CGRect(x: right - 180, y: y, width: 100, height: 16))
            drawText(CurrencyFormatter.usd(quote.computedLaborTotal), font: .boldSystemFont(ofSize: 12), rect: CGRect(x: right - 90, y: y, width: 90, height: 16))
            y += 16
            drawText("Tax", font: .systemFont(ofSize: 12), rect: CGRect(x: right - 180, y: y, width: 100, height: 16))
            drawText(CurrencyFormatter.usd(quote.computedTax), font: .boldSystemFont(ofSize: 12), rect: CGRect(x: right - 90, y: y, width: 90, height: 16))
            y += 18
            drawText("TOTAL", font: .boldSystemFont(ofSize: 14), rect: CGRect(x: right - 180, y: y, width: 100, height: 18))
            drawText(CurrencyFormatter.usd(quote.computedTotal), font: .boldSystemFont(ofSize: 14), rect: CGRect(x: right - 90, y: y, width: 90, height: 18))
            y += 28

            drawWrappedText("Warranty: \(quote.warrantyMonths) months", font: .systemFont(ofSize: 12), width: right - left)
            drawWrappedText("Scope: \(quote.solutionDescription)", font: .systemFont(ofSize: 11), color: .secondaryLabel, width: right - left)
            y += 6

            ensureSpace(76)
            drawText("Customer Signature:", font: .systemFont(ofSize: 12), rect: CGRect(x: left, y: y, width: 140, height: 16))
            cg.setStrokeColor(UIColor.systemGray.cgColor)
            cg.stroke(CGRect(x: left + 140, y: y + 12, width: 220, height: 1))
            if let signature {
                signature.draw(in: CGRect(x: left + 150, y: y - 24, width: 180, height: 36))
            }
            y += 26

            drawWrappedText(
                "Terms: \(companyInfo.terms.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? CompanySettingsService.defaultPdfTerms : companyInfo.terms)",
                font: .systemFont(ofSize: 10),
                color: .secondaryLabel,
                width: right - left,
                minHeight: 14
            )

            if !jobPhotos.isEmpty {
                drawFooter()
                beginPage()
                ensureSpace(20)
                drawText("Job Photos", font: .boldSystemFont(ofSize: 14), rect: CGRect(x: left, y: y, width: 220, height: 18))
                y += 22

                let columns: CGFloat = 2
                let spacing: CGFloat = 14
                let thumbWidth = ((right - left) - spacing) / columns
                let thumbHeight = thumbWidth * 0.68
                var x = left
                var col: CGFloat = 0

                for image in jobPhotos.prefix(6) {
                    ensureSpace(thumbHeight + 28)
                    image.draw(in: CGRect(x: x, y: y, width: thumbWidth, height: thumbHeight))
                    cg.setStrokeColor(UIColor.systemGray4.cgColor)
                    cg.stroke(CGRect(x: x, y: y, width: thumbWidth, height: thumbHeight))
                    drawText("Photo \(Int(col) + 1)", font: .systemFont(ofSize: 10), color: .secondaryLabel, rect: CGRect(x: x, y: y + thumbHeight + 4, width: thumbWidth, height: 14))
                    col += 1
                    if Int(col) % Int(columns) == 0 {
                        x = left
                        y += thumbHeight + 28
                    } else {
                        x += thumbWidth + spacing
                    }
                }
            }

            drawFooter()
        }

        let fileName = "PlumbQuote-\(result.estimateNumber ?? 0)-\(tier.rawValue).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: Data.WritingOptions.atomic)
        return (data, url)
    }

}
