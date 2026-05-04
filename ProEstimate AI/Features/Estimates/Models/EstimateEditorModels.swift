import Foundation

// MARK: - Line Item Draft

/// Mutable draft used when seeding line items from material suggestions
/// or when computing PDF totals at export time.
struct LineItemDraft: Identifiable, Sendable {
    var id: String = UUID().uuidString
    var estimateId: String = ""
    var category: EstimateLineItem.Category = .materials
    var name: String = ""
    var description: String = ""
    var quantity: Decimal = 1
    var unit: LineItemUnit = .each
    var unitCost: Decimal = 0
    var markupPercent: Decimal = 20
    var taxRate: Decimal = 8.25
    var sortOrder: Int = 0

    var baseCost: Decimal {
        quantity * unitCost
    }

    var markupAmount: Decimal {
        baseCost * (markupPercent / 100)
    }

    var taxAmount: Decimal {
        (baseCost + markupAmount) * (taxRate / 100)
    }

    var lineTotal: Decimal {
        baseCost + markupAmount + taxAmount
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && quantity > 0 && unitCost >= 0
    }
}

// MARK: - LineItemDraft ↔ EstimateLineItem

extension LineItemDraft {
    init(from item: EstimateLineItem) {
        id = item.id
        estimateId = item.estimateId
        category = item.category
        name = item.name
        description = item.description ?? ""
        quantity = item.quantity
        unit = LineItemUnit(rawValue: item.unit) ?? .each
        unitCost = item.unitCost
        markupPercent = item.markupPercent
        taxRate = item.taxRate
        sortOrder = item.sortOrder
    }

    /// Initialize a draft from an AI-suggested material.
    /// When `isDIY` is true, markup is set to 0 (homeowner cost only).
    init(from material: MaterialSuggestion, estimateId: String, isDIY: Bool, sortOrder: Int) {
        id = UUID().uuidString
        self.estimateId = estimateId
        category = .materials
        name = material.name
        quantity = material.quantity
        unit = LineItemUnit(rawValue: material.unit) ?? .each
        unitCost = material.estimatedCost
        markupPercent = isDIY ? 0 : 10
        taxRate = 8.25
        self.sortOrder = sortOrder

        // Embed supplier info in description so it persists through the backend.
        var desc = material.category
        if let supplier = material.supplierName {
            desc += " · \(supplier)"
        }
        if let url = material.supplierURL {
            desc += " · \(url.absoluteString)"
        }
        description = desc
    }

    /// Creates a default labor line item based on project type.
    static func defaultLabor(
        estimateId: String,
        projectType: Project.ProjectType,
        materialsCost: Decimal,
        sortOrder: Int
    ) -> LineItemDraft {
        let (name, rate, hours) = laborDefaults(for: projectType, materialsCost: materialsCost)
        var draft = LineItemDraft()
        draft.id = UUID().uuidString
        draft.estimateId = estimateId
        draft.category = .labor
        draft.name = name
        draft.description = "Professional installation labor"
        draft.quantity = hours
        draft.unit = .hour
        draft.unitCost = rate
        draft.markupPercent = 15
        draft.taxRate = 0
        draft.sortOrder = sortOrder
        return draft
    }

    private static func laborDefaults(
        for projectType: Project.ProjectType,
        materialsCost _: Decimal
    ) -> (String, Decimal, Decimal) {
        switch projectType {
        case .kitchen:
            return ("Kitchen Installation Labor", 75, 40)
        case .bathroom:
            return ("Bathroom Installation Labor", 70, 24)
        case .flooring:
            return ("Flooring Installation Labor", 55, 16)
        case .roofing:
            return ("Roofing Installation Labor", 65, 24)
        case .painting:
            return ("Painting Labor", 45, 16)
        case .siding:
            return ("Siding Installation Labor", 60, 32)
        case .roomRemodel:
            return ("Room Remodel Labor", 65, 24)
        case .exterior:
            return ("Exterior Work Labor", 60, 24)
        case .landscaping:
            return ("Landscape Install Labor", 55, 32)
        case .lawnCare:
            return ("Lawn Care Crew (per visit)", 50, 3)
        case .outdoorLiving:
            return ("Outdoor Living Install Labor", 65, 40)
        case .garage:
            return ("Garage Build-Out Labor", 60, 28)
        case .custom:
            return ("General Contractor Labor", 65, 20)
        }
    }

    func toLineItem() -> EstimateLineItem {
        EstimateLineItem(
            id: id,
            estimateId: estimateId,
            parentLineItemId: nil,
            sourceMaterialSuggestionId: nil,
            category: category,
            itemType: "per_unit",
            name: name,
            description: description.isEmpty ? nil : description,
            quantity: quantity,
            unit: unit.rawValue,
            unitCost: unitCost,
            markupPercent: markupPercent,
            taxRate: taxRate,
            lineTotal: lineTotal,
            sortOrder: sortOrder
        )
    }
}

// MARK: - Line Item Unit

enum LineItemUnit: String, CaseIterable, Identifiable, Sendable {
    case each
    case sqft = "sq ft"
    case lnft = "ln ft"
    case hour
    case day
    case lot

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .each: "Each"
        case .sqft: "Sq Ft"
        case .lnft: "Ln Ft"
        case .hour: "Hour"
        case .day: "Day"
        case .lot: "Lot"
        }
    }
}
