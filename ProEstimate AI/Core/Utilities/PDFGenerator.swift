import UIKit

/// Produces professional, customer-ready PDF documents for estimates,
/// invoices, and proposals. Renders at US Letter (612×792 pt) using
/// `UIGraphicsPDFRenderer`, with a branded letterhead, an accent color
/// bar, grouped line items, a totals panel, and footer sections for
/// assumptions / exclusions / notes / terms.
enum PDFGenerator {

    // MARK: - Branding Context

    /// Company identity + branding that appears on every generated PDF.
    /// Built from the logged-in user's `Company` record; fields are
    /// optional so the layout renders only what's available.
    struct CompanyBranding: Sendable {
        let name: String
        let phone: String?
        let email: String?
        let addressLines: [String]
        let websiteUrl: String?
        let logoImage: UIImage?
        let accentColor: UIColor

        init(
            name: String,
            phone: String? = nil,
            email: String? = nil,
            addressLines: [String] = [],
            websiteUrl: String? = nil,
            logoImage: UIImage? = nil,
            accentHex: String? = nil
        ) {
            self.name = name
            self.phone = phone
            self.email = email
            self.addressLines = addressLines
            self.websiteUrl = websiteUrl
            self.logoImage = logoImage
            self.accentColor = Self.parseHex(accentHex) ?? UIColor(red: 1.0, green: 0.572, blue: 0.188, alpha: 1.0)
        }

        static func parseHex(_ hex: String?) -> UIColor? {
            guard var s = hex?.replacingOccurrences(of: "#", with: "") else { return nil }
            if s.count == 3 {
                s = s.map { "\($0)\($0)" }.joined()
            }
            guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
            return UIColor(
                red:   CGFloat((v & 0xFF0000) >> 16) / 255,
                green: CGFloat((v & 0x00FF00) >> 8)  / 255,
                blue:  CGFloat(v & 0x0000FF)         / 255,
                alpha: 1.0
            )
        }
    }

    /// Client block that appears under "Prepared For". All fields optional
    /// so the layout renders only what it has.
    struct ClientInfo: Sendable {
        let name: String
        let company: String?
        let phone: String?
        let email: String?
        let addressLines: [String]

        init(
            name: String,
            company: String? = nil,
            phone: String? = nil,
            email: String? = nil,
            addressLines: [String] = []
        ) {
            self.name = name
            self.company = company
            self.phone = phone
            self.email = email
            self.addressLines = addressLines
        }
    }

    /// Line item as it appears on the PDF. Category drives grouping;
    /// `description` renders as a secondary line under `name`.
    struct PDFLineItem: Sendable {
        let category: Category
        let name: String
        let description: String?
        let quantity: Decimal
        let unit: String
        let unitCost: Decimal
        let total: Decimal

        enum Category: String, Sendable {
            case materials = "Materials"
            case labor = "Labor"
            case other = "Other"
        }

        init(
            category: Category,
            name: String,
            description: String? = nil,
            quantity: Decimal,
            unit: String,
            unitCost: Decimal,
            total: Decimal
        ) {
            self.category = category
            self.name = name
            self.description = description
            self.quantity = quantity
            self.unit = unit
            self.unitCost = unitCost
            self.total = total
        }
    }

    // MARK: - Public API

    static func generateEstimatePDF(
        branding: CompanyBranding,
        client: ClientInfo? = nil,
        estimateNumber: String,
        title: String? = nil,
        date: Date,
        validUntil: Date? = nil,
        status: String,
        lineItems: [PDFLineItem],
        subtotalMaterials: Decimal,
        subtotalLabor: Decimal,
        subtotalOther: Decimal,
        taxAmount: Decimal,
        discountAmount: Decimal,
        totalAmount: Decimal,
        assumptions: String? = nil,
        exclusions: String? = nil,
        notes: String? = nil,
        terms: String? = nil,
        beforeImage: UIImage? = nil,
        afterImage: UIImage? = nil,
        projectTitle: String? = nil
    ) -> URL? {
        let data = render { ctx in
            Renderer(ctx: ctx, branding: branding).drawEstimate(
                client: client,
                number: estimateNumber,
                title: title,
                date: date,
                validUntil: validUntil,
                status: status,
                lineItems: lineItems,
                subtotalMaterials: subtotalMaterials,
                subtotalLabor: subtotalLabor,
                subtotalOther: subtotalOther,
                taxAmount: taxAmount,
                discountAmount: discountAmount,
                totalAmount: totalAmount,
                assumptions: assumptions,
                exclusions: exclusions,
                notes: notes,
                terms: terms,
                beforeImage: beforeImage,
                afterImage: afterImage,
                projectTitle: projectTitle
            )
        }
        return writeToTemp(data: data, filename: "\(estimateNumber).pdf")
    }

    static func generateInvoicePDF(
        branding: CompanyBranding,
        client: ClientInfo? = nil,
        invoiceNumber: String,
        date: Date,
        dueDate: Date?,
        status: String,
        lineItems: [PDFLineItem],
        subtotal: Decimal,
        taxAmount: Decimal,
        totalAmount: Decimal,
        amountPaid: Decimal,
        amountDue: Decimal,
        paymentInstructions: String? = nil,
        notes: String? = nil
    ) -> URL? {
        let data = render { ctx in
            Renderer(ctx: ctx, branding: branding).drawInvoice(
                client: client,
                number: invoiceNumber,
                date: date,
                dueDate: dueDate,
                status: status,
                lineItems: lineItems,
                subtotal: subtotal,
                taxAmount: taxAmount,
                totalAmount: totalAmount,
                amountPaid: amountPaid,
                amountDue: amountDue,
                paymentInstructions: paymentInstructions,
                notes: notes
            )
        }
        return writeToTemp(data: data, filename: "\(invoiceNumber).pdf")
    }

    static func generateProposalPDF(
        branding: CompanyBranding,
        client: ClientInfo? = nil,
        projectTitle: String,
        proposalDate: Date,
        expiresAt: Date?,
        clientMessage: String?,
        lineItems: [PDFLineItem],
        subtotalMaterials: Decimal,
        subtotalLabor: Decimal,
        subtotalOther: Decimal,
        taxAmount: Decimal,
        totalAmount: Decimal,
        termsAndConditions: String?
    ) -> URL? {
        let data = render { ctx in
            Renderer(ctx: ctx, branding: branding).drawProposal(
                client: client,
                projectTitle: projectTitle,
                date: proposalDate,
                expiresAt: expiresAt,
                clientMessage: clientMessage,
                lineItems: lineItems,
                subtotalMaterials: subtotalMaterials,
                subtotalLabor: subtotalLabor,
                subtotalOther: subtotalOther,
                taxAmount: taxAmount,
                totalAmount: totalAmount,
                terms: termsAndConditions
            )
        }
        let sanitizedTitle = projectTitle
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        return writeToTemp(data: data, filename: "Proposal_\(sanitizedTitle).pdf")
    }

    // MARK: - Renderer

    /// Stateful drawing helper — carries page metrics, cursor, current
    /// page, and reusable text styles. Shared across estimate, invoice,
    /// and proposal entry points so they render with a consistent system.
    private final class Renderer {
        let ctx: UIGraphicsPDFRendererContext
        let branding: CompanyBranding
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 54
        var y: CGFloat = 0

        var contentWidth: CGFloat { pageRect.width - margin * 2 }
        var pageBottom: CGFloat { pageRect.height - margin }

        let documentTitleFont = UIFont.systemFont(ofSize: 30, weight: .bold)
        let sectionTitleFont  = UIFont.systemFont(ofSize: 10, weight: .semibold)
        let companyNameFont   = UIFont.systemFont(ofSize: 14, weight: .semibold)
        let bodyFont          = UIFont.systemFont(ofSize: 10, weight: .regular)
        let boldBodyFont      = UIFont.systemFont(ofSize: 10, weight: .semibold)
        let smallFont         = UIFont.systemFont(ofSize: 8.5, weight: .regular)
        let tableHeaderFont   = UIFont.systemFont(ofSize: 8.5, weight: .semibold)
        let lineItemNameFont  = UIFont.systemFont(ofSize: 10, weight: .semibold)
        let lineItemDescFont  = UIFont.systemFont(ofSize: 8.5, weight: .regular)
        let totalLabelFont    = UIFont.systemFont(ofSize: 10, weight: .regular)
        let totalValueFont    = UIFont.systemFont(ofSize: 10, weight: .semibold)
        let grandTotalFont    = UIFont.systemFont(ofSize: 14, weight: .bold)

        let bodyColor     = UIColor(white: 0.13, alpha: 1.0)
        let mutedColor    = UIColor(white: 0.42, alpha: 1.0)
        let subtleColor   = UIColor(white: 0.60, alpha: 1.0)
        let hairlineColor = UIColor(white: 0.82, alpha: 1.0)
        let rowTintColor  = UIColor(white: 0.97, alpha: 1.0)

        let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateStyle = .long
            return f
        }()

        let currencyFormatter: NumberFormatter = {
            let f = NumberFormatter()
            f.numberStyle = .currency
            f.currencyCode = "USD"
            f.maximumFractionDigits = 2
            f.minimumFractionDigits = 2
            return f
        }()

        init(ctx: UIGraphicsPDFRendererContext, branding: CompanyBranding) {
            self.ctx = ctx
            self.branding = branding
            ctx.beginPage()
            drawAccentBar()
            y = margin + 4
        }

        // MARK: - Estimate

        func drawEstimate(
            client: ClientInfo?,
            number: String,
            title: String?,
            date: Date,
            validUntil: Date?,
            status: String,
            lineItems: [PDFLineItem],
            subtotalMaterials: Decimal,
            subtotalLabor: Decimal,
            subtotalOther: Decimal,
            taxAmount: Decimal,
            discountAmount: Decimal,
            totalAmount: Decimal,
            assumptions: String?,
            exclusions: String?,
            notes: String?,
            terms: String?,
            beforeImage: UIImage?,
            afterImage: UIImage?,
            projectTitle: String?
        ) {
            drawHeader(
                documentKind: "ESTIMATE",
                documentNumber: number,
                documentTitle: title,
                primaryDate: date,
                primaryDateLabel: "Issued",
                secondaryDate: validUntil,
                secondaryDateLabel: "Valid until",
                statusText: status
            )
            if let client { drawClientBlock(client: client) }

            drawProjectVisuals(
                projectTitle: projectTitle,
                before: beforeImage,
                after: afterImage
            )

            drawGroupedLineItemsTable(lineItems: lineItems)

            // Always render Materials, Labor, and Other subtotals — even at
            // zero — so the reader can see at a glance what the categories
            // contributed. Matters for DIY estimates, where Labor = $0.00
            // is a meaningful statement rather than an omission.
            drawTotalsPanel(rows: [
                TotalRow(label: "Materials", amount: subtotalMaterials),
                TotalRow(label: "Labor", amount: subtotalLabor),
                TotalRow(label: "Other", amount: subtotalOther),
                TotalRow(label: "Tax", amount: taxAmount),
                TotalRow(label: "Discount", amount: -discountAmount, hideIf: discountAmount == 0),
            ], grandTotalLabel: "Total", grandTotal: totalAmount)

            drawNotesBlocks([
                ("Scope Assumptions", assumptions),
                ("Exclusions", exclusions),
                ("Notes", notes),
                ("Terms", terms),
            ])

            drawFooter()
        }

        // MARK: - Invoice

        func drawInvoice(
            client: ClientInfo?,
            number: String,
            date: Date,
            dueDate: Date?,
            status: String,
            lineItems: [PDFLineItem],
            subtotal: Decimal,
            taxAmount: Decimal,
            totalAmount: Decimal,
            amountPaid: Decimal,
            amountDue: Decimal,
            paymentInstructions: String?,
            notes: String?
        ) {
            drawHeader(
                documentKind: "INVOICE",
                documentNumber: number,
                documentTitle: nil,
                primaryDate: date,
                primaryDateLabel: "Issued",
                secondaryDate: dueDate,
                secondaryDateLabel: "Due",
                statusText: status
            )
            if let client { drawClientBlock(client: client) }

            drawGroupedLineItemsTable(lineItems: lineItems)

            drawTotalsPanel(rows: [
                TotalRow(label: "Subtotal", amount: subtotal),
                TotalRow(label: "Tax", amount: taxAmount),
                TotalRow(label: "Total", amount: totalAmount, style: .emphasized),
                TotalRow(label: "Payments Received", amount: -amountPaid, hideIf: amountPaid == 0),
            ], grandTotalLabel: "Amount Due", grandTotal: amountDue)

            drawNotesBlocks([
                ("Payment Instructions", paymentInstructions),
                ("Notes", notes),
            ])

            drawFooter()
        }

        // MARK: - Proposal

        func drawProposal(
            client: ClientInfo?,
            projectTitle: String,
            date: Date,
            expiresAt: Date?,
            clientMessage: String?,
            lineItems: [PDFLineItem],
            subtotalMaterials: Decimal,
            subtotalLabor: Decimal,
            subtotalOther: Decimal,
            taxAmount: Decimal,
            totalAmount: Decimal,
            terms: String?
        ) {
            drawHeader(
                documentKind: "PROPOSAL",
                documentNumber: projectTitle,
                documentTitle: nil,
                primaryDate: date,
                primaryDateLabel: "Prepared",
                secondaryDate: expiresAt,
                secondaryDateLabel: "Expires",
                statusText: nil
            )
            if let client { drawClientBlock(client: client) }

            if let msg = clientMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !msg.isEmpty {
                drawSectionTitle("Message")
                drawMultiline(msg, font: bodyFont, color: bodyColor)
                y += 10
            }

            drawGroupedLineItemsTable(lineItems: lineItems)

            drawTotalsPanel(rows: [
                TotalRow(label: "Materials", amount: subtotalMaterials),
                TotalRow(label: "Labor", amount: subtotalLabor),
                TotalRow(label: "Other", amount: subtotalOther),
                TotalRow(label: "Tax", amount: taxAmount),
            ], grandTotalLabel: "Total", grandTotal: totalAmount)

            drawNotesBlocks([("Terms & Conditions", terms)])

            drawFooter()
        }

        // MARK: - Building blocks

        private func drawAccentBar() {
            let bar = CGRect(x: 0, y: 0, width: pageRect.width, height: 6)
            branding.accentColor.setFill()
            UIRectFill(bar)
        }

        private func drawHeader(
            documentKind: String,
            documentNumber: String,
            documentTitle: String?,
            primaryDate: Date,
            primaryDateLabel: String,
            secondaryDate: Date?,
            secondaryDateLabel: String,
            statusText: String?
        ) {
            let startY = y + 4
            let leftX = margin
            let rightX = margin + contentWidth / 2 + 20

            // --- Left column: logo + company block ---
            var leftY = startY
            if let logo = branding.logoImage {
                let aspect = logo.size.width / max(logo.size.height, 1)
                let logoHeight: CGFloat = 42
                logo.draw(in: CGRect(x: leftX, y: leftY, width: logoHeight * aspect, height: logoHeight))
                leftY += logoHeight + 6
            }
            drawText(branding.name, at: CGPoint(x: leftX, y: leftY), font: companyNameFont, color: bodyColor)
            leftY += 18

            for line in branding.addressLines {
                drawText(line, at: CGPoint(x: leftX, y: leftY), font: smallFont, color: mutedColor)
                leftY += 11
            }
            var contact: [String] = []
            if let p = branding.phone { contact.append(p) }
            if let e = branding.email { contact.append(e) }
            if !contact.isEmpty {
                drawText(contact.joined(separator: "   •   "), at: CGPoint(x: leftX, y: leftY), font: smallFont, color: mutedColor)
                leftY += 11
            }
            if let web = branding.websiteUrl {
                drawText(web, at: CGPoint(x: leftX, y: leftY), font: smallFont, color: mutedColor)
                leftY += 11
            }

            // --- Right column: document kind, number, dates, status ---
            let titleParagraph = NSMutableParagraphStyle()
            titleParagraph.alignment = .right
            let kindAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: branding.accentColor,
                .kern: 4.5 as NSNumber,
                .paragraphStyle: titleParagraph,
            ]
            (documentKind as NSString).draw(
                in: CGRect(x: rightX, y: startY, width: pageRect.width - margin - rightX, height: 14),
                withAttributes: kindAttrs
            )

            let numberAttrs: [NSAttributedString.Key: Any] = [
                .font: documentTitleFont,
                .foregroundColor: bodyColor,
                .paragraphStyle: titleParagraph,
            ]
            (documentNumber as NSString).draw(
                in: CGRect(x: rightX, y: startY + 16, width: pageRect.width - margin - rightX, height: 36),
                withAttributes: numberAttrs
            )

            var rightY = startY + 52
            if let title = documentTitle, !title.isEmpty {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: mutedColor,
                    .paragraphStyle: titleParagraph,
                ]
                (title as NSString).draw(
                    in: CGRect(x: rightX, y: rightY, width: pageRect.width - margin - rightX, height: 14),
                    withAttributes: attrs
                )
                rightY += 16
            }

            rightY += 8
            drawKeyValueRight(label: primaryDateLabel, value: dateFormatter.string(from: primaryDate), atY: &rightY)
            if let secondaryDate {
                drawKeyValueRight(label: secondaryDateLabel, value: dateFormatter.string(from: secondaryDate), atY: &rightY)
            }
            if let status = statusText, !status.isEmpty {
                drawKeyValueRight(
                    label: "Status",
                    value: status.uppercased(),
                    atY: &rightY,
                    valueColor: branding.accentColor,
                    valueFont: boldBodyFont
                )
            }

            y = max(leftY, rightY) + 18
            drawHairline()
            y += 16
        }

        private func drawKeyValueRight(
            label: String,
            value: String,
            atY rowY: inout CGFloat,
            valueColor: UIColor? = nil,
            valueFont: UIFont? = nil
        ) {
            let rightEdge = pageRect.width - margin
            let labelAttrs: [NSAttributedString.Key: Any] = [.font: smallFont, .foregroundColor: mutedColor]
            let valAttrs: [NSAttributedString.Key: Any] = [
                .font: valueFont ?? bodyFont,
                .foregroundColor: valueColor ?? bodyColor,
            ]

            let labelStr = label as NSString
            let valStr = value as NSString
            let labelSize = labelStr.size(withAttributes: labelAttrs)
            let valSize = valStr.size(withAttributes: valAttrs)
            let gap: CGFloat = 8
            valStr.draw(at: CGPoint(x: rightEdge - valSize.width, y: rowY), withAttributes: valAttrs)
            labelStr.draw(at: CGPoint(x: rightEdge - valSize.width - gap - labelSize.width, y: rowY + 1), withAttributes: labelAttrs)
            rowY += 14
        }

        private func drawClientBlock(client: ClientInfo) {
            drawSectionTitle("Prepared For")

            drawText(client.name, at: CGPoint(x: margin, y: y), font: boldBodyFont, color: bodyColor)
            y += 13
            if let companyName = client.company, !companyName.isEmpty {
                drawText(companyName, at: CGPoint(x: margin, y: y), font: bodyFont, color: bodyColor)
                y += 12
            }
            for line in client.addressLines {
                drawText(line, at: CGPoint(x: margin, y: y), font: smallFont, color: mutedColor)
                y += 11
            }
            var contact: [String] = []
            if let p = client.phone { contact.append(p) }
            if let e = client.email { contact.append(e) }
            if !contact.isEmpty {
                drawText(contact.joined(separator: "   •   "), at: CGPoint(x: margin, y: y), font: smallFont, color: mutedColor)
                y += 12
            }
            y += 14
        }

        /// Renders a "Project Visuals" section with before/after photos side
        /// by side. Skips the whole section if neither image is provided.
        /// Falls back to a single full-width image if only one side is
        /// available. Forces a page break if the section wouldn't fit on the
        /// current page.
        private func drawProjectVisuals(
            projectTitle: String?,
            before: UIImage?,
            after: UIImage?
        ) {
            guard before != nil || after != nil else { return }

            let sectionLabel = (projectTitle?.isEmpty == false)
                ? "Project Visuals — \(projectTitle!)"
                : "Project Visuals"

            let imageAreaHeight: CGFloat = 170
            let captionHeight: CGFloat = 14
            let sectionTitleBlock: CGFloat = 26 // title + accent rule + padding
            let estimatedBlockHeight = sectionTitleBlock + imageAreaHeight + captionHeight + 20
            if y + estimatedBlockHeight > pageBottom - 40 { newPage() }

            drawSectionTitle(sectionLabel)

            if let before, let after {
                let gap: CGFloat = 12
                let slotWidth = (contentWidth - gap) / 2
                drawImageSlot(image: before, caption: "Before", x: margin, width: slotWidth, maxHeight: imageAreaHeight)
                drawImageSlot(image: after,  caption: "After",  x: margin + slotWidth + gap, width: slotWidth, maxHeight: imageAreaHeight)
                y += imageAreaHeight + captionHeight + 12
            } else if let single = before ?? after {
                let caption = before != nil ? "Before" : "After"
                drawImageSlot(image: single, caption: caption, x: margin, width: contentWidth, maxHeight: imageAreaHeight)
                y += imageAreaHeight + captionHeight + 12
            }
        }

        /// Draws one project-visual slot: the image aspect-fitted within the
        /// slot, a hairline border, and a caption chip below. Image origin is
        /// current `y`.
        private func drawImageSlot(
            image: UIImage,
            caption: String,
            x: CGFloat,
            width: CGFloat,
            maxHeight: CGFloat
        ) {
            let aspect = image.size.width / max(image.size.height, 1)
            var drawWidth = width
            var drawHeight = width / aspect
            if drawHeight > maxHeight {
                drawHeight = maxHeight
                drawWidth = maxHeight * aspect
            }
            let drawX = x + (width - drawWidth) / 2
            let drawY = y + (maxHeight - drawHeight) / 2

            // Subtle frame behind the image so slots read as cards even if the
            // image has a transparent background.
            let frame = CGRect(x: x, y: y, width: width, height: maxHeight)
            UIColor(white: 0.96, alpha: 1.0).setFill()
            UIRectFill(frame)

            image.draw(in: CGRect(x: drawX, y: drawY, width: drawWidth, height: drawHeight))

            // Border
            let border = UIBezierPath(rect: frame)
            border.lineWidth = 0.5
            hairlineColor.setStroke()
            border.stroke()

            // Caption chip below
            let captionY = y + maxHeight + 4
            let chipHeight: CGFloat = 14
            let captionAttrs: [NSAttributedString.Key: Any] = [
                .font: tableHeaderFont,
                .foregroundColor: branding.accentColor,
                .kern: 1.3 as NSNumber,
            ]
            let captionStr = caption.uppercased() as NSString
            let captionSize = captionStr.size(withAttributes: captionAttrs)
            let chipWidth = captionSize.width + 14
            let chipRect = CGRect(x: x, y: captionY, width: chipWidth, height: chipHeight)
            branding.accentColor.withAlphaComponent(0.1).setFill()
            UIBezierPath(roundedRect: chipRect, cornerRadius: 3).fill()
            captionStr.draw(
                at: CGPoint(x: x + 7, y: captionY + 1),
                withAttributes: captionAttrs
            )
        }

        private func drawGroupedLineItemsTable(lineItems: [PDFLineItem]) {
            // 4-column layout with item taking ~58% of the width
            let col1 = margin
            let col3 = margin + contentWidth * 0.72
            let col4 = margin + contentWidth * 0.86

            drawTableHeader(col1: col1, col3: col3, col4: col4)

            let groups: [PDFLineItem.Category] = [.materials, .labor, .other]
            var first = true
            for category in groups {
                let items = lineItems.filter { $0.category == category }
                guard !items.isEmpty else { continue }
                if !first { y += 4 }
                drawCategoryBand(category.rawValue)
                for (idx, item) in items.enumerated() {
                    drawLineItemRow(item, zebra: idx.isMultiple(of: 2), col1: col1, col3: col3, col4: col4)
                }
                first = false
            }

            y += 6
            drawHairline()
            y += 10
        }

        private func drawTableHeader(col1: CGFloat, col3: CGFloat, col4: CGFloat) {
            drawText("ITEM", at: CGPoint(x: col1 + 6, y: y), font: tableHeaderFont, color: mutedColor, tracking: 1.3)
            drawRightAligned("QTY",   at: CGPoint(x: col3 - 10, y: y), font: tableHeaderFont, color: mutedColor, tracking: 1.3)
            drawRightAligned("RATE",  at: CGPoint(x: col4 - 10, y: y), font: tableHeaderFont, color: mutedColor, tracking: 1.3)
            drawRightAligned("TOTAL", at: CGPoint(x: pageRect.width - margin - 6, y: y), font: tableHeaderFont, color: mutedColor, tracking: 1.3)
            y += 12
            drawHairline()
            y += 6
        }

        private func drawCategoryBand(_ title: String) {
            let bandHeight: CGFloat = 18
            let rect = CGRect(x: margin, y: y - 2, width: contentWidth, height: bandHeight)
            branding.accentColor.withAlphaComponent(0.08).setFill()
            UIRectFill(rect)
            drawText(title.uppercased(), at: CGPoint(x: margin + 6, y: y + 2), font: tableHeaderFont, color: branding.accentColor, tracking: 1.4)
            y += bandHeight + 2
        }

        private func drawLineItemRow(
            _ item: PDFLineItem,
            zebra: Bool,
            col1: CGFloat,
            col3: CGFloat,
            col4: CGFloat
        ) {
            let hasDescription = (item.description?.isEmpty == false)
            let rowHeight: CGFloat = hasDescription ? 30 : 20
            if y + rowHeight > pageBottom - 60 { newPage() }

            if zebra {
                let bg = CGRect(x: margin, y: y - 2, width: contentWidth, height: rowHeight)
                rowTintColor.setFill()
                UIRectFill(bg)
            }

            let nameColumnWidth = col3 - col1 - 18
            drawTextConstrained(
                item.name,
                in: CGRect(x: col1 + 6, y: y + 2, width: nameColumnWidth, height: 14),
                font: lineItemNameFont,
                color: bodyColor
            )
            if let desc = item.description, !desc.isEmpty {
                drawTextConstrained(
                    desc,
                    in: CGRect(x: col1 + 6, y: y + 16, width: nameColumnWidth, height: 12),
                    font: lineItemDescFont,
                    color: mutedColor
                )
            }

            let qtyText = "\(formatDecimal(item.quantity)) \(item.unit)"
            drawRightAligned(qtyText,                      at: CGPoint(x: col3 - 10, y: y + 2), font: bodyFont, color: bodyColor)
            drawRightAligned(currency(item.unitCost),      at: CGPoint(x: col4 - 10, y: y + 2), font: bodyFont, color: bodyColor)
            drawRightAligned(currency(item.total),         at: CGPoint(x: pageRect.width - margin - 6, y: y + 2), font: boldBodyFont, color: bodyColor)

            y += rowHeight
        }

        // MARK: - Totals

        private struct TotalRow {
            let label: String
            let amount: Decimal
            var hideIf: Bool = false
            var style: Style = .normal
            enum Style { case normal, emphasized }
        }

        private func drawTotalsPanel(rows: [TotalRow], grandTotalLabel: String, grandTotal: Decimal) {
            let panelX = margin + contentWidth * 0.55
            let panelWidth = contentWidth * 0.45
            let rightEdge = pageRect.width - margin

            let visible = rows.filter { !$0.hideIf }
            let estHeight: CGFloat = CGFloat(visible.count) * 16 + 46
            if y + estHeight > pageBottom - 60 { newPage() }

            for row in visible {
                let labelFont: UIFont = row.style == .emphasized ? boldBodyFont : totalLabelFont
                let valueFont: UIFont = row.style == .emphasized ? boldBodyFont : totalValueFont
                drawText(row.label, at: CGPoint(x: panelX, y: y), font: labelFont, color: mutedColor)
                drawRightAligned(currency(row.amount), at: CGPoint(x: rightEdge, y: y), font: valueFont, color: bodyColor)
                y += 16
            }

            let topBar = CGRect(x: panelX, y: y + 2, width: panelWidth, height: 1.5)
            branding.accentColor.setFill()
            UIRectFill(topBar)
            y += 10

            drawText(
                grandTotalLabel.uppercased(),
                at: CGPoint(x: panelX, y: y + 3),
                font: UIFont.systemFont(ofSize: 10, weight: .semibold),
                color: bodyColor,
                tracking: 1.4
            )
            drawRightAligned(currency(grandTotal), at: CGPoint(x: rightEdge, y: y - 2), font: grandTotalFont, color: branding.accentColor)
            y += 30
        }

        // MARK: - Notes blocks

        private func drawNotesBlocks(_ blocks: [(String, String?)]) {
            for (title, content) in blocks {
                guard let content = content?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else { continue }
                if y > pageBottom - 110 { newPage() }
                drawSectionTitle(title)
                drawMultiline(content, font: bodyFont, color: bodyColor)
                y += 10
            }
        }

        private func drawSectionTitle(_ title: String) {
            drawText(title.uppercased(), at: CGPoint(x: margin, y: y), font: sectionTitleFont, color: branding.accentColor, tracking: 1.6)
            y += 14
            let rule = CGRect(x: margin, y: y, width: 32, height: 1.5)
            branding.accentColor.setFill()
            UIRectFill(rule)
            y += 12
        }

        private func drawMultiline(_ text: String, font: UIFont, color: UIColor) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 2
            paragraph.lineBreakMode = .byWordWrapping
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph,
            ]
            let maxHeight: CGFloat = 500
            let bounded = (text as NSString).boundingRect(
                with: CGSize(width: contentWidth, height: maxHeight),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs,
                context: nil
            )
            if y + bounded.height > pageBottom - 30 { newPage() }
            let rect = CGRect(x: margin, y: y, width: contentWidth, height: bounded.height + 4)
            (text as NSString).draw(in: rect, withAttributes: attrs)
            y += max(bounded.height, font.lineHeight) + 4
        }

        // MARK: - Footer

        private func drawFooter() {
            let footerY = pageBottom + 8
            let rule = CGRect(x: margin, y: footerY - 8, width: contentWidth, height: 0.5)
            hairlineColor.setFill()
            UIRectFill(rule)

            var parts: [String] = [branding.name]
            if let phone = branding.phone { parts.append(phone) }
            if let email = branding.email { parts.append(email) }
            if let web = branding.websiteUrl { parts.append(web) }
            let footerText = parts.joined(separator: "   •   ")

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: smallFont,
                .foregroundColor: subtleColor,
                .paragraphStyle: paragraph,
            ]
            (footerText as NSString).draw(
                in: CGRect(x: margin, y: footerY, width: contentWidth, height: 14),
                withAttributes: attrs
            )
        }

        // MARK: - Drawing helpers

        private func drawText(
            _ string: String,
            at point: CGPoint,
            font: UIFont,
            color: UIColor,
            tracking: CGFloat = 0
        ) {
            var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            if tracking != 0 { attrs[.kern] = tracking as NSNumber }
            (string as NSString).draw(at: point, withAttributes: attrs)
        }

        private func drawRightAligned(
            _ string: String,
            at point: CGPoint,
            font: UIFont,
            color: UIColor,
            tracking: CGFloat = 0
        ) {
            var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            if tracking != 0 { attrs[.kern] = tracking as NSNumber }
            let size = (string as NSString).size(withAttributes: attrs)
            (string as NSString).draw(at: CGPoint(x: point.x - size.width, y: point.y), withAttributes: attrs)
        }

        private func drawTextConstrained(
            _ string: String,
            in rect: CGRect,
            font: UIFont,
            color: UIColor
        ) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph,
            ]
            (string as NSString).draw(in: rect, withAttributes: attrs)
        }

        private func drawHairline() {
            let rule = CGRect(x: margin, y: y, width: contentWidth, height: 0.5)
            hairlineColor.setFill()
            UIRectFill(rule)
        }

        private func newPage() {
            drawFooter()
            ctx.beginPage()
            drawAccentBar()
            y = margin + 4
        }

        // MARK: - Formatting

        private func currency(_ amount: Decimal) -> String {
            currencyFormatter.string(from: amount as NSDecimalNumber) ?? ""
        }

        private func formatDecimal(_ amount: Decimal) -> String {
            let ns = amount as NSDecimalNumber
            if ns.doubleValue.truncatingRemainder(dividingBy: 1) == 0 {
                return String(format: "%d", ns.intValue)
            }
            let f = NumberFormatter()
            f.minimumFractionDigits = 1
            f.maximumFractionDigits = 3
            return f.string(from: ns) ?? "\(amount)"
        }
    }

    // MARK: - Plumbing

    private static func render(_ body: (UIGraphicsPDFRendererContext) -> Void) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { ctx in body(ctx) }
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
}
