#if canImport(UIKit)
    import UIKit
#endif
import Foundation

/// Renders an estimate (with its line items) into a branded PDF.
/// Lifted out of the deprecated `EstimateEditorViewModel` so the project
/// detail screen can export without instantiating an editor.
enum EstimatePDFRenderer {
    static func render(
        estimate: Estimate,
        lineItems: [EstimateLineItem],
        isDIY: Bool,
        branding: PDFGenerator.CompanyBranding,
        client: PDFGenerator.ClientInfo? = nil,
        beforeImage: UIImage? = nil,
        afterImage: UIImage? = nil,
        projectTitle: String? = nil
    ) -> URL? {
        let materials = lineItems
            .filter { $0.category == .materials }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { LineItemDraft(from: $0) }
        let labor = lineItems
            .filter { $0.category == .labor }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { LineItemDraft(from: $0) }
        let other = lineItems
            .filter { $0.category == .other }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { LineItemDraft(from: $0) }

        var pdfItems: [PDFGenerator.PDFLineItem] = []
        pdfItems.append(contentsOf: materials.map(Self.toPDFItem))
        if !isDIY {
            pdfItems.append(contentsOf: labor.map(Self.toPDFItem))
        }
        pdfItems.append(contentsOf: other.map(Self.toPDFItem))

        let subtotalMaterials = materials.reduce(Decimal.zero) { $0 + $1.lineTotal }
        let subtotalLabor: Decimal = isDIY
            ? .zero
            : labor.reduce(Decimal.zero) { $0 + $1.lineTotal }
        let subtotalOther = other.reduce(Decimal.zero) { $0 + $1.lineTotal }

        let materialsTax = materials.reduce(Decimal.zero) { $0 + $1.taxAmount }
        let laborTax: Decimal = isDIY
            ? .zero
            : labor.reduce(Decimal.zero) { $0 + $1.taxAmount }
        let otherTax = other.reduce(Decimal.zero) { $0 + $1.taxAmount }
        let taxAmount = materialsTax + laborTax + otherTax

        let preTaxMaterials = materials.reduce(Decimal.zero) { $0 + $1.baseCost + $1.markupAmount }
        let preTaxLabor: Decimal = isDIY
            ? .zero
            : labor.reduce(Decimal.zero) { $0 + $1.baseCost + $1.markupAmount }
        let preTaxOther = other.reduce(Decimal.zero) { $0 + $1.baseCost + $1.markupAmount }
        let totalAmount = preTaxMaterials + preTaxLabor + preTaxOther + taxAmount - estimate.discountAmount

        return PDFGenerator.generateEstimatePDF(
            branding: branding,
            client: client,
            estimateNumber: estimate.estimateNumber + (isDIY ? " (DIY)" : ""),
            title: estimate.title,
            date: estimate.createdAt,
            validUntil: estimate.validUntil,
            lineItems: pdfItems,
            subtotalMaterials: subtotalMaterials,
            subtotalLabor: subtotalLabor,
            subtotalOther: subtotalOther,
            taxAmount: taxAmount,
            discountAmount: estimate.discountAmount,
            totalAmount: totalAmount,
            assumptions: estimate.assumptions,
            exclusions: estimate.exclusions,
            notes: estimate.notes,
            terms: nil,
            beforeImage: beforeImage,
            afterImage: afterImage,
            projectTitle: projectTitle
        )
    }

    private static func toPDFItem(_ draft: LineItemDraft) -> PDFGenerator.PDFLineItem {
        let category: PDFGenerator.PDFLineItem.Category = {
            switch draft.category {
            case .materials: return .materials
            case .labor: return .labor
            case .other: return .other
            }
        }()
        return PDFGenerator.PDFLineItem(
            category: category,
            name: draft.name,
            description: draft.description.isEmpty ? nil : draft.description,
            quantity: draft.quantity,
            unit: draft.unit.rawValue,
            unitCost: draft.unitCost,
            total: draft.lineTotal
        )
    }
}
