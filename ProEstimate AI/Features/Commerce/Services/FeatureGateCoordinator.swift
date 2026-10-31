import Foundation
import Observation
import os.log

/// Central coordinator for feature access gating.
///
/// Returns a `FeatureGateResult`:
///   - `.allowed` — the user can proceed.
///   - `.blocked(PaywallDecision)` — present the paywall.
///
/// Basic project access and manual work remain free. Every billable AI or
/// document feature is gated locally and independently enforced by the API.
@Observable
final class FeatureGateCoordinator {
    static let shared = FeatureGateCoordinator()

    // MARK: - Dependencies

    private var entitlementStore: EntitlementStore?
    private var usageMeterStore: UsageMeterStore?
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "FeatureGate")

    // MARK: - Cached Products

    /// Products surfaced to the paywall when a gate fires. Loaded once
    /// at app launch so the paywall doesn't have to round-trip before
    /// its first paint.
    var cachedProducts: [StoreProductModel] = []

    /// Fetch real products from the backend and cache them. Falls back
    /// to sample tier data on failure so the paywall still renders in
    /// dev environments.
    func loadProducts() async {
        do {
            let commerceClient = CommerceAPIClient()
            cachedProducts = try await commerceClient.fetchProducts()
        } catch {
            logger.warning("Failed to load products: \(error.localizedDescription)")
        }
    }

    private var products: [StoreProductModel] {
        cachedProducts.isEmpty ? StoreProductModel.sampleAll : cachedProducts
    }

    // MARK: - Init

    init() {}

    /// Configure the coordinator with its dependencies. Both stores are
    /// load-bearing: `entitlementStore` decides whether the user has
    /// subscription-tier access. Usage is displayed from the server snapshot;
    /// a stale credit balance never substitutes for subscription access.
    func configure(
        entitlementStore: EntitlementStore,
        usageMeterStore: UsageMeterStore
    ) {
        self.entitlementStore = entitlementStore
        self.usageMeterStore = usageMeterStore
    }

    // MARK: - Helpers

    /// Block the action and present the trial-offer / upgrade paywall.
    /// Centralized so copy stays consistent across every gate.
    private func blockWithTrialOffer(
        placement: PaywallPlacement,
        triggerReason: String,
        headline: String,
        subheadline: String
    ) -> FeatureGateResult {
        let primaryTitle = "View Pro Plans"
        let recommendedId = AppConstants.proMonthlyProductID

        return .blocked(PaywallDecision(
            placement: placement,
            triggerReason: triggerReason,
            blocking: true,
            headline: headline,
            subheadline: subheadline,
            primaryCtaTitle: primaryTitle,
            secondaryCtaTitle: "Restore Purchases",
            showContinueFree: false,
            showRestorePurchases: true,
            recommendedProductId: recommendedId,
            availableProducts: products
        ))
    }

    // MARK: - Feature Guards

    /// Historical credits and cached paid flags cannot unlock AI for a free,
    /// expired or revoked account. StoreKit confirms trial eligibility later.
    func guardGeneratePreview() -> FeatureGateResult {
        if entitlementStore?.hasProAccess == true { return .allowed }
        return blockWithTrialOffer(
            placement: .generationLimitHit,
            triggerReason: "AI generation requires an active subscription or trial",
            headline: "Unlock AI Remodel Previews",
            subheadline: "Choose Pro for AI previews and estimates. Eligible Apple Accounts can start with a three-day free trial."
        )
    }

    /// Soft post-generation upgrade prompt is retired. Free users hit
    /// the hard paywall on first tap; Pro users hit it server-side
    /// when they cross their monthly cap. There's no separate "running
    /// low on credits" flow anymore.
    func shouldShowSoftUpgradeAfterGeneration() -> PaywallDecision? {
        nil
    }

    /// Check whether the user can export a quote / proposal PDF.
    func guardExportQuote() -> FeatureGateResult {
        if entitlementStore?.hasProAccess == true { return .allowed }
        logger.info("Quote export blocked — subscription required.")
        return blockWithTrialOffer(
            placement: .quoteLimitHit,
            triggerReason: "Quote export requires a subscription",
            headline: "Send Branded Proposals",
            subheadline: "Export client-ready PDFs with your logo, colors, and contact details. Start a 3-day free trial."
        )
    }

    /// Check whether the user can AI-generate a professional estimate.
    func guardGenerateAIEstimate() -> FeatureGateResult {
        if entitlementStore?.hasProAccess == true { return .allowed }
        logger.info("AI estimate generation blocked — subscription required.")
        return blockWithTrialOffer(
            placement: .aiEstimateLocked,
            triggerReason: "AI estimate generation requires a subscription",
            headline: "AI-Generated Estimates",
            subheadline: "Hand the project to a specialized AI estimator that writes a complete, client-ready estimate using your branding, materials, and pricing."
        )
    }

    /// Check whether the user can create / convert an invoice. Invoices are
    /// a Pro-only feature — the final billing step of the project loop. The
    /// backend independently enforces `assertCanCreateInvoice`, so this gate
    /// is the client-side fast path that routes free users to the paywall
    /// before the round-trip.
    func guardCreateInvoice() -> FeatureGateResult {
        if entitlementStore?.hasFeature(.canCreateInvoice) == true { return .allowed }
        logger.info("Invoice creation blocked — subscription required.")
        return blockWithTrialOffer(
            placement: .invoiceLocked,
            triggerReason: "Invoice creation requires a subscription",
            headline: "Bill Clients with Invoices",
            subheadline: "Turn approved estimates into professional invoices, track payments, and send branded PDFs. Start a 3-day free trial."
        )
    }

    /// Manual projects remain available to free, paid and lapsed accounts.
    /// The optional AI work has its own gate.
    func guardCreateProject() -> FeatureGateResult {
        .allowed
    }

    /// Check whether the user can use the lawn polygon / roof scouting
    /// maps tools. These hit billable Google APIs (Geocoding + Solar
    /// Building Insights) so they share the standard subscription gate.
    /// Catches downgraded users who still have an inherited project but
    /// have lost their entitlement.
    func guardUseMaps() -> FeatureGateResult {
        if entitlementStore?.hasProAccess == true { return .allowed }
        logger.info("Property maps blocked — subscription required.")
        return blockWithTrialOffer(
            placement: .generationLimitHit,
            triggerReason: "Property maps require a subscription",
            headline: "Measure Lawns & Scout Roofs",
            subheadline: "Pull lawn area from a satellite polygon. Pull roof outlines from Google Solar imagery. Both included with any subscription."
        )
    }

    /// Check whether the user can use custom branding.
    func guardUseBranding() -> FeatureGateResult {
        if entitlementStore?.hasFeature(.canUseBranding) == true { return .allowed }
        logger.info("Branding blocked — subscription required.")
        return blockWithTrialOffer(
            placement: .brandingLocked,
            triggerReason: "Custom branding requires a subscription",
            headline: "Brand Every Proposal",
            subheadline: "Add your company logo, colors, and contact info to every proposal and invoice."
        )
    }

    /// Check whether the user can share an approval link with a client.
    func guardShareApprovalLink() -> FeatureGateResult {
        if entitlementStore?.hasFeature(.canShareApprovalLink) == true { return .allowed }
        logger.info("Approval share blocked — subscription required.")
        return blockWithTrialOffer(
            placement: .approvalShareLocked,
            triggerReason: "Client approval links require a subscription",
            headline: "One-Tap Client Approval",
            subheadline: "Send clients a secure link to review and approve proposals from any device — no app required."
        )
    }

    /// Check whether the user can remove watermarks from exports.
    func guardRemoveWatermark() -> FeatureGateResult {
        if entitlementStore?.hasFeature(.canRemoveWatermark) == true { return .allowed }
        logger.info("Watermark removal blocked — subscription required.")
        return blockWithTrialOffer(
            placement: .watermarkRemovalLocked,
            triggerReason: "Watermark-free exports require a subscription",
            headline: "Remove Watermarks",
            subheadline: "Export clean, professional previews and proposals without the ProEstimate watermark."
        )
    }
}

// MARK: - Preview Support

extension FeatureGateCoordinator {
    /// Create a coordinator pre-configured for SwiftUI previews.
    static func preview(
        entitlementStore: EntitlementStore = .preview(),
        usageMeterStore: UsageMeterStore = .preview()
    ) -> FeatureGateCoordinator {
        let coordinator = FeatureGateCoordinator()
        coordinator.entitlementStore = entitlementStore
        coordinator.usageMeterStore = usageMeterStore
        return coordinator
    }
}
