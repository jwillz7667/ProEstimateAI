import Foundation
import Observation
import os.log
import StoreKit

/// ViewModel managing the paywall presentation and purchase flow.
/// Handles product loading from both the backend catalog and StoreKit,
/// plan selection, purchase initiation, and restore.
///
/// The paywall can be triggered from any `PaywallPlacement` with a `PaywallDecision`
/// that provides the headline copy, CTA labels, and whether the gate is blocking.
@Observable
final class PaywallHostViewModel {
    // MARK: - State

    /// Backend product catalog enriched with StoreKit pricing.
    private(set) var products: [StoreProductModel] = []

    /// The currently selected product for purchase. Always derived
    /// from (`selectedTier`, `isAnnualSelected`) but stored explicitly
    /// so the existing UI bindings keep working.
    var selectedProduct: StoreProductModel?

    /// Currently-highlighted tier. Pro is the only paid tier; the
    /// property is retained so the period picker can resolve the matching
    /// SKU and so any future tiering doesn't require re-plumbing the view.
    var selectedTier: PlanTier = .pro {
        didSet { resyncSelectedProduct() }
    }

    /// Monthly is the initial selection. Both periods can show an actual
    /// introductory offer when StoreKit confirms Apple Account eligibility.
    var isAnnualSelected: Bool = false {
        didSet { resyncSelectedProduct() }
    }

    /// Keep the selection within the products actually returned by StoreKit.
    /// An unavailable period has no selected product and cannot be purchased.
    private func resyncSelectedProduct() {
        let exact = products.first {
            $0.tier == selectedTier && $0.isAnnual == isAnnualSelected
        }
        selectedProduct = exact
    }

    /// Whether products are loading.
    private(set) var isLoading: Bool = false

    /// Whether a purchase is in progress.
    private(set) var isPurchasing: Bool = false

    /// Whether a restore is in progress.
    private(set) var isRestoring: Bool = false

    /// Whether the current Apple ID is eligible for the introductory (free-trial)
    /// offer on the subscription group. `nil` until products have been loaded.
    private(set) var isEligibleForTrial: Bool?

    /// A retryable catalog error. Purchases stay disabled without live plans;
    /// restore and free workspace access remain available.
    var errorMessage: String?

    /// Modal alert for purchase, restore, and other transactional outcomes.
    /// Distinct copy + actions per failure mode (account mismatch, payments
    /// disabled, network, retryable error). Cancelled purchases are silent.
    var activeAlert: PurchaseAlert?

    /// Whether the purchase completed successfully.
    private(set) var purchaseSucceeded: Bool = false

    /// The paywall placement context.
    let placement: PaywallPlacement

    /// The paywall decision providing copy and configuration.
    let decision: PaywallDecision

    // MARK: - Dependencies

    private let commerceAPI: CommerceAPIClientProtocol
    private let catalogService: StoreKitCatalogProviding
    private let purchaseCoordinator: PurchaseCoordinating
    private let entitlementStore: EntitlementStore
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "PaywallVM")

    // MARK: - Init

    init(
        decision: PaywallDecision,
        commerceAPI: CommerceAPIClientProtocol = CommerceAPIClient(),
        catalogService: StoreKitCatalogProviding = StoreKitCatalogService(),
        purchaseCoordinator: PurchaseCoordinating? = nil,
        entitlementStore: EntitlementStore = .shared
    ) {
        self.decision = decision
        placement = decision.placement
        self.commerceAPI = commerceAPI
        self.catalogService = catalogService
        self.entitlementStore = entitlementStore

        // If no purchase coordinator is provided, create one with the shared dependencies.
        if let coordinator = purchaseCoordinator {
            self.purchaseCoordinator = coordinator
        } else {
            self.purchaseCoordinator = StoreKitPurchaseCoordinator(
                commerceAPI: commerceAPI,
                entitlementStore: entitlementStore
            )
        }

        // Start with monthly; both periods use their live StoreKit offer.
        selectedTier = .pro
        isAnnualSelected = false
    }

    // MARK: - Product Loading

    /// Only Apple's live products can supply checkout prices and offers.
    /// A catalog outage must remain retryable, not turn fallback text into a sale.
    func loadProducts() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        isEligibleForTrial = nil
        defer { isLoading = false }

        do {
            let storeProducts = try await catalogService.loadProducts()
            guard !storeProducts.isEmpty else { throw PurchaseError.productNotFound }
            let eligible = await catalogService.isEligibleForIntroOffer()
            isEligibleForTrial = eligible
            let monthly = storeProducts.first { $0.id == AppConstants.proMonthlyProductID }
            let annual = storeProducts.first { $0.id == AppConstants.proAnnualProductID }
            let savings = monthly.flatMap { monthly in
                annual.flatMap { StoreProductModel.annualSavingsText(monthlyPrice: monthly.price, annualPrice: $0.price) }
            }
            products = storeProducts.map { product in
                StoreKitCatalogService.mapToStoreProductModel(
                    product,
                    isEligibleForIntro: eligible,
                    isFeatured: product.id == AppConstants.proMonthlyProductID,
                    savingsText: product.id == AppConstants.proAnnualProductID ? savings : nil
                )
            }
            applyInitialSelection()
        } catch {
            products = []
            selectedProduct = nil
            errorMessage = "The App Store couldn't load subscription plans. Check your connection and App Store account, then try again. You can still restore purchases or close this screen to use your basic workspace."
            logger.warning("StoreKit catalog unavailable: \(error.localizedDescription)")
        }
    }

    // MARK: - Plan Selection

    /// Select a specific product for purchase. Updates the tier +
    /// period state so the picker visuals stay in sync.
    func selectProduct(_ product: StoreProductModel) {
        selectedProduct = product
        selectedTier = product.tier
        isAnnualSelected = product.isAnnual
    }

    /// Pick the initial product after products load. Order of preference:
    ///   1. The decision's `recommendedProductId` (e.g. backend hinting at
    ///      Pro Monthly for a trial offer).
    ///   2. Pro Monthly, if Apple returned it.
    ///   3. Whatever the catalog's first entry is.
    private func applyInitialSelection() {
        if let recommendedId = decision.recommendedProductId,
           let recommended = products.first(where: { $0.productId == recommendedId })
        {
            selectProduct(recommended)
            return
        }
        if let proMonthly = products.first(where: { $0.isPro && $0.isMonthly }) {
            selectProduct(proMonthly)
            return
        }
        if let any = products.first {
            selectProduct(any)
        }
    }

    // MARK: - Purchase

    /// Initiate a purchase for the currently selected product.
    /// Follows the full flow: backend purchase attempt -> StoreKit purchase -> sync.
    func purchase() async {
        guard let selectedProduct else {
            activeAlert = .selectionRequired
            return
        }

        guard !isPurchasing, !isRestoring else { return }

        // Set the in-flight flag BEFORE any async work so a rapid double-tap
        // is rejected by the guard above even while the first
        // `createPurchaseAttempt` round-trip is mid-flight. The previous
        // ordering set the flag after the RPC, leaving a brief window where
        // two attempts could be created back-to-back.
        isPurchasing = true
        activeAlert = nil
        errorMessage = nil

        do {
            // Resolve Apple's actual product before creating an attempt. Never
            // initiate checkout using a backend or cached display-only fallback.
            guard let storeProduct = try await catalogService.product(for: selectedProduct.productId) else {
                throw PurchaseError.productNotFound
            }
            let attempt = try await commerceAPI.createPurchaseAttempt(
                productId: storeProduct.id,
                placement: placement
            )
            guard let appAccountToken = UUID(uuidString: attempt.appAccountToken) else {
                throw PurchaseError.storeKitError("Invalid app account token from server")
            }

            // Step 3: Initiate StoreKit purchase.
            // The purchase coordinator handles verification, backend sync, and entitlement update.
            _ = try await purchaseCoordinator.purchase(
                product: storeProduct,
                appAccountToken: appAccountToken
            )

            guard entitlementStore.hasProAccess else {
                throw PurchaseError.deliveryPending
            }
            purchaseSucceeded = true
            logger.info("Purchase completed successfully for product: \(selectedProduct.productId)")
        } catch let error as PurchaseError {
            handlePurchaseError(error, context: .purchase)
        } catch let APIError.network(detail) {
            handlePurchaseError(.network(detail), context: .purchase)
        } catch {
            logger.error("Purchase failed with unexpected error: \(error.localizedDescription)")
            activeAlert = PurchaseAlert(
                kind: .genericFailure(message: error.localizedDescription),
                context: .purchase
            )
        }

        // Always reconcile entitlement after a purchase round-trip — whether
        // it succeeded, failed, or threw. The backend may have partially
        // updated state (e.g. PurchaseAttempt marked COMPLETED but the
        // response was lost to a network blip) and the user shouldn't be
        // stranded on a stale FREE snapshot.
        await entitlementStore.refresh()
        isPurchasing = false
    }

    /// Map a `PurchaseError` to the alert state. Centralised so both
    /// `purchase()` and `restorePurchases()` route through the same
    /// translation; `context` decides whether the alert's "Try Again"
    /// button re-runs the purchase or the restore flow.
    private func handlePurchaseError(_ error: PurchaseError, context: PurchaseAlert.Context) {
        switch error {
        case .cancelled:
            // User cancelled the StoreKit dialog — no UI noise.
            logger.info("Purchase cancelled by user.")
            activeAlert = nil
        case .pending:
            logger.info("Purchase pending approval.")
            activeAlert = PurchaseAlert(kind: .pendingApproval, context: context)
        case .deliveryPending:
            activeAlert = PurchaseAlert(kind: .deliveryPending, context: context)
        case .accountMismatch:
            logger.error("Purchase blocked by account mismatch.")
            activeAlert = PurchaseAlert(kind: .accountMismatch, context: context)
        case .subscriptionBoundToOtherUser:
            logger.error("Purchase blocked — Apple subscription owned by another ProEstimate user.")
            activeAlert = PurchaseAlert(kind: .subscriptionBoundToOtherUser, context: context)
        case .paymentsNotAllowed:
            logger.error("Purchase blocked: payments not allowed on this device/Apple ID.")
            activeAlert = PurchaseAlert(kind: .paymentsNotAllowed, context: context)
        case .unverified:
            logger.error("Purchase verification failed.")
            activeAlert = PurchaseAlert(kind: .verificationFailed, context: context)
        case .productNotFound:
            logger.error("Selected product not available.")
            activeAlert = PurchaseAlert(kind: .productUnavailable, context: context)
        case .network(let detail):
            logger.warning("Purchase network error: \(detail)")
            activeAlert = PurchaseAlert(kind: .networkProblem, context: context)
        case .storeKitError(let detail):
            logger.error("StoreKit error: \(detail)")
            activeAlert = PurchaseAlert(
                kind: .genericFailure(message: error.localizedDescription),
                context: context
            )
        }
    }

    // MARK: - Restore

    /// Restore previously purchased subscriptions.
    func restorePurchases() async {
        guard !isRestoring, !isPurchasing else { return }

        isRestoring = true
        activeAlert = nil
        errorMessage = nil

        do {
            try await purchaseCoordinator.restorePurchases()

            // Check if restore resulted in Pro access.
            if entitlementStore.hasProAccess {
                purchaseSucceeded = true
                logger.info("Restore successful — Pro access confirmed.")
            } else {
                logger.info("Restore completed but no active subscription found.")
                activeAlert = .restoreNothingToRestore
            }
        } catch let error as PurchaseError {
            // Restore can surface the same error space as purchase (network,
            // payments-disabled, etc.) — reuse the mapping so the user sees
            // consistent copy and recovery actions, but tag the alert with
            // restore context so "Try Again" re-runs the restore flow.
            handlePurchaseError(error, context: .restore)
        } catch {
            logger.error("Restore failed: \(error.localizedDescription)")
            activeAlert = .restoreFailed
        }

        isRestoring = false
    }

    // MARK: - Computed Properties

    var hasProAccess: Bool { entitlementStore.hasProAccess }

    var displayHeadline: String {
        if decision.headline.localizedCaseInsensitiveContains("trial") ||
           decision.headline.localizedCaseInsensitiveContains("free for") {
            if let product = selectedProduct, product.showsTrialBadge,
               let offer = product.introOfferDisplayText {
                return "Try Pro with a \(offer)"
            }
            return "Unlock Pro Features"
        }
        return decision.headline
    }

    var displaySubheadline: String {
        if decision.subheadline.localizedCaseInsensitiveContains("trial") ||
           decision.subheadline.localizedCaseInsensitiveContains("free for") {
            return "Choose a monthly or annual plan for AI previews, branded proposals, invoicing, and client approvals. Trial eligibility and renewal pricing are shown below."
        }
        return decision.subheadline
    }

    /// The monthly product, if available.
    var monthlyProduct: StoreProductModel? {
        products.first { $0.isMonthly }
    }

    /// The annual product, if available.
    var annualProduct: StoreProductModel? {
        products.first { $0.isAnnual }
    }

    /// Whether the paywall should show the "Continue with Free" option.
    var showContinueFree: Bool {
        decision.showContinueFree
    }

    /// Whether the paywall should show the "Restore Purchases" link.
    var showRestorePurchases: Bool {
        decision.showRestorePurchases
    }

    /// Whether the paywall is a hard gate (cannot be dismissed without purchase).
    var isBlocking: Bool {
        decision.blocking
    }

    /// Primary CTA label. When the user is NOT trial-eligible (e.g. they already
    /// redeemed the intro offer on another device or via Family Sharing), replace
    /// the "Start Free Trial" copy with an immediate-charge label so the user
    /// isn't surprised by a charge.
    var primaryCtaTitle: String {
        selectedProduct?.purchaseButtonTitle(fallback: decision.primaryCtaTitle) ?? "Subscribe Now"
    }
}

// MARK: - Preview Support

extension PaywallHostViewModel {
    /// Create a view model for SwiftUI previews with mock data.
    /// Loads the sample catalog (Pro Monthly + Annual) and lets the
    /// period binding drive `selectedProduct` so the preview surfaces the
    /// same selection logic used in production.
    static func preview(
        decision: PaywallDecision = .sampleSoftGate
    ) -> PaywallHostViewModel {
        let vm = PaywallHostViewModel(
            decision: decision,
            commerceAPI: MockCommerceAPIClient(),
            entitlementStore: .preview()
        )
        vm.products = StoreProductModel.sampleAll
        vm.selectedTier = .pro
        vm.isAnnualSelected = false
        return vm
    }
}
