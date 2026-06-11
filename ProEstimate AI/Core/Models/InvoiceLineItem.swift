import Foundation

/// A single billable line within an invoice. Unlike `EstimateLineItem`,
/// invoice line items carry no per-line markup or tax-rate overrides — the
/// invoice's money is fixed at conversion time, so each line just records
/// the agreed quantity, unit, unit cost, and resulting total.
struct InvoiceLineItem: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let invoiceId: String
    let name: String
    let description: String?
    let quantity: Decimal
    let unit: String
    let unitCost: Decimal
    let lineTotal: Decimal
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case invoiceId = "invoice_id"
        case name
        case description
        case quantity
        case unit
        case unitCost = "unit_cost"
        case lineTotal = "line_total"
        case sortOrder = "sort_order"
    }
}

// MARK: - Sample Data

extension InvoiceLineItem {
    static let sample = InvoiceLineItem(
        id: "ili-001",
        invoiceId: "inv-001",
        name: "Quartz Countertop – Calacatta",
        description: "Premium quartz slab, fabrication included",
        quantity: 45,
        unit: "sq ft",
        unitCost: 75,
        lineTotal: 3375,
        sortOrder: 0
    )
}
