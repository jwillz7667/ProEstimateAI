import Foundation
import StoreKit

/// Protocol abstracting StoreKit 2 product loading and eligibility checks.
/// The real implementation uses `Product.products(for:)` and subscription status APIs.
/// Mock implementations can return synthetic data for previews and tests without
/// requiring a StoreKit configuration file.
protocol StoreKitCatalogProviding: Sendable {
    /// Load all subscription products from the App Store for the configured product IDs.
    /// Returns an array of StoreKit `Product` objects.
    func loadProducts() async throws -> [Product]

    /// Retrieve a single product by its identifier.
    /// Returns `nil` if the product is not found in the catalog.
    func product(for id: String) async throws -> Product?

    /// Check whether the current user is eligible for an introductory offer
    /// in the given subscription group.
    /// Returns `true` if the user has never subscribed to this group.
    func isEligibleForIntroOffer(groupID: String) async -> Bool
}
