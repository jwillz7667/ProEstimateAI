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

            // Round-trip assertion: the verified transaction MUST carry the
            // exact appAccountToken we passed in `options`. A mismatch means
            // the OS-level Apple ID didn't accept our token (typically
            // because the user is signed into a different Apple ID at the
            // App Store level than the ProEstimate account they authenticated
            // as) — the backend would reject the sync anyway, but failing
            // fast lets us surface a clear, actionable message and avoid
            // finishing a transaction the backend will refuse to honour.
            guard let returnedToken = transaction.appAccountToken,
                  returnedToken == appAccountToken
            else {
                logger.error("appAccountToken round-trip failed. expected=\(appAccountToken.uuidString) got=\(transaction.appAccountToken?.uuidString ?? "nil")")
                // Finish so Apple stops redelivering this exact transaction.
                // The user resolves the account mismatch and can retry; the
                // next purchase mints a fresh appAccountToken via the
                // backend so there's no risk of replaying this one.
                await transaction.finish()
                throw PurchaseError.accountMismatch
            }

            // Sync the transaction to the backend for server-side validation.
            // The Apple-signed JWS rides along so the backend can re-verify
            // the chain against Apple Root CA G3 before flipping entitlement.
            // `syncTransactionToBackend` re-throws unrecoverable errors
            // (account mismatch) so the caller can render a specific UI.
            try await syncTransactionToBackend(
                transaction: transaction,
                signedJWS: verification.jwsRepresentation,
                appAccountToken: appAccountToken
            )

            // Finish the transaction to acknowledge it to the App Store.
            await transaction.finish()
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

        // 2. Iterate every verified current entitlement and post to the backend.
        var items: [RestoreTransactionItem] = []
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try verifyTransaction(result)
                items.append(
                    makeRestoreItem(
                        from: transaction,
                        signedJWS: result.jwsRepresentation
                    )
                )
                await transaction.finish()
            } catch {
                logger.warning("Skipping unverified transaction in restore: \(error.localizedDescription)")
            }
        }

        // 3. Post every collected transaction to the backend so it can re-bind to this user.
        if !items.isEmpty {
            do {
                let snapshot = try await commerceAPI.restoreTransactions(items)
                await entitlementStore.updateFromSnapshot(snapshot)
                logger.info("Restore synced \(items.count) transaction(s) to backend. New state: \(snapshot.subscriptionState.rawValue)")
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

                // Only sync to backend when the transaction carries the
                // appAccountToken that was minted by our PurchaseAttempt
                // flow. Renewals and out-of-band transactions (Family
                // Sharing, restored on a different device) often arrive
                // with a nil token; sending a random UUID would just make
                // the backend's `PurchaseAttempt` lookup miss and the
                // sync silently fail. App Store Server Notifications
                // remain the authoritative reconciliation path for those
                // — we just refresh locally so the UI catches up.
                if let appAccountToken = transaction.appAccountToken {
                    do {
                        try await syncTransactionToBackend(
                            transaction: transaction,
                            signedJWS: result.jwsRepresentation,
                            appAccountToken: appAccountToken
                        )
                    } catch {
                        // The listener path can't surface UI; just log so
                        // ops can investigate. Finishing below stops Apple
                        // from infinitely redelivering. Eventual webhook
                        // reconciliation handles legitimate renewals.
                        logger.error("Listener sync failed: \(error.localizedDescription)")
                    }
                }

                await transaction.finish()
                await entitlementStore.refresh()
            } catch {
                logger.error("Transaction update verification failed: \(error.localizedDescription)")
                // Even on verification failure, pull a fresh entitlement
                // so the UI reflects whatever the backend now believes.
                await entitlementStore.refresh()
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
    /// Re-throws ONLY the unrecoverable errors that need explicit user
    /// action — most prominently `accountMismatch`, where the backend
    /// has refused to bind this transaction to the authenticated user.
    /// Transient failures (network blips, idempotency races, server
    /// hiccups) are absorbed and a fresh entitlement snapshot is pulled
    /// from the canonical endpoint instead; App Store Server
    /// Notifications remain the eventual-consistency safety net.
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
            let updatedSnapshot = try await commerceAPI.syncTransaction(request: request)
            await entitlementStore.updateFromSnapshot(updatedSnapshot)
            logger.info("Transaction synced to backend. New state: \(updatedSnapshot.subscriptionState.rawValue)")
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
            throw PurchaseError.network(message)
        } catch {
            logger.warning("Failed to sync transaction to backend: \(error.localizedDescription). Falling back to direct entitlement refresh.")
            await entitlementStore.refresh()
            // Transient — don't re-throw. ASSN + the next launch refresh
            // will reconcile any drift; failing the purchase here would
            // confuse a user whose payment Apple already authorized.
        }
    }
}
