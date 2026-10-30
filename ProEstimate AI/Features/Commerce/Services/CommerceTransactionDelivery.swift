import Foundation

/// A transaction is delivered only after the backend accepts its signed receipt.
/// Keeping this boundary independent of StoreKit also covers recovery and restore.
@MainActor
final class CommerceTransactionDelivery {
    private let commerceAPI: CommerceAPIClientProtocol
    private let entitlementStore: EntitlementStore

    init(commerceAPI: CommerceAPIClientProtocol, entitlementStore: EntitlementStore) {
        self.commerceAPI = commerceAPI
        self.entitlementStore = entitlementStore
    }

    func sync(_ request: SyncTransactionRequest, finish: () async -> Void) async throws {
        let snapshot: EntitlementSnapshot
        do {
            snapshot = try await commerceAPI.syncTransaction(request: request)
        } catch let APIError.server(code, message)
            where code == "NOT_FOUND" && message.contains("PurchaseAttempt") {
            // An existing App Store receipt can outlive a migrated purchase-attempt
            // database. Restore still verifies the signature and account ownership.
            snapshot = try await commerceAPI.restoreTransactions([
                RestoreTransactionItem(
                    storeProductId: request.storeProductId,
                    transactionId: request.transactionId,
                    originalTransactionId: request.originalTransactionId,
                    appAccountToken: request.appAccountToken,
                    environment: request.environment,
                    signedTransaction: request.signedTransaction
                )
            ])
        }
        await entitlementStore.updateFromSnapshot(snapshot)
        await finish()
    }

    func restore(_ transactions: [RestoreTransactionItem], finish: () async -> Void) async throws {
        let snapshot = try await commerceAPI.restoreTransactions(transactions)
        await entitlementStore.updateFromSnapshot(snapshot)
        await finish()
    }
}
