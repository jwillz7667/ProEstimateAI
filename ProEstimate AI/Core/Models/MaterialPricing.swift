import Foundation

/// A material product from Home Depot with real-time pricing.
struct MaterialPricingProduct: Codable, Identifiable, Hashable, Sendable {
    let productId: String
    let title: String
    let brand: String
    let price: Decimal?
    let priceWas: Decimal?
    let savings: String?
    let percentageOff: Double?
    let rating: Double?
    let reviews: Int?
    let modelNumber: String?
    let link: String
    let thumbnail: String?
    let deliveryFree: Bool
    let inStorePickup: Bool
    let badges: [String]

    var id: String { productId }

    /// Formatted price string.
    var formattedPrice: String {
        guard let price else { return "N/A" }
        return "$\(price)"
    }

    /// Whether this product is on sale.
    var isOnSale: Bool {
        priceWas != nil && percentageOff != nil && (percentageOff ?? 0) > 0
    }

    enum CodingKeys: String, CodingKey {
        case productId = "product_id"
        case title, brand, price
        case priceWas = "price_was"
        case savings
        case percentageOff = "percentage_off"
        case rating, reviews
        case modelNumber = "model_number"
        case link, thumbnail
        case deliveryFree = "delivery_free"
        case inStorePickup = "in_store_pickup"
        case badges
    }
}

/// Search result from the materials pricing API.
struct MaterialSearchResult: Codable, Sendable {
    let products: [MaterialPricingProduct]
    let totalResults: Int
    let storeName: String?
    let query: String

    enum CodingKeys: String, CodingKey {
        case products
        case totalResults = "total_results"
        case storeName = "store_name"
        case query
    }
}

/// Categorized materials for a project type.
struct ProjectMaterialsResult: Codable, Sendable {
    let categories: [String: [MaterialPricingProduct]]
    let projectType: String
    let zipCode: String?

    enum CodingKeys: String, CodingKey {
        case categories
        case projectType = "project_type"
        case zipCode = "zip_code"
    }
}
