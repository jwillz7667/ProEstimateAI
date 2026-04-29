import Foundation

/// Protocol defining all backend API calls related to commerce and monetization.
/// Implementations include the real `CommerceAPIClient` (backed by `APIClientProtocol`)
/// and `MockCommerceAPIClient` for previews and tests.
protocol CommerceAPIClientProtocol {
    /// Fetch the product catalog from the backend.
    /// Returns enriched product models with pricing, trial eligibility, and copy.
    func fetchProducts() async throws -> [StoreProductModel]

    /// Fetch the current user's entitlement snapshot from the backend.
    /// This is the canonical source of truth for subscription state, feature flags, and usage.
    func fetchEntitlement() async throws -> EntitlementSnapshot

    /// Create a purchase attempt on the backend before initiating a StoreKit purchase.
    /// Returns an `appAccountToken` (UUID) that links the App Store transaction to the backend user.
    func createPurchaseAttempt(productId: String, placement: PaywallPlacement?) async throws -> PurchaseAttemptResponse

    /// Sync a verified StoreKit transaction to the backend.
    /// The backend validates the transaction with Apple and updates the user's entitlement.
    /// Returns the updated entitlement snapshot.
    func syncTransaction(request: SyncTransactionRequest) async throws -> EntitlementSnapshot

    /// Restore previously purchased transactions on the backend.
    /// Posts every verified `Transaction.currentEntitlements` item so the backend
    /// can re-bind them to the current user. Returns the refreshed entitlement snapshot.
    func restoreTransactions(_ transactions: [RestoreTransactionItem]) async throws -> EntitlementSnapshot

    /// Consume one unit of a metered usage bucket (e.g., AI generation, quote export).
    /// Returns the updated usage bucket with decremented remaining quantity.
    func consumeUsage(metric: UsageMetricCode) async throws -> UsageBucket
}

// MARK: - Request / Response Types

/// Response from `POST /v1/commerce/purchase-attempt`.
/// The `appAccountToken` is a UUID string that must be passed to StoreKit's
/// `Product.purchase(options:)` to link the Apple transaction to the backend user.
struct PurchaseAttemptResponse: Codable, Sendable {
    let purchaseAttemptId: String
    let appAccountToken: String

    enum CodingKeys: String, CodingKey {
        case purchaseAttemptId = "purchase_attempt_id"
        case appAccountToken = "app_account_token"
    }
}

/// Request body for `POST /v1/commerce/transactions/sync`.
/// Sent after a successful StoreKit purchase to reconcile the transaction on the backend.
///
/// `signedTransaction` is the `jwsRepresentation` from `VerificationResult<Transaction>` —
/// a JWS chained to Apple Root CA G3 that the backend re-verifies before
/// flipping the entitlement. The other fields are convenience scalars
/// for the backend's own bookkeeping; the JWS is the trust anchor.
struct SyncTransactionRequest: Codable, Sendable {
    let purchaseAttemptId: String
    let storeProductId: String
    let transactionId: String
    let originalTransactionId: String
    let appAccountToken: String
    let environment: String
    let signedTransaction: String

    enum CodingKeys: String, CodingKey {
        case purchaseAttemptId = "purchase_attempt_id"
        case storeProductId = "store_product_id"
        case transactionId = "transaction_id"
        case originalTransactionId = "original_transaction_id"
        case appAccountToken = "app_account_token"
        case environment
        case signedTransaction = "signed_transaction"
    }
}

/// Request body for creating a purchase attempt.
struct CreatePurchaseAttemptBody: Encodable, Sendable {
    let productId: String
    let placement: String?

    enum CodingKeys: String, CodingKey {
        case productId = "product_id"
        case placement
    }
}

/// Request body for consuming a usage metric.
struct ConsumeUsageBody: Encodable, Sendable {
    let metricCode: String

    enum CodingKeys: String, CodingKey {
        case metricCode = "metric_code"
    }
}

/// Request body for `POST /v1/commerce/restore`.
/// Sent during a Restore Purchases flow with every verified entitlement transaction.
struct RestoreTransactionsRequest: Encodable, Sendable {
    let transactions: [RestoreTransactionItem]
}

/// One transaction item inside a restore request. `signedTransaction`
/// carries the Apple-signed JWS payload (from `VerificationResult.jwsRepresentation`)
/// so the backend can authenticate every restored entitlement against
/// Apple Root CA G3 before granting Pro access.
struct RestoreTransactionItem: Codable, Sendable {
    let storeProductId: String
    let transactionId: String
    let originalTransactionId: String
    let appAccountToken: String?
    let environment: String
    let signedTransaction: String

    enum CodingKeys: String, CodingKey {
        case storeProductId = "store_product_id"
        case transactionId = "transaction_id"
        case originalTransactionId = "original_transaction_id"
        case appAccountToken = "app_account_token"
        case environment
        case signedTransaction = "signed_transaction"
    }
}
