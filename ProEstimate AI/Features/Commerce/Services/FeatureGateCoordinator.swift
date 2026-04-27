import Foundation
import os.log

/// Central coordinator for feature access gating.
///
/// Returns a `FeatureGateResult`:
///   - `.allowed` — the user can proceed.
///   - `.blocked(PaywallDecision)` — present the paywall.
///
/// As of the Premium tier launch, free users receive **zero** pre-paid
/// actions: every paid feature flips to the paywall on first tap (Trial
/// Offer if the user has never trialed, Subscribe Now if they have).
/// Pro users have monthly caps (2 projects / 20 image gens / 20 estimates)
/// enforced on the backend; the local gate just routes to the paywall.
@Observable
final class FeatureGateCoordinator {
    static let shared = FeatureGateCoordinator()

    // MARK: - Dependencies

    private var entitlementStore: EntitlementStore?
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

    /// Configure the coordinator with its dependencies.
    /// `usageMeterStore` is no longer required for gating decisions but
    /// stays in the API for source compatibility with
    /// `ProEstimate_AIApp.bootstrap()`.
    func configure(
        entitlementStore: EntitlementStore,
        usageMeterStore _: UsageMeterStore
    ) {
        self.entitlementStore = entitlementStore
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
    func guardGeneratePreview() -> FeatureGateResult {
        guard let entitlementStore else { return .allowed }
        if entitlementStore.hasProAccess { return .allowed }
        logger.info("Generation blocked — subscription required.")
        return blockWithTrialOffer(
            placement: .generationLimitHit,
            triggerReason: "AI preview requires a subscription",
            headline: "Unlock AI Remodel Previews",
            subheadline: "See realistic AI-generated previews of your finished project, instantly. Start a 7-day free trial — cancel anytime."
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

    /// Check whether the user can create a new project. Free users hit
    /// the paywall here; Pro users hit it server-side at the 2/month cap.
    func guardCreateProject() -> FeatureGateResult {
        guard let entitlementStore else { return .allowed }
        if entitlementStore.hasProAccess { return .allowed }
        logger.info("Project creation blocked — subscription required.")
        return blockWithTrialOffer(
            placement: .generationLimitHit,
            triggerReason: "Creating projects requires a subscription",
            headline: "Start Your First Project",
            subheadline: "Every project includes AI previews, instant estimates, and branded proposals. Start a 7-day free trial — cancel anytime."
        )
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

    /// Check whether the user can open the Analytics dashboard.
    func guardAccessAnalytics() -> FeatureGateResult {
        guard let entitlementStore else { return .allowed }
        if entitlementStore.hasProAccess { return .allowed }
        logger.info("Analytics blocked — subscription required.")
        return blockWithTrialOffer(
            placement: .analyticsLocked,
            triggerReason: "Analytics requires a subscription",
            headline: "Business Analytics",
            subheadline: "Track revenue, win rates, and project trends across your pipeline."
        )
    }

    /// Check whether the user can create an additional pricing profile.
    /// Free users hit the paywall on the first attempt — Pro/Premium can
    /// create unlimited.
    func guardAddPricingProfile(currentCount _: Int) -> FeatureGateResult {
        guard let entitlementStore else { return .allowed }
        if entitlementStore.hasProAccess { return .allowed }
        logger.info("Pricing profile creation blocked — subscription required.")
        return blockWithTrialOffer(
            placement: .pricingProfileLocked,
            triggerReason: "Pricing profiles require a subscription",
            headline: "Custom Pricing Profiles",
            subheadline: "Build reusable pricing templates for residential, commercial, and specialty work — switch between them in one tap."
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
        _ = usageMeterStore
        return coordinator
    }
}
