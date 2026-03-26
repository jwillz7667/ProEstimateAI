import Foundation
import StoreKit

/// Mock implementation of `StoreKitCatalogProviding` for SwiftUI previews and tests.
/// Returns empty product arrays since real `Product` objects cannot be constructed
/// in tests without a StoreKit configuration. The paywall view model gracefully
/// falls back to backend-provided `StoreProductModel` data when StoreKit is unavailable.
///
/// For integration testing with real StoreKit products, use `StoreKitCatalogService`
/// with the `ProEstimate.storekit` configuration file in Xcode.
final class MockStoreKitCatalogService: StoreKitCatalogProviding {
    /// Whether `loadProducts()` should throw an error (simulating StoreKit unavailability).
    var shouldThrow: Bool

    /// Whether intro offer is eligible.
    var introOfferEligible: Bool

    /// Simulated delay in nanoseconds.
    var delayNanoseconds: UInt64

    /// Track call counts for test assertions.
    private(set) var loadProductsCallCount = 0
    private(set) var productForIdCallCount = 0
    private(set) var introOfferCheckCallCount = 0

    init(
        shouldThrow: Bool = false,
        introOfferEligible: Bool = true,
        delayNanoseconds: UInt64 = 0
    ) {
        self.shouldThrow = shouldThrow
        self.introOfferEligible = introOfferEligible
        self.delayNanoseconds = delayNanoseconds
    }

    // MARK: - StoreKitCatalogProviding

    func loadProducts() async throws -> [Product] {
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        loadProductsCallCount += 1

        if shouldThrow {
            throw StoreKitMockError.unavailable
        }

        // Real Product objects cannot be constructed manually.
        // Return an empty array — the PaywallHostViewModel will fall back
        // to backend-provided StoreProductModel data.
        return []
    }

    func product(for id: String) async throws -> Product? {
        productForIdCallCount += 1

        if shouldThrow {
            throw StoreKitMockError.unavailable
        }

        // Cannot construct mock Product objects.
        return nil
    }

    func isEligibleForIntroOffer(groupID: String) async -> Bool {
        introOfferCheckCallCount += 1
        return introOfferEligible
    }
}

// MARK: - Mock Error

/// Error type for mock StoreKit failures.
enum StoreKitMockError: Error, LocalizedError {
    case unavailable

    var errorDescription: String? {
        "StoreKit is unavailable in this environment."
    }
}
