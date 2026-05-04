import Foundation
import os.log

/// Central coordinator for feature access gating.
///
/// Returns a `FeatureGateResult`:
///   - `.allowed` — the user can proceed.
///   - `.blocked(PaywallDecision)` — present the paywall.
///
/// Free users get a small pool of starter AI generation credits
/// (`AppConstants.freeGenerationCredits`) before the paywall fires.
/// Project creation and photo upload ride through unconditionally —
/// without a project there's nothing to generate against, so the
/// generation gate is the only bottleneck. Every other Pro feature
/// (quote export, branding, invoices, share links, AI estimates,
/// analytics, custom pricing profiles, watermark removal, maps) hits
/// the paywall on first tap. Pro users have backend-enforced monthly
/// caps; the local gate just routes them to the paywall when the
/// backend signals exhaustion.
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
    /// subscription-tier access, and `usageMeterStore` decides whether a
    /// FREE user still has starter generation credits remaining.
    func configure(
        entitlementStore: EntitlementStore,
        usageMeterStore: UsageMeterStore
    ) {
        self.entitlementStore = entitlementStore
        self.usageMeterStore = usageMeterStore
    }

    // MARK: - Helpers

    /// Whether this user qualifies for the 7-day free trial. A user is
    /// trial-eligible when they're currently on the free tier AND have
    /// never started a trial before (no `trialEndsAt` on the snapshot).
    private var isTrialEligible: Bool {
        guard let snapshot = entitlementStore?.snapshot else { return true }
        return snapshot.subscriptionState == .free && snapshot.trialEndsAt == nil
    }

    /// Block the action and present the trial-offer / upgrade paywall.
    /// Centralized so copy stays consistent across every gate.
    private func blockWithTrialOffer(
        placement: PaywallPlacement,
        triggerReason: String,
        headline: String,
        subheadline: String
    ) -> FeatureGateResult {
        let primaryTitle = isTrialEligible ? "Start 7-Day Free Trial" : "Upgrade to Continue"
        let recommendedId = isTrialEligible
            ? AppConstants.proMonthlyProductID
            : AppConstants.premiumMonthlyProductID

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

    /// Check whether the user can generate an AI preview image.
    ///
    /// Pro / trialing users always pass through. Free users pass through
    /// while they still have starter generation credits remaining and hit
    /// the paywall the moment that pool is exhausted. The credit counter
    /// is intentionally NOT surfaced in normal UI — it only appears on
    /// the paywall sheet that fires on exhaustion (see
    /// `PaywallHostView`'s `.generationLimitHit` branch).
    func guardGeneratePreview() -> FeatureGateResult {
        guard let entitlementStore else { return .allowed }
        if entitlementStore.hasProAccess { return .allowed }
        if let meter = usageMeterStore, meter.canGenerate {
            return .allowed
        }
        logger.info("Generation blocked — starter credits exhausted.")
        return blockWithTrialOffer(
            placement: .generationLimitHit,
            triggerReason: "Free generation credits exhausted",
            headline: "You've Used All 5 Free Generations",
            subheadline: "Start a 7-day free trial to keep generating AI previews — unlimited while you trial, then continue on any paid plan."
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
        guard let entitlementStore else { return .allowed }
        if entitlementStore.hasProAccess { return .allowed }
        logger.info("Quote export blocked — subscription required.")
        return blockWithTrialOffer(
            placement: .quoteLimitHit,
            triggerReason: "Quote export requires a subscription",
            headline: "Send Branded Proposals",
            subheadline: "Export client-ready PDFs with your logo, colors, and contact details. Start a 7-day free trial."
        )
    }

    /// Check whether the user can AI-generate a professional estimate.
    func guardGenerateAIEstimate() -> FeatureGateResult {
        guard let entitlementStore else { return .allowed }
        if entitlementStore.subscriptionState.hasProAccess { return .allowed }
        logger.info("AI estimate generation blocked — subscription required.")
        return blockWithTrialOffer(
            placement: .aiEstimateLocked,
            triggerReason: "AI estimate generation requires a subscription",
            headline: "AI-Generated Estimates",
            subheadline: "Hand the project to a specialized AI estimator that writes a complete, client-ready estimate using your branding, materials, and pricing."
        )
    }

    /// Project creation is always allowed locally. Free users need to
    /// own a project to spend their starter generation credits against,
    /// so gating creation defeats the starter pack. The bottleneck for
    /// free users is `guardGeneratePreview()`; Pro users hit the
    /// 2-projects-per-month cap server-side.
    func guardCreateProject() -> FeatureGateResult {
        .allowed
    }

    /// Check whether the user can use the lawn polygon / roof scouting
    /// maps tools. These hit billable Google APIs (Geocoding + Solar
    /// Building Insights) so they share the standard subscription gate.
    /// Catches downgraded users who still have an inherited project but
    /// have lost their entitlement.
    func guardUseMaps() -> FeatureGateResult {
        guard let entitlementStore else { return .allowed }
        if entitlementStore.hasProAccess { return .allowed }
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
        guard let entitlementStore else { return .allowed }
        if entitlementStore.hasFeature(.canUseBranding) { return .allowed }
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
        guard let entitlementStore else { return .allowed }
        if entitlementStore.hasFeature(.canShareApprovalLink) { return .allowed }
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
        guard let entitlementStore else { return .allowed }
        if entitlementStore.hasFeature(.canRemoveWatermark) { return .allowed }
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
