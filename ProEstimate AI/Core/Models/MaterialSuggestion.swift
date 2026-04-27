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
    /// Retailer-friendly query string for live price verification — the
    /// iOS deep-link picker pairs this with the contractor's preferred
    /// supplier (Home Depot / Lowe's / SiteOne / etc.) and opens the
    /// search URL. Nullable for legacy material rows generated before
    /// the prompt-library upgrade.
    let supplierSearchQuery: String?
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
        case supplierSearchQuery = "supplier_search_query"
        case isSelected = "is_selected"
        case sortOrder = "sort_order"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        generationId = try c.decode(String.self, forKey: .generationId)
        projectId = try c.decode(String.self, forKey: .projectId)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decode(String.self, forKey: .category)
        estimatedCost = try c.decode(Decimal.self, forKey: .estimatedCost)
        unit = try c.decode(String.self, forKey: .unit)
        quantity = try c.decode(Decimal.self, forKey: .quantity)
        supplierName = try c.decodeIfPresent(String.self, forKey: .supplierName)
        supplierURL = try c.decodeIfPresent(URL.self, forKey: .supplierURL)
        supplierSearchQuery = try c.decodeIfPresent(String.self, forKey: .supplierSearchQuery)
        isSelected = try c.decode(Bool.self, forKey: .isSelected)
        sortOrder = try c.decode(Int.self, forKey: .sortOrder)
    }

    init(
        id: String,
        generationId: String,
        projectId: String,
        name: String,
        category: String,
        estimatedCost: Decimal,
        unit: String,
        quantity: Decimal,
        supplierName: String?,
        supplierURL: URL?,
        supplierSearchQuery: String? = nil,
        isSelected: Bool,
        sortOrder: Int
    ) {
        self.id = id
        self.generationId = generationId
        self.projectId = projectId
        self.name = name
        self.category = category
        self.estimatedCost = estimatedCost
        self.unit = unit
        self.quantity = quantity
        self.supplierName = supplierName
        self.supplierURL = supplierURL
        self.supplierSearchQuery = supplierSearchQuery
        self.isSelected = isSelected
        self.sortOrder = sortOrder
    }
}

// MARK: - Convenience

extension MaterialSuggestion {
    /// Total cost for this material line (quantity * estimatedCost).
    var lineTotal: Decimal {
        quantity * estimatedCost
    }
}

// MARK: - Supplier Deep Links

/// Catalog of supported retailers the contractor can deep-link to from
/// each material suggestion. Each case knows how to build a search URL
/// from a retailer-friendly query string. Adding a new retailer is a
/// one-line change here plus a row in `displayName` / `iconAsset`.
enum MaterialSupplier: String, CaseIterable, Identifiable, Sendable {
    case homeDepot = "home_depot"
    case lowes
    case menards
    case amazonBusiness = "amazon_business"
    case ferguson
    case siteOne = "siteone"
    case acehardware
    case floorAndDecor = "floor_and_decor"

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .homeDepot: return "Home Depot"
        case .lowes: return "Lowe's"
        case .menards: return "Menards"
        case .amazonBusiness: return "Amazon Business"
        case .ferguson: return "Ferguson"
        case .siteOne: return "SiteOne Landscape Supply"
        case .acehardware: return "Ace Hardware"
        case .floorAndDecor: return "Floor & Decor"
        }
    }

    /// Build a search URL for `query` on this retailer. Each retailer's
    /// search path was verified at the time of writing; if a retailer
    /// changes their path we update the case here, not in callers.
    func searchURL(for query: String) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            ?? query
        let base: String
        switch self {
        case .homeDepot:
            base = "https://www.homedepot.com/s/\(encoded)"
        case .lowes:
            base = "https://www.lowes.com/search?searchTerm=\(encoded)"
        case .menards:
            base = "https://www.menards.com/main/search.html?search=\(encoded)"
        case .amazonBusiness:
            base = "https://www.amazon.com/s?k=\(encoded)"
        case .ferguson:
            base = "https://www.ferguson.com/search/\(encoded)"
        case .siteOne:
            base = "https://www.siteone.com/en/search?q=\(encoded)"
        case .acehardware:
            base = "https://www.acehardware.com/search?query=\(encoded)"
        case .floorAndDecor:
            base = "https://www.flooranddecor.com/search?q=\(encoded)"
        }
        return URL(string: base)
    }

    /// Heuristic match between a `MaterialSuggestion.supplierName` string
    /// (free-form, populated by the AI) and our enum. Lets the iOS UI
    /// pre-select the AI-suggested retailer in the deep-link picker.
    static func match(supplierName: String?) -> MaterialSupplier? {
        guard let raw = supplierName?.lowercased() else { return nil }
        if raw.contains("home depot") { return .homeDepot }
        if raw.contains("lowe") { return .lowes }
        if raw.contains("menards") { return .menards }
        if raw.contains("amazon") { return .amazonBusiness }
        if raw.contains("ferguson") { return .ferguson }
        if raw.contains("siteone") || raw.contains("site one") { return .siteOne }
        if raw.contains("ace") { return .acehardware }
        if raw.contains("floor & decor") || raw.contains("floor and decor") {
            return .floorAndDecor
        }
        return nil
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
        supplierSearchQuery: "quartz countertop calacatta slab",
        isSelected: true,
        sortOrder: 0
    )
}
