import Foundation

/// A single line within an invoice. Invoice line items are flat (no category
/// grouping, no per-line markup or tax — those are baked into `unitCost` and
/// rolled into the invoice's tax/discount totals). `lineTotal` is computed
/// server-side as `quantity * unitCost`.
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
        name: "Kitchen Remodel — Materials & Labor",
        description: "Per approved estimate EST-1001",
        quantity: 1,
        unit: "lot",
        unitCost: 21000,
        lineTotal: 21000,
        sortOrder: 0
    )
}
