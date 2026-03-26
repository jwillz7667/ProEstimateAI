import Foundation
import os.log

/// Central coordinator for feature access gating.
/// Checks the user's entitlement and usage state to determine whether
/// a gated action should proceed or present a paywall.
///
/// Each `guard*` method returns a `FeatureGateResult`:
/// - `.allowed` — the user can proceed.
/// - `.blocked(PaywallDecision)` — present the paywall with the given decision.
///
/// This coordinator reads from `EntitlementStore` and `UsageMeterStore` only.
/// It does not make network calls — the stores are responsible for staying fresh.
@Observable
final class FeatureGateCoordinator {
    // MARK: - Shared Instance

    static let shared = FeatureGateCoordinator()

    // MARK: - Dependencies

    private var entitlementStore: EntitlementStore?
    private var usageMeterStore: UsageMeterStore?
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "FeatureGate")

    // MARK: - Cached Products

    var cachedProducts: [StoreProductModel] = []

    /// Fetch real products from the backend and cache them.
    /// Falls back to sample data if the fetch fails.
    func loadProducts() async {
        do {
            let commerceClient = CommerceAPIClient()
            cachedProducts = try await commerceClient.fetchProducts()
        } catch {
            logger.warning("Failed to load products: \(error.localizedDescription)")
        }
    }

    /// Returns cached products if available, otherwise sample fallbacks.
    private var products: [StoreProductModel] {
        cachedProducts.isEmpty ? [.sampleMonthly, .sampleAnnual] : cachedProducts
    }

    // MARK: - Init

    init() {}

    /// Configure the coordinator with its dependencies.
    /// Call once during app initialization.
    func configure(
        entitlementStore: EntitlementStore,
        usageMeterStore: UsageMeterStore
    ) {
        self.entitlementStore = entitlementStore
        self.usageMeterStore = usageMeterStore
    }

    // MARK: - Feature Guards

    /// Check whether the user can generate an AI preview.
    /// Free users need remaining generation credits. Pro users have unlimited access.
    func guardGeneratePreview() -> FeatureGateResult {
        guard let entitlementStore, let usageMeterStore else {
            logger.warning("FeatureGateCoordinator not configured. Defaulting to allowed.")
            return .allowed
        }

        // Pro users always have access.
        if entitlementStore.hasProAccess {
            return .allowed
        }

        // Free users need remaining credits.
        if usageMeterStore.canGenerate {
            return .allowed
        }

        logger.info("Generation blocked — credits exhausted.")
        return .blocked(PaywallDecision(
            placement: .generationLimitHit,
            triggerReason: "Free AI generation credits exhausted",
            blocking: true,
            headline: "You've used all \(AppConstants.freeGenerationCredits) free AI previews",
            subheadline: "Upgrade to Pro for unlimited AI remodel previews, watermark-free exports, and branded proposals.",
            primaryCtaTitle: "Start Free Trial",
            secondaryCtaTitle: nil,
            showContinueFree: false,
            showRestorePurchases: true,
            recommendedProductId: AppConstants.monthlyProductID,
            availableProducts: products
        ))
    }

    /// Check whether the user can export a quote.
    /// Free users need remaining export credits. Pro users have unlimited access.
    func guardExportQuote() -> FeatureGateResult {
        guard let entitlementStore, let usageMeterStore else {
            logger.warning("FeatureGateCoordinator not configured. Defaulting to allowed.")
            return .allowed
        }

        if entitlementStore.hasProAccess {
            return .allowed
        }

        if usageMeterStore.canExportQuote {
            return .allowed
        }

        logger.info("Quote export blocked — credits exhausted.")
        return .blocked(PaywallDecision(
            placement: .quoteLimitHit,
            triggerReason: "Free quote export credits exhausted",
            blocking: true,
            headline: "You've used all \(AppConstants.freeQuoteExportCredits) free quote exports",
            subheadline: "Upgrade to Pro for unlimited quote exports, branded proposals, and invoicing.",
            primaryCtaTitle: "Start Free Trial",
            secondaryCtaTitle: nil,
            showContinueFree: false,
            showRestorePurchases: true,
            recommendedProductId: AppConstants.monthlyProductID,
            availableProducts: products
        ))
    }

    /// Check whether the user can create an invoice.
    /// Invoicing is a Pro-only feature — free users cannot create invoices.
    func guardCreateInvoice() -> FeatureGateResult {
        guard let entitlementStore else {
            logger.warning("FeatureGateCoordinator not configured. Defaulting to allowed.")
            return .allowed
        }

        if entitlementStore.hasFeature(.canCreateInvoice) {
            return .allowed
        }

        logger.info("Invoice creation blocked — Pro required.")
        return .blocked(PaywallDecision(
            placement: .invoiceLocked,
            triggerReason: "Invoice creation requires Pro",
            blocking: true,
            headline: "Invoicing is a Pro feature",
            subheadline: "Create and send professional invoices with automatic payment tracking.",
            primaryCtaTitle: "Upgrade to Pro",
            secondaryCtaTitle: nil,
            showContinueFree: false,
            showRestorePurchases: true,
            recommendedProductId: AppConstants.monthlyProductID,
            availableProducts: products
        ))
    }

    /// Check whether the user can use custom branding.
    /// Branding is a Pro-only feature.
    func guardUseBranding() -> FeatureGateResult {
        guard let entitlementStore else {
            logger.warning("FeatureGateCoordinator not configured. Defaulting to allowed.")
            return .allowed
        }

        if entitlementStore.hasFeature(.canUseBranding) {
            return .allowed
        }

        logger.info("Branding blocked — Pro required.")
        return .blocked(PaywallDecision(
            placement: .brandingLocked,
            triggerReason: "Custom branding requires Pro",
            blocking: true,
            headline: "Brand your proposals",
            subheadline: "Add your company logo, colors, and contact info to every proposal and invoice.",
            primaryCtaTitle: "Upgrade to Pro",
            secondaryCtaTitle: nil,
            showContinueFree: false,
            showRestorePurchases: true,
            recommendedProductId: AppConstants.monthlyProductID,
            availableProducts: products
        ))
    }

    /// Check whether the user can share an approval link.
    /// Approval link sharing is a Pro-only feature.
    func guardShareApprovalLink() -> FeatureGateResult {
        guard let entitlementStore else {
            logger.warning("FeatureGateCoordinator not configured. Defaulting to allowed.")
            return .allowed
        }

        if entitlementStore.hasFeature(.canShareApprovalLink) {
            return .allowed
        }

        logger.info("Approval share blocked — Pro required.")
        return .blocked(PaywallDecision(
            placement: .approvalShareLocked,
            triggerReason: "Client approval links require Pro",
            blocking: true,
            headline: "Share approval links with clients",
            subheadline: "Let clients review and approve proposals online with a single tap.",
            primaryCtaTitle: "Upgrade to Pro",
            secondaryCtaTitle: nil,
            showContinueFree: false,
            showRestorePurchases: true,
            recommendedProductId: AppConstants.monthlyProductID,
            availableProducts: products
        ))
    }

    /// Check whether the user can remove watermarks from exports.
    /// Watermark removal is a Pro-only feature.
    func guardRemoveWatermark() -> FeatureGateResult {
        guard let entitlementStore else {
            logger.warning("FeatureGateCoordinator not configured. Defaulting to allowed.")
            return .allowed
        }

        if entitlementStore.hasFeature(.canRemoveWatermark) {
            return .allowed
        }

        logger.info("Watermark removal blocked — Pro required.")
        return .blocked(PaywallDecision(
            placement: .watermarkRemovalLocked,
            triggerReason: "Watermark-free exports require Pro",
            blocking: true,
            headline: "Remove watermarks",
            subheadline: "Export clean, professional previews and proposals without the ProEstimate watermark.",
            primaryCtaTitle: "Upgrade to Pro",
            secondaryCtaTitle: nil,
            showContinueFree: false,
            showRestorePurchases: true,
            recommendedProductId: AppConstants.monthlyProductID,
            availableProducts: products
        ))
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
