import Foundation

// MARK: - Line Item Draft

/// Mutable draft used when creating or editing a line item in the editor.
/// Converted to/from EstimateLineItem for persistence.
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

    /// Computed base cost before markup.
    var baseCost: Decimal {
        quantity * unitCost
    }

    /// Computed markup dollar amount.
    var markupAmount: Decimal {
        baseCost * (markupPercent / 100)
    }

    /// Computed tax dollar amount on (base + markup).
    var taxAmount: Decimal {
        (baseCost + markupAmount) * (taxRate / 100)
    }

    /// Computed line total including markup and tax.
    var lineTotal: Decimal {
        baseCost + markupAmount + taxAmount
    }

    /// Whether this draft has enough data to be saved.
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && quantity > 0 && unitCost >= 0
    }
}

// MARK: - LineItemDraft ↔ EstimateLineItem

extension LineItemDraft {
    /// Initialize a draft from an existing line item for editing.
    init(from item: EstimateLineItem) {
        self.id = item.id
        self.estimateId = item.estimateId
        self.category = item.category
        self.name = item.name
        self.description = item.description ?? ""
        self.quantity = item.quantity
        self.unit = LineItemUnit(rawValue: item.unit) ?? .each
        self.unitCost = item.unitCost
        self.markupPercent = item.markupPercent
        self.taxRate = item.taxRate
        self.sortOrder = item.sortOrder
    }

    /// Convert draft to an immutable EstimateLineItem for persistence.
    func toLineItem() -> EstimateLineItem {
        EstimateLineItem(
            id: id,
            estimateId: estimateId,
            category: category,
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

/// Standard measurement units for estimate line items.
enum LineItemUnit: String, CaseIterable, Identifiable, Sendable {
    case each
    case sqft = "sq ft"
    case lnft = "ln ft"
    case hour
    case day
    case lot

    var id: String { rawValue }

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

// MARK: - Estimate Status Filter

/// Filter options for the estimate list segmented control.
enum EstimateStatusFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case draft
    case sent
    case approved
    case declined
    case expired

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .draft: "Draft"
        case .sent: "Sent"
        case .approved: "Approved"
        case .declined: "Declined"
        case .expired: "Expired"
        }
    }

    /// The estimate statuses that match this filter.
    var matchingStatuses: [Estimate.Status] {
        switch self {
        case .all: Estimate.Status.allCases
        case .draft: [.draft]
        case .sent: [.sent]
        case .approved: [.approved]
        case .declined: [.declined]
        case .expired: [.expired]
        }
    }
}

// MARK: - Estimate Summary

/// Lightweight summary for list display, combining estimate + project info.
struct EstimateSummary: Identifiable, Sendable {
    let id: String
    let estimate: Estimate
    let projectTitle: String

    init(estimate: Estimate, projectTitle: String) {
        self.id = estimate.id
        self.estimate = estimate
        self.projectTitle = projectTitle
    }
}
