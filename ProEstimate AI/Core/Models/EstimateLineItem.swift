import Foundation

/// A single line item within an estimate.
/// Line items are categorized (materials, labor, other) and support
/// per-line markup and tax rate overrides.
struct EstimateLineItem: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let estimateId: String
    let parentLineItemId: String?
    let sourceMaterialSuggestionId: String?
    let category: Category
    let itemType: String?
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
        case parentLineItemId = "parent_line_item_id"
        case sourceMaterialSuggestionId = "source_material_suggestion_id"
        case category
        case itemType = "item_type"
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

    init(
        id: String,
        estimateId: String,
        parentLineItemId: String?,
        sourceMaterialSuggestionId: String?,
        category: Category,
        itemType: String?,
        name: String,
        description: String?,
        quantity: Decimal,
        unit: String,
        unitCost: Decimal,
        markupPercent: Decimal,
        taxRate: Decimal,
        lineTotal: Decimal,
        sortOrder: Int
    ) {
        self.id = id
        self.estimateId = estimateId
        self.parentLineItemId = parentLineItemId
        self.sourceMaterialSuggestionId = sourceMaterialSuggestionId
        self.category = category
        self.itemType = itemType
        self.name = name
        self.description = description
        self.quantity = quantity
        self.unit = unit
        self.unitCost = unitCost
        self.markupPercent = markupPercent
        self.taxRate = taxRate
        self.lineTotal = lineTotal
        self.sortOrder = sortOrder
    }

    /// Custom decoder that converts `tax_rate` from the canonical wire
    /// representation (fraction, e.g. 0.0825) to the in-memory
    /// representation UI math expects (percent, e.g. 8.25). Every other
    /// field decodes straight from the snake_case payload.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.estimateId = try c.decode(String.self, forKey: .estimateId)
        self.parentLineItemId = try c.decodeIfPresent(String.self, forKey: .parentLineItemId)
        self.sourceMaterialSuggestionId = try c.decodeIfPresent(String.self, forKey: .sourceMaterialSuggestionId)
        self.category = try c.decode(Category.self, forKey: .category)
        self.itemType = try c.decodeIfPresent(String.self, forKey: .itemType)
        self.name = try c.decode(String.self, forKey: .name)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.quantity = try c.decode(Decimal.self, forKey: .quantity)
        self.unit = try c.decode(String.self, forKey: .unit)
        self.unitCost = try c.decode(Decimal.self, forKey: .unitCost)
        self.markupPercent = try c.decode(Decimal.self, forKey: .markupPercent)
        let wireTax = try c.decode(Decimal.self, forKey: .taxRate)
        // Canonical wire format is a fraction (0.0825). Some rows predating
        // the tax_rate fix may still hold a percent (8.25) — detect by
        // magnitude and skip the scale-up so a legacy row doesn't become
        // 825% on screen.
        self.taxRate = wireTax > 1 ? wireTax : wireTax * 100
        self.lineTotal = try c.decode(Decimal.self, forKey: .lineTotal)
        self.sortOrder = try c.decode(Int.self, forKey: .sortOrder)
    }

    /// Symmetric encoder — converts `tax_rate` back to a fraction on the
    /// wire so the backend validator (0..1) accepts the value.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(estimateId, forKey: .estimateId)
        try c.encodeIfPresent(parentLineItemId, forKey: .parentLineItemId)
        try c.encodeIfPresent(sourceMaterialSuggestionId, forKey: .sourceMaterialSuggestionId)
        try c.encode(category, forKey: .category)
        try c.encodeIfPresent(itemType, forKey: .itemType)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encode(quantity, forKey: .quantity)
        try c.encode(unit, forKey: .unit)
        try c.encode(unitCost, forKey: .unitCost)
        try c.encode(markupPercent, forKey: .markupPercent)
        try c.encode(taxRate / 100, forKey: .taxRate)
        try c.encode(lineTotal, forKey: .lineTotal)
        try c.encode(sortOrder, forKey: .sortOrder)
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
        parentLineItemId: nil,
        sourceMaterialSuggestionId: nil,
        category: .materials,
        itemType: "per_unit",
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
