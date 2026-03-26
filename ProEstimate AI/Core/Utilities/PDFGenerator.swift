import UIKit

/// Centralized PDF generation for estimates, invoices, and proposals.
/// Uses UIGraphicsPDFRenderer to produce US Letter-sized PDF documents
/// saved to the temporary directory for sharing.
enum PDFGenerator {

    // MARK: - Estimate PDF

    static func generateEstimatePDF(
        companyName: String,
        estimateNumber: String,
        date: Date,
        status: String,
        lineItems: [(name: String, qty: Decimal, unit: String, unitCost: Decimal, total: Decimal)],
        subtotalMaterials: Decimal,
        subtotalLabor: Decimal,
        subtotalOther: Decimal,
        taxAmount: Decimal,
        discountAmount: Decimal,
        totalAmount: Decimal,
        notes: String?
    ) -> URL? {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let fmt = Self.makeDateFormatter()
        let cur = Self.makeCurrencyFormatter()

        let data = renderer.pdfData { context in
            context.beginPage()

            let titleFont = UIFont.boldSystemFont(ofSize: 24)
            let headerFont = UIFont.boldSystemFont(ofSize: 14)
            let bodyFont = UIFont.systemFont(ofSize: 11)
            let boldBodyFont = UIFont.boldSystemFont(ofSize: 11)

            var y: CGFloat = 40
            let margin: CGFloat = 50
            let pageWidth = pageRect.width - margin * 2

            // Company name
            companyName.draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: titleFont])
            y += 36

            // Estimate number and date
            "Estimate \(estimateNumber)".draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: headerFont])
            y += 20

            "Date: \(fmt.string(from: date))".draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: bodyFont])
            y += 16
            "Status: \(status)".draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: bodyFont])
            y += 30

            // Separator
            drawHorizontalLine(at: y, from: margin, width: pageWidth)
            y += 8

            // Column headers
            "Item".draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: boldBodyFont])
            "Qty".draw(at: CGPoint(x: margin + 280, y: y), withAttributes: [.font: boldBodyFont])
            "Rate".draw(at: CGPoint(x: margin + 350, y: y), withAttributes: [.font: boldBodyFont])
            "Total".draw(at: CGPoint(x: margin + 440, y: y), withAttributes: [.font: boldBodyFont])
            y += 18

            // Line items
            for item in lineItems {
                if y > pageRect.height - 120 {
                    context.beginPage()
                    y = 40
                }

                item.name.draw(
                    in: CGRect(x: margin, y: y, width: 270, height: 30),
                    withAttributes: [.font: bodyFont]
                )
                "\(item.qty) \(item.unit)".draw(at: CGPoint(x: margin + 280, y: y), withAttributes: [.font: bodyFont])
                (cur.string(from: item.unitCost as NSDecimalNumber) ?? "").draw(
                    at: CGPoint(x: margin + 350, y: y), withAttributes: [.font: bodyFont]
                )
                (cur.string(from: item.total as NSDecimalNumber) ?? "").draw(
                    at: CGPoint(x: margin + 440, y: y), withAttributes: [.font: bodyFont]
                )
                y += 18
            }

            y += 10
            drawHorizontalLine(at: y, from: margin + 350, width: pageWidth - 350)
            y += 8

            // Totals
            func drawTotalLine(_ label: String, _ amount: Decimal, bold: Bool = false) {
                let attrs: [NSAttributedString.Key: Any] = [.font: bold ? boldBodyFont : bodyFont]
                label.draw(at: CGPoint(x: margin + 350, y: y), withAttributes: attrs)
                (cur.string(from: amount as NSDecimalNumber) ?? "").draw(
                    at: CGPoint(x: margin + 440, y: y), withAttributes: attrs
                )
                y += 16
            }

            drawTotalLine("Materials:", subtotalMaterials)
            drawTotalLine("Labor:", subtotalLabor)
            drawTotalLine("Other:", subtotalOther)
            drawTotalLine("Tax:", taxAmount)
            if discountAmount > 0 {
                drawTotalLine("Discount:", -discountAmount)
            }
            y += 4
            drawTotalLine("TOTAL:", totalAmount, bold: true)
            y += 20

            // Notes
            if let notes, !notes.isEmpty {
                if y > pageRect.height - 100 {
                    context.beginPage()
                    y = 40
                }
                "Notes:".draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: boldBodyFont])
                y += 18
                notes.draw(
                    in: CGRect(x: margin, y: y, width: pageWidth, height: 100),
                    withAttributes: [.font: bodyFont]
                )
            }
        }

        return writeToTemp(data: data, filename: "\(estimateNumber).pdf")
    }

    // MARK: - Invoice PDF

    static func generateInvoicePDF(
        companyName: String,
        invoiceNumber: String,
        date: Date,
        dueDate: Date?,
        status: String,
        clientName: String?,
        lineItems: [(name: String, qty: Decimal, unit: String, unitCost: Decimal, total: Decimal)],
        subtotal: Decimal,
        taxAmount: Decimal,
        totalAmount: Decimal,
        amountPaid: Decimal,
        amountDue: Decimal,
        notes: String?
    ) -> URL? {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let fmt = Self.makeDateFormatter()
        let cur = Self.makeCurrencyFormatter()

        let data = renderer.pdfData { context in
            context.beginPage()

            let titleFont = UIFont.boldSystemFont(ofSize: 24)
            let headerFont = UIFont.boldSystemFont(ofSize: 14)
            let bodyFont = UIFont.systemFont(ofSize: 11)
            let boldBodyFont = UIFont.boldSystemFont(ofSize: 11)

            var y: CGFloat = 40
            let margin: CGFloat = 50
            let pageWidth = pageRect.width - margin * 2

            // Company name
            companyName.draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: titleFont])
            y += 36

            // Invoice header
            "Invoice \(invoiceNumber)".draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: headerFont])
            y += 20

            "Date: \(fmt.string(from: date))".draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: bodyFont])
            y += 16
            if let dueDate {
                "Due: \(fmt.string(from: dueDate))".draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: bodyFont])
                y += 16
            }
            "Status: \(status)".draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: bodyFont])
            y += 16
            if let clientName {
                "Bill To: \(clientName)".draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: bodyFont])
                y += 16
            }
            y += 14

            // Column headers
            drawHorizontalLine(at: y, from: margin, width: pageWidth)
            y += 8
            "Item".draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: boldBodyFont])
            "Qty".draw(at: CGPoint(x: margin + 280, y: y), withAttributes: [.font: boldBodyFont])
            "Rate".draw(at: CGPoint(x: margin + 350, y: y), withAttributes: [.font: boldBodyFont])
            "Total".draw(at: CGPoint(x: margin + 440, y: y), withAttributes: [.font: boldBodyFont])
            y += 18

            // Line items
            for item in lineItems {
                if y > pageRect.height - 120 {
                    context.beginPage()
                    y = 40
                }
                item.name.draw(
                    in: CGRect(x: margin, y: y, width: 270, height: 30),
                    withAttributes: [.font: bodyFont]
                )
                "\(item.qty) \(item.unit)".draw(at: CGPoint(x: margin + 280, y: y), withAttributes: [.font: bodyFont])
                (cur.string(from: item.unitCost as NSDecimalNumber) ?? "").draw(
                    at: CGPoint(x: margin + 350, y: y), withAttributes: [.font: bodyFont]
                )
                (cur.string(from: item.total as NSDecimalNumber) ?? "").draw(
                    at: CGPoint(x: margin + 440, y: y), withAttributes: [.font: bodyFont]
                )
                y += 18
            }

            y += 10
            drawHorizontalLine(at: y, from: margin + 350, width: pageWidth - 350)
            y += 8

            // Totals
            func drawLine(_ label: String, _ amount: Decimal, bold: Bool = false) {
                let attrs: [NSAttributedString.Key: Any] = [.font: bold ? boldBodyFont : bodyFont]
                label.draw(at: CGPoint(x: margin + 350, y: y), withAttributes: attrs)
                (cur.string(from: amount as NSDecimalNumber) ?? "").draw(
                    at: CGPoint(x: margin + 440, y: y), withAttributes: attrs
                )
                y += 16
            }

            drawLine("Subtotal:", subtotal)
            drawLine("Tax:", taxAmount)
            drawLine("TOTAL:", totalAmount, bold: true)
            drawLine("Paid:", amountPaid)
            drawLine("AMOUNT DUE:", amountDue, bold: true)
            y += 20

            // Notes
            if let notes, !notes.isEmpty {
                if y > pageRect.height - 100 {
                    context.beginPage()
                    y = 40
                }
                "Notes:".draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: boldBodyFont])
                y += 18
                notes.draw(
                    in: CGRect(x: margin, y: y, width: pageWidth, height: 100),
                    withAttributes: [.font: bodyFont]
                )
            }
        }

        return writeToTemp(data: data, filename: "\(invoiceNumber).pdf")
    }

    // MARK: - Proposal PDF

    static func generateProposalPDF(
        companyName: String,
        projectTitle: String,
        clientName: String?,
        proposalDate: Date,
        expiresAt: Date?,
        clientMessage: String?,
        lineItems: [(name: String, qty: Decimal, unit: String, unitCost: Decimal, total: Decimal)],
        subtotalMaterials: Decimal,
        subtotalLabor: Decimal,
        subtotalOther: Decimal,
        taxAmount: Decimal,
        totalAmount: Decimal,
        termsAndConditions: String?
    ) -> URL? {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let fmt = Self.makeDateFormatter()
        let cur = Self.makeCurrencyFormatter()

        let data = renderer.pdfData { context in
            context.beginPage()

            let titleFont = UIFont.boldSystemFont(ofSize: 24)
            let headerFont = UIFont.boldSystemFont(ofSize: 14)
            let bodyFont = UIFont.systemFont(ofSize: 11)
            let boldBodyFont = UIFont.boldSystemFont(ofSize: 11)
            let subtitleFont = UIFont.systemFont(ofSize: 9)

            var y: CGFloat = 40
            let margin: CGFloat = 50
            let pageWidth = pageRect.width - margin * 2

            // Company name
            companyName.draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: titleFont])
            y += 36

            // "PROPOSAL" label
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: subtitleFont,
                .foregroundColor: UIColor.gray,
                .kern: 4.0 as NSNumber
            ]
            "PROPOSAL".draw(at: CGPoint(x: margin, y: y), withAttributes: labelAttrs)
            y += 20

            // Project title
            projectTitle.draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: headerFont])
            y += 20

            // Date and client
            "Date: \(fmt.string(from: proposalDate))".draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: bodyFont])
            y += 16
            if let expiresAt {
                "Expires: \(fmt.string(from: expiresAt))".draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: bodyFont])
                y += 16
            }
            if let clientName {
                "Prepared For: \(clientName)".draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: bodyFont])
                y += 16
            }
            y += 10

            // Client message
            if let clientMessage, !clientMessage.isEmpty {
                "Message:".draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: boldBodyFont])
                y += 16
                clientMessage.draw(
                    in: CGRect(x: margin, y: y, width: pageWidth, height: 60),
                    withAttributes: [.font: bodyFont]
                )
                y += 64
            }

            // Line items header
            drawHorizontalLine(at: y, from: margin, width: pageWidth)
            y += 8
            "Item".draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: boldBodyFont])
            "Qty".draw(at: CGPoint(x: margin + 280, y: y), withAttributes: [.font: boldBodyFont])
            "Rate".draw(at: CGPoint(x: margin + 350, y: y), withAttributes: [.font: boldBodyFont])
            "Total".draw(at: CGPoint(x: margin + 440, y: y), withAttributes: [.font: boldBodyFont])
            y += 18

            // Line items
            for item in lineItems {
                if y > pageRect.height - 140 {
                    context.beginPage()
                    y = 40
                }
                item.name.draw(
                    in: CGRect(x: margin, y: y, width: 270, height: 30),
                    withAttributes: [.font: bodyFont]
                )
                "\(item.qty) \(item.unit)".draw(at: CGPoint(x: margin + 280, y: y), withAttributes: [.font: bodyFont])
                (cur.string(from: item.unitCost as NSDecimalNumber) ?? "").draw(
                    at: CGPoint(x: margin + 350, y: y), withAttributes: [.font: bodyFont]
                )
                (cur.string(from: item.total as NSDecimalNumber) ?? "").draw(
                    at: CGPoint(x: margin + 440, y: y), withAttributes: [.font: bodyFont]
                )
                y += 18
            }

            y += 10
            drawHorizontalLine(at: y, from: margin + 350, width: pageWidth - 350)
            y += 8

            // Totals
            func drawLine(_ label: String, _ amount: Decimal, bold: Bool = false) {
                let attrs: [NSAttributedString.Key: Any] = [.font: bold ? boldBodyFont : bodyFont]
                label.draw(at: CGPoint(x: margin + 350, y: y), withAttributes: attrs)
                (cur.string(from: amount as NSDecimalNumber) ?? "").draw(
                    at: CGPoint(x: margin + 440, y: y), withAttributes: attrs
                )
                y += 16
            }

            drawLine("Materials:", subtotalMaterials)
            drawLine("Labor:", subtotalLabor)
            drawLine("Other:", subtotalOther)
            drawLine("Tax:", taxAmount)
            y += 4
            drawLine("TOTAL:", totalAmount, bold: true)
            y += 20

            // Terms & conditions
            if let terms = termsAndConditions, !terms.isEmpty {
                if y > pageRect.height - 100 {
                    context.beginPage()
                    y = 40
                }
                "Terms & Conditions:".draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: boldBodyFont])
                y += 18
                terms.draw(
                    in: CGRect(x: margin, y: y, width: pageWidth, height: 120),
                    withAttributes: [.font: bodyFont]
                )
            }
        }

        let sanitizedTitle = projectTitle
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        return writeToTemp(data: data, filename: "Proposal_\(sanitizedTitle).pdf")
    }

    // MARK: - Private Helpers

    private static func drawHorizontalLine(at y: CGFloat, from x: CGFloat, width: CGFloat) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: x, y: y))
        path.addLine(to: CGPoint(x: x + width, y: y))
        UIColor.gray.setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    private static func writeToTemp(data: Data, filename: String) -> URL? {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: tempURL)
            return tempURL
        } catch {
            return nil
        }
    }

    private static func makeDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }

    private static func makeCurrencyFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter
    }
}
