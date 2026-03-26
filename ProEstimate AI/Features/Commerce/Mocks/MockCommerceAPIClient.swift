import Foundation

/// Mock implementation of `CommerceAPIClientProtocol` for SwiftUI previews and tests.
/// Returns sample entitlement (free tier with 2/3 generations, 3/3 quotes remaining)
/// and sample products. Includes configurable delay and error injection.
final class MockCommerceAPIClient: CommerceAPIClientProtocol {
    /// Simulated network delay in nanoseconds. Defaults to 300ms.
    var delayNanoseconds: UInt64

    /// When set, all methods will throw this error.
    var forcedError: Error?

    /// The entitlement snapshot to return from `fetchEntitlement()`.
    var entitlementSnapshot: EntitlementSnapshot

    /// The products to return from `fetchProducts()`.
    var products: [StoreProductModel]

    /// The purchase attempt response to return.
    var purchaseAttemptResponse: PurchaseAttemptResponse

    /// Track which methods were called (for test assertions).
    private(set) var fetchProductsCallCount = 0
    private(set) var fetchEntitlementCallCount = 0
    private(set) var createPurchaseAttemptCallCount = 0
    private(set) var syncTransactionCallCount = 0
    private(set) var consumeUsageCallCount = 0
    private(set) var lastConsumedMetric: UsageMetricCode?

    init(
        delayNanoseconds: UInt64 = 300_000_000,
        entitlementSnapshot: EntitlementSnapshot = .sampleFree,
        products: [StoreProductModel] = [.sampleMonthly, .sampleAnnual]
    ) {
        self.delayNanoseconds = delayNanoseconds
        self.entitlementSnapshot = entitlementSnapshot
        self.products = products
        self.purchaseAttemptResponse = PurchaseAttemptResponse(
            purchaseAttemptId: UUID().uuidString,
            appAccountToken: UUID().uuidString
        )
    }

    // MARK: - CommerceAPIClientProtocol

    func fetchProducts() async throws -> [StoreProductModel] {
        try await simulateDelay()
        fetchProductsCallCount += 1
        if let error = forcedError { throw error }
        return products
    }

    func fetchEntitlement() async throws -> EntitlementSnapshot {
        try await simulateDelay()
        fetchEntitlementCallCount += 1
        if let error = forcedError { throw error }
        return entitlementSnapshot
    }

    func createPurchaseAttempt(
        productId: String,
        placement: PaywallPlacement?
    ) async throws -> PurchaseAttemptResponse {
        try await simulateDelay()
        createPurchaseAttemptCallCount += 1
        if let error = forcedError { throw error }
        return purchaseAttemptResponse
    }

    func syncTransaction(request: SyncTransactionRequest) async throws -> EntitlementSnapshot {
        try await simulateDelay()
        syncTransactionCallCount += 1
        if let error = forcedError { throw error }

        // After sync, return a Pro entitlement.
        return .samplePro
    }

    func consumeUsage(metric: UsageMetricCode) async throws -> UsageBucket {
        try await simulateDelay()
        consumeUsageCallCount += 1
        lastConsumedMetric = metric
        if let error = forcedError { throw error }

        // Return a decremented bucket based on the current snapshot.
        let currentBucket = entitlementSnapshot.usage.first { $0.metricCode == metric }

        let remaining = max(0, (currentBucket?.remainingQuantity ?? 1) - 1)
        let consumed = (currentBucket?.consumedQuantity ?? 0) + 1
        let included = currentBucket?.includedQuantity ?? AppConstants.freeGenerationCredits

        return UsageBucket(
            metricCode: metric,
            includedQuantity: included,
            consumedQuantity: consumed,
            remainingQuantity: remaining,
            source: "free_starter"
        )
    }

    // MARK: - Delay

    private func simulateDelay() async throws {
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
    }
}
