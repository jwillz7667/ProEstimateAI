import Foundation
import StoreKit

/// Protocol abstracting the StoreKit 2 purchase and transaction management flow.
/// The real implementation handles `Product.purchase(options:)`, transaction verification,
/// and `Transaction.updates` listening. Mock implementations can simulate purchase
/// outcomes for previews and tests.
protocol PurchaseCoordinating: Sendable {
    /// Initiate a purchase for the given StoreKit product.
    /// - Parameters:
    ///   - product: The StoreKit `Product` to purchase.
    ///   - appAccountToken: A UUID linking the transaction to the backend user.
    /// - Returns: The verified `Transaction` on success.
    /// - Throws: `PurchaseError` if the purchase fails, is cancelled, or pending.
    func purchase(product: Product, appAccountToken: UUID) async throws -> Transaction

    /// Restore previously purchased transactions.
    /// Triggers StoreKit to re-sync all transactions for the current Apple ID.
    func restorePurchases() async throws

    /// Begin listening for transaction updates (renewals, revocations, refunds).
    /// This should be called once at app launch and run indefinitely.
    func listenForTransactions() async
}

// MARK: - Purchase Errors

/// Errors specific to the StoreKit purchase flow.
/// These are thrown by `PurchaseCoordinating` implementations and handled
/// by the paywall view model to show appropriate UI.
enum PurchaseError: Error, LocalizedError, Sendable {
    /// The user cancelled the purchase dialog.
    case cancelled

    /// The purchase is pending (e.g., Ask to Buy, requires approval).
    case pending

    /// StoreKit returned an unverified transaction — possible tampering.
    case unverified

    /// The StoreKit product could not be found.
    case productNotFound

    /// A wrapped StoreKit error for unexpected failures.
    case storeKitError(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Purchase was cancelled."
        case .pending:
            return "Your purchase is pending approval."
        case .unverified:
            return "The transaction could not be verified. Please try again."
        case .productNotFound:
            return "The requested product was not found."
        case .storeKitError(let message):
            return "Purchase failed: \(message)"
        }
    }
}
