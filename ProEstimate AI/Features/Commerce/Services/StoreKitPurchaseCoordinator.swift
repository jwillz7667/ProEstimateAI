import Foundation
import os.log
import StoreKit

/// Production implementation of `PurchaseCoordinating`.
/// Orchestrates the full purchase lifecycle:
/// 1. Create a purchase attempt on the backend (obtain `appAccountToken`)
/// 2. Call `Product.purchase(options:)` with the `appAccountToken`
/// 3. Verify the transaction locally
/// 4. Sync the verified transaction to the backend
/// 5. Update the local entitlement store
///
/// Also listens for `Transaction.updates` to handle renewals, revocations,
/// and other server-side transaction events.
final class StoreKitPurchaseCoordinator: PurchaseCoordinating {
    private let commerceAPI: CommerceAPIClientProtocol
    private let entitlementStore: EntitlementStore
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "PurchaseCoordinator")

    init(
        commerceAPI: CommerceAPIClientProtocol,
        entitlementStore: EntitlementStore
    ) {
        self.commerceAPI = commerceAPI
        self.entitlementStore = entitlementStore
    }

    // MARK: - PurchaseCoordinating

    func purchase(product: Product, appAccountToken: UUID) async throws -> Transaction {
        logger.info("Initiating purchase for product: \(product.id) with token: \(appAccountToken.uuidString)")

        // Pre-flight: confirm the device + Apple ID can transact at all.
        // `AppStore.canMakePayments` is false when the device has parental
        // controls / Screen Time blocking purchases, an MDM-managed device
        // disables the App Store, or the account region/type doesn't support
        // IAP. Without this guard, `Product.purchase()` either silently
        // returns nothing or throws an opaque error and the user sees a
        // frozen paywall — exactly the symptom the bug report describes.
        guard AppStore.canMakePayments else {
            logger.error("AppStore.canMakePayments == false; aborting purchase before StoreKit prompt.")
            throw PurchaseError.paymentsNotAllowed
        }

        // Diagnostic-only: capture the active Storefront so support can
        // disambiguate "wrong Apple ID" from "supported region but the
        // account is blocked". Storefront reflects the App Store account,
        // not the iCloud account — they can differ on a single device.
        if let storefront = await Storefront.current {
            logger.info("Active Storefront: country=\(storefront.countryCode) id=\(storefront.id)")
        } else {
            logger.warning("No active Storefront — App Store account may not be signed in.")
        }

        // Attempt the StoreKit purchase with the app account token.
        let result: Product.PurchaseResult
        do {
            let options: Set<Product.PurchaseOption> = [
                .appAccountToken(appAccountToken),
            ]
            result = try await product.purchase(options: options)
        } catch {
            logger.error("StoreKit purchase failed: \(error.localizedDescription)")
            throw mapStoreKitError(error)
        }

        // Handle the purchase result.
        switch result {
        case let .success(verification):
            let transaction = try verifyTransaction(verification)
            logger.info("Purchase verified. Transaction ID: \(transaction.id)")

            // Existing subscriptions can retain a token from an earlier purchase.
            // The server validates signed ownership; a new attempt UUID alone
            // cannot establish that the customer's Apple Account changed.
            try await deliver(transaction, signedJWS: verification.jwsRepresentation)
            logger.info("Transaction finished: \(transaction.id)")

            return transaction

        case .userCancelled:
            logger.info("User cancelled purchase for product: \(product.id)")
            throw PurchaseError.cancelled

        case .pending:
            logger.info("Purchase pending for product: \(product.id)")
            throw PurchaseError.pending

        @unknown default:
            logger.error("Unknown purchase result for product: \(product.id)")
            throw PurchaseError.storeKitError("Unknown purchase result")
        }
    }

    /// Map a raw StoreKit purchase error to a `PurchaseError`. StoreKit 2
    /// surfaces `StoreKitError` for many failure modes; pulling out the
    /// well-known cases lets the UI render specific copy instead of a
    /// generic "something went wrong".
    private func mapStoreKitError(_ error: Error) -> PurchaseError {
        if let storeKitError = error as? StoreKitError {
            switch storeKitError {
            case .userCancelled:
                return .cancelled
            case .networkError:
                return .network(storeKitError.localizedDescription)
            case .notAvailableInStorefront, .notEntitled:
                return .paymentsNotAllowed
            default:
                return .storeKitError(storeKitError.localizedDescription)
            }
        }
        if let purchaseError = error as? Product.PurchaseError {
            switch purchaseError {
            case .ineligibleForOffer, .invalidQuantity, .productUnavailable:
                return .productNotFound
            default:
                return .storeKitError(purchaseError.localizedDescription)
            }
        }
        return .storeKitError(error.localizedDescription)
    }

    func restorePurchases() async throws {
        logger.info("Restoring purchases...")

        do {
            // 1. Ask the App Store to refresh local transaction state.
            try await AppStore.sync()
            logger.info("App Store sync completed. Collecting current entitlements.")
        } catch {
            logger.error("AppStore.sync failed: \(error.localizedDescription)")
            throw PurchaseError.storeKitError(error.localizedDescription)
        }

        try await restoreCurrentEntitlements()
    }

    /// Current entitlements include finished purchases that an unfinished-only
    /// retry cannot recover after the backend's purchase records were migrated.
    func reconcileCurrentEntitlements() async {
        do {
            try await restoreCurrentEntitlements()
        } catch {
            // A quiet login reconciliation never blocks basic account access.
            // The explicit Restore Purchases action surfaces recovery errors.
            logger.warning("Existing subscription reconciliation pending: \(error.localizedDescription)")
        }
    }

    private func restoreCurrentEntitlements() async throws {
        // Iterate verified current receipts without requesting AppStore.sync.

        var items: [RestoreTransactionItem] = []
        var verifiedTransactions: [Transaction] = []
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try verifyTransaction(result)
                items.append(
                    makeRestoreItem(
                        from: transaction,
                        signedJWS: result.jwsRepresentation
                    )
                )
                verifiedTransactions.append(transaction)
            } catch {
                logger.warning("Skipping unverified transaction in restore: \(error.localizedDescription)")
            }
        }

        // 3. Post every collected transaction to the backend so it can re-bind to this user.
        if !items.isEmpty {
            do {
                let delivery = CommerceTransactionDelivery(commerceAPI: commerceAPI, entitlementStore: entitlementStore)
                try await delivery.restore(items) {
                    for transaction in verifiedTransactions { await transaction.finish() }
                }
                logger.info("Restore synced \(items.count) transaction(s) to backend.")
            } catch let APIError.server(code, message) where code == "SUBSCRIPTION_BOUND_TO_OTHER_USER" {
                logger.error("Restore rejected — subscription owned by another ProEstimate user: \(message)")
                await entitlementStore.refresh()
                throw PurchaseError.subscriptionBoundToOtherUser
            } catch let APIError.server(code, message) where code == "ACCOUNT_MISMATCH" {
                // The restore endpoint doesn't currently emit this code,
                // but mirror the sync path so any future tightening lands
                // in the right alert without another iOS round-trip.
                logger.error("Restore rejected with ACCOUNT_MISMATCH: \(message)")
                await entitlementStore.refresh()
                throw PurchaseError.accountMismatch
            } catch let APIError.network(message) {
                logger.warning("Network error during restore: \(message). Falling back to direct entitlement refresh.")
                await entitlementStore.refresh()
                throw PurchaseError.network(message)
            } catch {
                logger.error("Backend restore sync failed: \(error.localizedDescription)")
                await entitlementStore.refresh()
                throw PurchaseError.storeKitError(error.localizedDescription)
            }
        } else {
            // No transactions on file — pull a fresh snapshot anyway so UI updates.
            await entitlementStore.refresh()
            logger.info("No current entitlements to restore.")
        }
    }

    /// Build a `RestoreTransactionItem` from a verified StoreKit
    /// `Transaction` and the JWS string produced by Apple's verification
    /// pipeline. The backend re-verifies that JWS against Apple Root CA
    /// G3 before granting access — the bare scalars here are convenience
    /// for bookkeeping, not the trust anchor.
    private func makeRestoreItem(
        from transaction: Transaction,
        signedJWS: String
    ) -> RestoreTransactionItem {
        let environment: String = {
            switch transaction.environment {
            case .sandbox: return "sandbox"
            case .production: return "production"
            case .xcode: return "xcode"
            default: return "unknown"
            }
        }()

        return RestoreTransactionItem(
            storeProductId: transaction.productID,
            transactionId: String(transaction.id),
            originalTransactionId: String(transaction.originalID),
            appAccountToken: transaction.appAccountToken?.uuidString,
            environment: environment,
            signedTransaction: signedJWS
        )
    }

    func listenForTransactions() async {
        logger.info("Starting transaction listener...")

        for await result in Transaction.updates {
            do {
                let transaction = try verifyTransaction(result)
                logger.info("Transaction update received: \(transaction.id), product: \(transaction.productID)")

                try await deliver(transaction, signedJWS: result.jwsRepresentation)
                await entitlementStore.refresh()
            } catch {
                logger.error("Transaction update could not be delivered: \(error.localizedDescription)")
                // Even on verification failure, pull a fresh entitlement
                // so the UI reflects whatever the backend now believes.
                await entitlementStore.refresh()
            }
        }
    }

    func reconcileUnfinishedTransactions() async {
        for await result in Transaction.unfinished {
            do {
                let transaction = try verifyTransaction(result)
                try await deliver(transaction, signedJWS: result.jwsRepresentation)
            } catch {
                // Keep the receipt unfinished so a later authenticated retry
                // can deliver it after an outage or an account correction.
                logger.warning("Unfinished purchase still awaiting delivery: \(error.localizedDescription)")
            }
        }
    }

    private func deliver(_ transaction: Transaction, signedJWS: String) async throws {
        if let token = transaction.appAccountToken {
            try await syncTransactionToBackend(transaction: transaction, signedJWS: signedJWS, appAccountToken: token)
        } else {
            let delivery = CommerceTransactionDelivery(commerceAPI: commerceAPI, entitlementStore: entitlementStore)
            do {
                try await delivery.restore([makeRestoreItem(from: transaction, signedJWS: signedJWS)]) {
                    await transaction.finish()
                }
            } catch let APIError.server(code, _) where code == "SUBSCRIPTION_BOUND_TO_OTHER_USER" {
                throw PurchaseError.subscriptionBoundToOtherUser
            } catch let APIError.server(code, _) where code == "ACCOUNT_MISMATCH" {
                throw PurchaseError.accountMismatch
            } catch {
                throw PurchaseError.deliveryPending
            }
        }
    }

    // MARK: - Transaction Verification

    /// Verify a StoreKit transaction using on-device verification.
    /// Throws `PurchaseError.unverified` if the transaction fails verification.
    private func verifyTransaction(_ result: VerificationResult<Transaction>) throws -> Transaction {
        switch result {
        case let .verified(transaction):
            return transaction
        case let .unverified(_, error):
            logger.error("Transaction verification failed: \(error.localizedDescription)")
            throw PurchaseError.unverified
        }
    }

    // MARK: - Backend Sync

    /// Sync a verified transaction to the backend for server-side
    /// reconciliation.
    ///
    /// Failed syncs remain unfinished. Ownership failures request account
    /// recovery; transport and server failures request receipt delivery retry.
    private func syncTransactionToBackend(
        transaction: Transaction,
        signedJWS: String,
        appAccountToken: UUID
    ) async throws {
        let environment: String = {
            switch transaction.environment {
            case .sandbox: return "sandbox"
            case .production: return "production"
            case .xcode: return "xcode"
            default: return "unknown"
            }
        }()

        let request = SyncTransactionRequest(
            purchaseAttemptId: appAccountToken.uuidString,
            storeProductId: transaction.productID,
            transactionId: String(transaction.id),
            originalTransactionId: String(transaction.originalID),
            appAccountToken: appAccountToken.uuidString,
            environment: environment,
            signedTransaction: signedJWS
        )

        do {
            let delivery = CommerceTransactionDelivery(commerceAPI: commerceAPI, entitlementStore: entitlementStore)
            try await delivery.sync(request) { await transaction.finish() }
            logger.info("Transaction synced to backend.")
        } catch let APIError.server(code, message) where code == "ACCOUNT_MISMATCH" {
            logger.error("Backend rejected transaction with ACCOUNT_MISMATCH: \(message)")
            // Refresh so the UI reflects whatever entitlement the backend
            // currently believes — then propagate so the caller can route
            // the user into the recovery flow (sign out / restore).
            await entitlementStore.refresh()
            throw PurchaseError.accountMismatch
        } catch let APIError.server(code, message) where code == "SUBSCRIPTION_BOUND_TO_OTHER_USER" {
            logger.error("Backend rejected transaction — subscription owned by another ProEstimate user: \(message)")
            // Pull the canonical entitlement (the user remains FREE on this
            // account) and propagate so the paywall can render the
            // dedicated alert. Restore would just hit the same wall, so
            // we don't suggest it.
            await entitlementStore.refresh()
            throw PurchaseError.subscriptionBoundToOtherUser
        } catch let APIError.network(message) {
            logger.warning("Network error syncing transaction: \(message). Falling back to direct entitlement refresh.")
            await entitlementStore.refresh()
            throw PurchaseError.deliveryPending
        } catch {
            logger.warning("Failed to sync transaction to backend: \(error.localizedDescription). Falling back to direct entitlement refresh.")
            await entitlementStore.refresh()
            throw PurchaseError.deliveryPending
        }
    }
}
