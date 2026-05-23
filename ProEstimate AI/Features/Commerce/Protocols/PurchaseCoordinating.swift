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

    /// In-app purchases are not allowed on this device or for this Apple ID
    /// (parental controls, MDM restrictions, country/region not supported).
    case paymentsNotAllowed

    /// The OS-level Apple ID does not match the ProEstimate account that
    /// initiated this purchase. Either the local `appAccountToken` round-trip
    /// failed, or the backend rejected the transaction with `ACCOUNT_MISMATCH`.
    /// User must sign in with the matching Apple ID, or use Restore Purchases.
    case accountMismatch

    /// The Apple subscription is already bound to a *different* ProEstimate
    /// account with an active entitlement. Distinct from `accountMismatch`:
    /// here the device's Apple ID is fine, but the ProEstimate user trying
    /// to claim it is the wrong one. Restore won't help — it would just hit
    /// the same wall — so the only recovery is signing into the ProEstimate
    /// account that owns the subscription, or contacting support.
    case subscriptionBoundToOtherUser

    /// A network error occurred during the purchase round-trip. Retryable.
    case network(String)

    /// A wrapped StoreKit error for unexpected failures.
    case storeKitError(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return String(localized: "purchase.error.cancelled", defaultValue: "Purchase was cancelled.")
        case .pending:
            return String(localized: "purchase.error.pending.message", defaultValue: "Your purchase is pending approval.")
        case .unverified:
            return String(localized: "purchase.error.unverified.message", defaultValue: "The transaction could not be verified. Please try again.")
        case .productNotFound:
            return String(localized: "purchase.error.product_not_found.message", defaultValue: "The selected plan is unavailable right now. Please try again.")
        case .paymentsNotAllowed:
            return String(
                localized: "purchase.error.payments_not_allowed.message",
                defaultValue: "This Apple ID can't make purchases. Check Screen Time restrictions in Settings, or sign in with an account that supports In-App Purchases."
            )
        case .accountMismatch:
            return String(
                localized: "purchase.error.account_mismatch.message",
                defaultValue: "We detected a different Apple ID than the one linked to your ProEstimate account. Sign out of the other Apple ID in Settings → App Store, or tap Restore Purchases if you've already subscribed."
            )
        case .subscriptionBoundToOtherUser:
            return String(
                localized: "purchase.error.subscription_bound_to_other_user.message",
                defaultValue: "This Apple subscription is linked to a different ProEstimate account. Sign in to that account to access Pro features, or contact support if you need help."
            )
        case .network(let detail):
            return String(
                localized: "purchase.error.network.message",
                defaultValue: "Couldn't reach our servers. Check your connection and try again."
            ) + " (\(detail))"
        case .storeKitError(let message):
            return String(localized: "purchase.error.unknown.message", defaultValue: "Purchase failed: \(message)")
        }
    }
}
