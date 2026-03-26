import Foundation
import Observation
import os.log

/// Tracks metered usage credits (AI generations, quote exports) for the current user.
/// Reads initial values from `EntitlementStore`'s snapshot and decrements locally
/// on each consumption, with backend confirmation.
///
/// The store auto-syncs from the entitlement snapshot on refresh, so values
/// stay consistent with the backend's canonical usage ledger.
@Observable
final class UsageMeterStore {
    // MARK: - Shared Instance

    static let shared = UsageMeterStore()

    // MARK: - Published State

    /// Remaining AI generation credits.
    private(set) var generationsRemaining: Int = 0

    /// Remaining quote export credits.
    private(set) var quotesRemaining: Int = 0

    /// Total included AI generation credits (for progress bar denominator).
    private(set) var generationsTotal: Int = 0

    /// Total included quote export credits (for progress bar denominator).
    private(set) var quotesTotal: Int = 0

    /// Whether a usage consumption is in progress.
    private(set) var isConsuming: Bool = false

    // MARK: - Dependencies

    private var commerceAPI: CommerceAPIClientProtocol?
    private var entitlementStore: EntitlementStore?
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "UsageMeter")

    // MARK: - Init

    init() {}

    /// Configure the store with its dependencies.
    /// Call once during app initialization.
    func configure(
        commerceAPI: CommerceAPIClientProtocol,
        entitlementStore: EntitlementStore
    ) {
        self.commerceAPI = commerceAPI
        self.entitlementStore = entitlementStore
    }

    // MARK: - Computed Properties

    /// Whether the user has any AI generation credits remaining.
    var canGenerate: Bool {
        // Pro users have unlimited credits.
        if entitlementStore?.hasProAccess == true { return true }
        return generationsRemaining > 0
    }

    /// Whether the user has any quote export credits remaining.
    var canExportQuote: Bool {
        // Pro users have unlimited credits.
        if entitlementStore?.hasProAccess == true { return true }
        return quotesRemaining > 0
    }

    /// Progress fraction for AI generations (0.0 to 1.0).
    var generationsProgress: Double {
        guard generationsTotal > 0 else { return 0 }
        return Double(generationsRemaining) / Double(generationsTotal)
    }

    /// Progress fraction for quote exports (0.0 to 1.0).
    var quotesProgress: Double {
        guard quotesTotal > 0 else { return 0 }
        return Double(quotesRemaining) / Double(quotesTotal)
    }

    // MARK: - Actions

    /// Sync usage values from the current entitlement snapshot.
    /// Called after entitlement refresh to keep meters in sync.
    func refresh() async {
        guard let entitlementStore, let snapshot = entitlementStore.snapshot else {
            logger.warning("UsageMeterStore.refresh() called without entitlement snapshot. Skipping.")
            return
        }

        // If user has Pro access, usage is unlimited — set high values.
        if snapshot.subscriptionState.hasProAccess {
            generationsRemaining = Int.max
            quotesRemaining = Int.max
            generationsTotal = Int.max
            quotesTotal = Int.max
            return
        }

        // Extract usage from entitlement snapshot.
        if let genBucket = snapshot.usage.first(where: { $0.metricCode == .aiGeneration }) {
            generationsRemaining = genBucket.remainingQuantity
            generationsTotal = genBucket.includedQuantity
        } else {
            generationsRemaining = AppConstants.freeGenerationCredits
            generationsTotal = AppConstants.freeGenerationCredits
        }

        if let quoteBucket = snapshot.usage.first(where: { $0.metricCode == .quoteExport }) {
            quotesRemaining = quoteBucket.remainingQuantity
            quotesTotal = quoteBucket.includedQuantity
        } else {
            quotesRemaining = AppConstants.freeQuoteExportCredits
            quotesTotal = AppConstants.freeQuoteExportCredits
        }

        logger.info("Usage refreshed. Generations: \(self.generationsRemaining)/\(self.generationsTotal), Quotes: \(self.quotesRemaining)/\(self.quotesTotal)")
    }

    /// Consume one AI generation credit.
    /// Decrements locally first (optimistic), then confirms with the backend.
    /// If the backend rejects, the local count is corrected.
    @discardableResult
    func consumeGeneration() async throws -> UsageBucket {
        guard let commerceAPI else {
            throw APIError.unknown("UsageMeterStore not configured")
        }

        isConsuming = true
        defer { isConsuming = false }

        // Optimistic local decrement.
        if generationsRemaining > 0 && generationsRemaining != Int.max {
            generationsRemaining -= 1
        }

        do {
            let updatedBucket = try await commerceAPI.consumeUsage(metric: .aiGeneration)
            generationsRemaining = updatedBucket.remainingQuantity
            generationsTotal = updatedBucket.includedQuantity
            logger.info("Generation consumed. Remaining: \(updatedBucket.remainingQuantity)")
            return updatedBucket
        } catch {
            // Revert optimistic decrement on failure.
            await refresh()
            logger.error("Failed to consume generation: \(error.localizedDescription)")
            throw error
        }
    }

    /// Consume one quote export credit.
    /// Decrements locally first (optimistic), then confirms with the backend.
    @discardableResult
    func consumeQuoteExport() async throws -> UsageBucket {
        guard let commerceAPI else {
            throw APIError.unknown("UsageMeterStore not configured")
        }

        isConsuming = true
        defer { isConsuming = false }

        // Optimistic local decrement.
        if quotesRemaining > 0 && quotesRemaining != Int.max {
            quotesRemaining -= 1
        }

        do {
            let updatedBucket = try await commerceAPI.consumeUsage(metric: .quoteExport)
            quotesRemaining = updatedBucket.remainingQuantity
            quotesTotal = updatedBucket.includedQuantity
            logger.info("Quote export consumed. Remaining: \(updatedBucket.remainingQuantity)")
            return updatedBucket
        } catch {
            // Revert optimistic decrement on failure.
            await refresh()
            logger.error("Failed to consume quote export: \(error.localizedDescription)")
            throw error
        }
    }

    /// Reset usage meters (e.g., on sign-out).
    func reset() {
        generationsRemaining = 0
        quotesRemaining = 0
        generationsTotal = 0
        quotesTotal = 0
        logger.info("UsageMeterStore reset.")
    }
}

// MARK: - Preview Support

extension UsageMeterStore {
    /// Create a store pre-loaded with usage values for SwiftUI previews.
    static func preview(
        generationsRemaining: Int = 2,
        generationsTotal: Int = 3,
        quotesRemaining: Int = 3,
        quotesTotal: Int = 3
    ) -> UsageMeterStore {
        let store = UsageMeterStore()
        store.generationsRemaining = generationsRemaining
        store.generationsTotal = generationsTotal
        store.quotesRemaining = quotesRemaining
        store.quotesTotal = quotesTotal
        return store
    }
}
