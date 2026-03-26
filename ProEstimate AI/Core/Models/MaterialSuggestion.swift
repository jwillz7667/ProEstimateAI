import Foundation

/// Represents an AI-suggested material for a remodel generation.
/// Material suggestions are linked to a specific AI generation and can be
/// toggled on/off by the user before creating an estimate.
struct MaterialSuggestion: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let generationId: String
    let projectId: String
    let name: String
    let category: String
    let estimatedCost: Decimal
    let unit: String
    let quantity: Decimal
    let supplierName: String?
    let supplierURL: URL?
    let isSelected: Bool
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case generationId = "generation_id"
        case projectId = "project_id"
        case name
        case category
        case estimatedCost = "estimated_cost"
        case unit
        case quantity
        case supplierName = "supplier_name"
        case supplierURL = "supplier_url"
        case isSelected = "is_selected"
        case sortOrder = "sort_order"
    }
}

// MARK: - Convenience

extension MaterialSuggestion {
    /// Total cost for this material line (quantity * estimatedCost).
    var lineTotal: Decimal {
        quantity * estimatedCost
    }
}

// MARK: - Sample Data

extension MaterialSuggestion {
    static let sample = MaterialSuggestion(
        id: "ms-001",
        generationId: "gen-001",
        projectId: "p-001",
        name: "Quartz Countertop – Calacatta",
        category: "Countertops",
        estimatedCost: 75,
        unit: "sq ft",
        quantity: 45,
        supplierName: "Home Depot",
        supplierURL: URL(string: "https://homedepot.com/p/quartz-calacatta"),
        isSelected: true,
        sortOrder: 0
    )
}
