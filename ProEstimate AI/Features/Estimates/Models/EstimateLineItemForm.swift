import Foundation

struct EstimateLineItemForm: Equatable, Sendable {
    var category: EstimateLineItem.Category = .materials
    var name = ""
    var details = ""
    var quantity = "1"
    var unit = "each"
    var unitCost = "0"
    var markupPercent = "0"
    var taxPercent = "0"
    var sortOrder = 0

    init() {}

    init(item: EstimateLineItem, locale: Locale = .current) {
        category = item.category
        name = item.name
        details = item.description ?? ""
        quantity = Self.input(item.quantity, locale: locale)
        unit = item.unit
        unitCost = Self.input(item.unitCost, locale: locale)
        markupPercent = Self.input(item.markupPercent, locale: locale)
        // EstimateLineItem already decodes the fraction into a UI percent.
        taxPercent = Self.input(item.taxRate, locale: locale)
        sortOrder = item.sortOrder
    }

    func validatedRequest(locale: Locale = .current) throws -> EstimateLineItemEditRequest {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, cleanName.utf16.count <= 500 else {
            throw EstimateEditError.validation("Enter an item name of 1–500 characters.")
        }
        guard details.utf16.count <= 5000 else {
            throw EstimateEditError.validation("Keep the description within 5,000 characters.")
        }
        guard !cleanUnit.isEmpty, cleanUnit.utf16.count <= 50 else {
            throw EstimateEditError.validation("Enter a unit of 1–50 characters, such as hours or sq ft.")
        }
        guard let quantity = DecimalFormInput.parse(quantity, locale: locale), quantity > 0 else {
            throw EstimateEditError.validation("Quantity must be greater than zero.")
        }
        guard let unitCost = DecimalFormInput.parse(unitCost, locale: locale), unitCost >= 0 else {
            throw EstimateEditError.validation("Enter a unit cost of zero or more.")
        }
        guard let markup = DecimalFormInput.parse(markupPercent, locale: locale), markup >= 0, markup <= 1000 else {
            throw EstimateEditError.validation("Markup must be between 0% and 1,000%.")
        }
        guard let tax = DecimalFormInput.parse(taxPercent, locale: locale), tax >= 0, tax <= 100 else {
            throw EstimateEditError.validation("Tax must be between 0% and 100%.")
        }
        guard sortOrder >= 0 else { throw EstimateEditError.validation("The item order is invalid. Refresh the estimate.") }
        return EstimateLineItemEditRequest(
            category: category, name: cleanName, description: details.isEmpty ? nil : details,
            quantity: quantity, unit: cleanUnit, unitCost: unitCost,
            markupPercent: markup, taxRate: tax / 100, sortOrder: sortOrder
        )
    }

    private static func input(_ value: Decimal, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 38
        return formatter.string(from: value as NSDecimalNumber) ?? value.description
    }
}

/// Send only editable fields. Server-owned totals, ownership and source links
/// are omitted; a cleared description is explicitly encoded as JSON null.
struct EstimateLineItemEditRequest: Encodable, Sendable {
    let category: EstimateLineItem.Category
    let name: String
    let description: String?
    let quantity: Decimal
    let unit: String
    let unitCost: Decimal
    let markupPercent: Decimal
    let taxRate: Decimal
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case category, name, description, quantity, unit
        case unitCost = "unit_cost"
        case markupPercent = "markup_percent"
        case taxRate = "tax_rate"
        case sortOrder = "sort_order"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(category, forKey: .category)
        try c.encode(name, forKey: .name)
        try c.encode(description, forKey: .description)
        try c.encode(quantity, forKey: .quantity)
        try c.encode(unit, forKey: .unit)
        try c.encode(unitCost, forKey: .unitCost)
        try c.encode(markupPercent, forKey: .markupPercent)
        try c.encode(taxRate, forKey: .taxRate)
        try c.encode(sortOrder, forKey: .sortOrder)
    }
}

enum EstimateEditError: LocalizedError {
    case validation(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case let .validation(message): message
        case .invalidResponse: "The estimate response didn't match this document. Please refresh."
        }
    }
}
