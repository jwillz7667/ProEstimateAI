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

    /// Currently-highlighted tier (Pro vs Premium). Premium is the
    /// default since it's the recommended tier; the trial only kicks
    /// in if the user toggles to Pro Monthly.
    var selectedTier: PlanTier = .premium {
        didSet { resyncSelectedProduct() }
    }

    /// Whether the annual period toggle is selected. Defaults off so
    /// the cheapest entry-point ($49.99 Premium Monthly) is the visible
    /// price first.
    var isAnnualSelected: Bool = false {
        didSet { resyncSelectedProduct() }
    }

    /// Resolve the (tier, period) intersection from the current product
    /// catalog and assign it to `selectedProduct`. Falls back to the
    /// nearest tier match when the exact intersection isn't available
    /// (e.g. before Premium ships in App Store Connect).
    private func resyncSelectedProduct() {
        let exact = products.first {
            $0.tier == selectedTier && $0.isAnnual == isAnnualSelected
        }
        let fallback = products.first { $0.tier == selectedTier }
        selectedProduct = exact ?? fallback ?? selectedProduct
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

    /// Error message to display, if any.
    var errorMessage: String?

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

        // Default selection: Premium Monthly. The contractor sees the
        // recommended tier with the lowest entry-point price first; the
        // toggle is one tap from Pro or Annual.
        selectedTier = .premium
        isAnnualSelected = false
    }

    // MARK: - Product Loading

    /// Load products from the backend catalog, enriched with live StoreKit pricing.
    /// Falls back to the backend-provided products if StoreKit is unavailable.
    func loadProducts() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        do {
            // First, try to load from backend for enriched catalog data.
            var backendProducts = try await commerceAPI.fetchProducts()

            // Then try to enrich with live StoreKit pricing and eligibility.
            do {
                let storeProducts = try await catalogService.loadProducts()
                let isEligibleForIntro = await catalogService.isEligibleForIntroOffer(
                    groupID: AppConstants.subscriptionGroupID
                )
                isEligibleForTrial = isEligibleForIntro

                // Map StoreKit products and merge with backend data.
                // Premium Monthly is the featured tile (paywall headline);
                // Annual products surface a savings tag pulled from the
                // backend catalog when present.
                let storeModels = storeProducts.map { product in
                    StoreKitCatalogService.mapToStoreProductModel(
                        product,
                        isEligibleForIntro: isEligibleForIntro,
                        isFeatured: product.id == AppConstants.premiumMonthlyProductID,
                        savingsText: product.id == AppConstants.proAnnualProductID
                            ? "Save 17%"
                            : product.id == AppConstants.premiumAnnualProductID
                            ? "Save 17%"
                            : nil
                    )
                }

                // Prefer StoreKit pricing over backend pricing if available.
                if !storeModels.isEmpty {
                    backendProducts = storeModels
                }
            } catch {
                // StoreKit unavailable (e.g., simulator without StoreKit config).
                // Fall through to use backend products.
                logger.warning("StoreKit products unavailable: \(error.localizedDescription). Using backend catalog.")
            }

            products = backendProducts

            applyInitialSelection()

            let loadedCount = products.count
            logger.info("Loaded \(loadedCount) products for paywall.")
        } catch {
            // If backend also fails, use decision's embedded products as last resort.
            if let decisionProducts = decision.availableProducts, !decisionProducts.isEmpty {
                products = decisionProducts
                applyInitialSelection()
                logger.warning("Using PaywallDecision fallback products.")
            } else {
                errorMessage = "Unable to load subscription plans. Please try again."
                logger.error("Failed to load products: \(error.localizedDescription)")
            }
        }

        isLoading = false
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
    ///   2. Premium Monthly — the headline tier we want most contractors on.
    ///   3. Pro Monthly — fallback for legacy catalogs missing Premium.
    ///   4. Whatever the catalog's first entry is.
    private func applyInitialSelection() {
        if let recommendedId = decision.recommendedProductId,
           let recommended = products.first(where: { $0.productId == recommendedId })
        {
            selectProduct(recommended)
            return
        }
        if let premiumMonthly = products.first(where: { $0.isPremium && $0.isMonthly }) {
            selectProduct(premiumMonthly)
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
            errorMessage = "Please select a plan."
            return
        }

        guard !isPurchasing else { return }

        isPurchasing = true
        errorMessage = nil

        do {
            // Step 1: Create purchase attempt on backend to get appAccountToken.
            let attempt = try await commerceAPI.createPurchaseAttempt(
                productId: selectedProduct.productId,
                placement: placement
            )

            guard let appAccountToken = UUID(uuidString: attempt.appAccountToken) else {
                throw PurchaseError.storeKitError("Invalid app account token from server")
            }

            // Step 2: Get the StoreKit product.
            guard let storeProduct = try await catalogService.product(for: selectedProduct.productId) else {
                throw PurchaseError.productNotFound
            }

            // Step 3: Initiate StoreKit purchase.
            // The purchase coordinator handles verification, backend sync, and entitlement update.
            _ = try await purchaseCoordinator.purchase(
                product: storeProduct,
                appAccountToken: appAccountToken
            )

            purchaseSucceeded = true
            logger.info("Purchase completed successfully for product: \(selectedProduct.productId)")
        } catch let error as PurchaseError {
            switch error {
            case .cancelled:
                // User cancelled — no error message needed.
                logger.info("Purchase cancelled by user.")
            case .pending:
                errorMessage = "Your purchase is pending approval. You'll get access once approved."
                logger.info("Purchase pending approval.")
            default:
                errorMessage = error.localizedDescription
                logger.error("Purchase failed: \(error.localizedDescription)")
            }
        } catch {
            errorMessage = "Something went wrong. Please try again."
            logger.error("Purchase failed with unexpected error: \(error.localizedDescription)")
        }

        isPurchasing = false
    }

    // MARK: - Restore

    /// Restore previously purchased subscriptions.
    func restorePurchases() async {
        guard !isRestoring else { return }

        isRestoring = true
        errorMessage = nil

        do {
            try await purchaseCoordinator.restorePurchases()

            // Check if restore resulted in Pro access.
            if entitlementStore.hasProAccess {
                purchaseSucceeded = true
                logger.info("Restore successful — Pro access confirmed.")
            } else {
                errorMessage = "No active subscription found for this Apple ID."
                logger.info("Restore completed but no active subscription found.")
            }
        } catch {
            errorMessage = "Unable to restore purchases. Please try again."
            logger.error("Restore failed: \(error.localizedDescription)")
        }

        isRestoring = false
    }

    // MARK: - Computed Properties

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
        let base = decision.primaryCtaTitle
        // If eligibility is known-false AND the decision copy implies a trial, override.
        if isEligibleForTrial == false,
           base.localizedCaseInsensitiveContains("trial") || base.localizedCaseInsensitiveContains("free")
        {
            return "Subscribe Now"
        }
        return base
    }
}

// MARK: - Preview Support

extension PaywallHostViewModel {
    /// Create a view model for SwiftUI previews with mock data.
    static func preview(
        decision: PaywallDecision = .sampleSoftGate
    ) -> PaywallHostViewModel {
        let vm = PaywallHostViewModel(
            decision: decision,
            commerceAPI: MockCommerceAPIClient(),
            entitlementStore: .preview()
        )
        vm.products = [.sampleMonthly, .sampleAnnual]
        vm.selectedProduct = .sampleAnnual
        return vm
    }
}
