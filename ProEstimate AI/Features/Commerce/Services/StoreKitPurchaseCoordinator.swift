import Foundation
import StoreKit
import os.log

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

        // Attempt the StoreKit purchase with the app account token.
        let result: Product.PurchaseResult
        do {
            var options: Set<Product.PurchaseOption> = [
                .appAccountToken(appAccountToken)
            ]

            // Ensure the purchase is associated with the correct subscription group window.
            _ = options // Silence unused warning — options set is passed below.

            result = try await product.purchase(options: options)
        } catch {
            logger.error("StoreKit purchase failed: \(error.localizedDescription)")
            throw PurchaseError.storeKitError(error.localizedDescription)
        }

        // Handle the purchase result.
        switch result {
        case .success(let verification):
            let transaction = try verifyTransaction(verification)
            logger.info("Purchase verified. Transaction ID: \(transaction.id)")

            // Sync the transaction to the backend for server-side validation.
            await syncTransactionToBackend(
                transaction: transaction,
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
                items.append(makeRestoreItem(from: transaction))
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
            } catch {
                logger.error("Backend restore sync failed: \(error.localizedDescription)")
                // Still refresh in case backend reconciled via ASSN.
                await entitlementStore.refresh()
                throw PurchaseError.storeKitError(error.localizedDescription)
            }
        } else {
            // No transactions on file — pull a fresh snapshot anyway so UI updates.
            await entitlementStore.refresh()
            logger.info("No current entitlements to restore.")
        }
    }

    /// Build a `RestoreTransactionItem` from a verified StoreKit `Transaction`.
    private func makeRestoreItem(from transaction: Transaction) -> RestoreTransactionItem {
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
            environment: environment
        )
    }

    func listenForTransactions() async {
        logger.info("Starting transaction listener...")

        for await result in Transaction.updates {
            do {
                let transaction = try verifyTransaction(result)
                logger.info("Transaction update received: \(transaction.id), product: \(transaction.productID)")

                // Sync the updated transaction to the backend.
                await syncTransactionToBackend(
                    transaction: transaction,
                    appAccountToken: transaction.appAccountToken ?? UUID()
                )

                // Finish the transaction.
                await transaction.finish()

                // Refresh local entitlement state.
                await entitlementStore.refresh()
            } catch {
                logger.error("Transaction update verification failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Transaction Verification

    /// Verify a StoreKit transaction using on-device verification.
    /// Throws `PurchaseError.unverified` if the transaction fails verification.
    private func verifyTransaction(_ result: VerificationResult<Transaction>) throws -> Transaction {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified(_, let error):
            logger.error("Transaction verification failed: \(error.localizedDescription)")
            throw PurchaseError.unverified
        }
    }

    // MARK: - Backend Sync

    /// Sync a verified transaction to the backend for server-side reconciliation.
    /// Non-throwing — failures are logged but do not block the purchase flow.
    /// The backend will eventually reconcile via App Store Server Notifications.
    private func syncTransactionToBackend(
        transaction: Transaction,
        appAccountToken: UUID
    ) async {
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
            environment: environment
        )

        do {
            let updatedSnapshot = try await commerceAPI.syncTransaction(request: request)
            await entitlementStore.updateFromSnapshot(updatedSnapshot)
            logger.info("Transaction synced to backend. New state: \(updatedSnapshot.subscriptionState.rawValue)")
        } catch {
            // Non-fatal: the backend will reconcile via App Store Server Notifications.
            logger.warning("Failed to sync transaction to backend: \(error.localizedDescription). Will reconcile via ASSN.")
        }
    }
}
