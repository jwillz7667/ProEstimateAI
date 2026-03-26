import Foundation

/// A single line item within an estimate.
/// Line items are categorized (materials, labor, other) and support
/// per-line markup and tax rate overrides.
struct EstimateLineItem: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let estimateId: String
    let category: Category
    let name: String
    let description: String?
    let quantity: Decimal
    let unit: String
    let unitCost: Decimal
    let markupPercent: Decimal
    let taxRate: Decimal
    let lineTotal: Decimal
    let sortOrder: Int

    // MARK: - Nested Enums

    /// Cost category for grouping and subtotaling line items.
    enum Category: String, Codable, CaseIterable, Sendable {
        case materials
        case labor
        case other
    }

    enum CodingKeys: String, CodingKey {
        case id
        case estimateId = "estimate_id"
        case category
        case name
        case description
        case quantity
        case unit
        case unitCost = "unit_cost"
        case markupPercent = "markup_percent"
        case taxRate = "tax_rate"
        case lineTotal = "line_total"
        case sortOrder = "sort_order"
    }
}

// MARK: - Convenience

extension EstimateLineItem {
    /// Base cost before markup (quantity * unitCost).
    var baseCost: Decimal {
        quantity * unitCost
    }

    /// Markup amount applied to the base cost.
    var markupAmount: Decimal {
        baseCost * (markupPercent / 100)
    }

    /// Tax amount calculated on (baseCost + markupAmount).
    var taxAmount: Decimal {
        (baseCost + markupAmount) * (taxRate / 100)
    }
}

// MARK: - Sample Data

extension EstimateLineItem {
    static let sample = EstimateLineItem(
        id: "eli-001",
        estimateId: "e-001",
        category: .materials,
        name: "Quartz Countertop – Calacatta",
        description: "Premium quartz slab, fabrication included",
        quantity: 45,
        unit: "sq ft",
        unitCost: 75,
        markupPercent: 20,
        taxRate: 8.25,
        lineTotal: 4387.50,
        sortOrder: 0
    )
}
