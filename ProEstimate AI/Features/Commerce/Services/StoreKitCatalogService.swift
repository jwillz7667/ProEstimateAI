import Foundation
import os.log
import StoreKit

/// Production implementation of `StoreKitCatalogProviding`.
/// Loads subscription products from the App Store using StoreKit 2 APIs
/// and checks introductory offer eligibility against the subscription group.
final class StoreKitCatalogService: StoreKitCatalogProviding {
    private let productIDs: Set<String>
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "StoreKitCatalog")

    /// Cached products after the first load to avoid redundant App Store calls.
    private var cachedProducts: [Product]?
    private var loadedAt: Date?

    init(productIDs: Set<String>? = nil) {
        self.productIDs = productIDs ?? Set(AppConstants.allSubscriptionProductIDs)
    }

    // MARK: - StoreKitCatalogProviding

    func loadProducts() async throws -> [Product] {
        if let cached = cachedProducts, !cached.isEmpty,
           let loadedAt, Date().timeIntervalSince(loadedAt) < 60 {
            return cached
        }

        let ids = productIDs
        logger.info("Loading StoreKit products: \(ids)")

        do {
            let products = try await Product.products(for: ids)

            if products.isEmpty {
                logger.warning("No products returned from StoreKit for IDs: \(ids)")
            } else {
                logger.info("Loaded \(products.count) products from StoreKit")
            }

            // An empty catalog is transient (sign-in, storefront or propagation);
            // do not poison retries for the lifetime of this paywall.
            if !products.isEmpty {
                cachedProducts = products
                loadedAt = Date()
            }
            return products
        } catch {
            logger.error("Failed to load StoreKit products: \(error.localizedDescription)")
            throw error
        }
    }

    func product(for id: String) async throws -> Product? {
        let products = try await loadProducts()
        return products.first { $0.id == id }
    }

    func isEligibleForIntroOffer() async -> Bool {
        do {
            let products = try await loadProducts()

            // App Store Connect assigns the production group identifier.
            // The local .storekit test group name is not its identifier.
            guard let subscription = products.first(where: { $0.subscription != nil })?.subscription else {
                logger.warning("No subscription products available for intro offer eligibility.")
                return false
            }

            let isEligible = await subscription.isEligibleForIntroOffer
            logger.info("Intro offer eligibility for group \(subscription.subscriptionGroupID): \(isEligible)")
            return isEligible
        } catch {
            logger.error("Failed to check intro offer eligibility: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Mapping

    /// Convert a StoreKit `Product` to our app's `StoreProductModel`.
    /// Enriches with intro offer details and plan code derived from the product ID.
    static func mapToStoreProductModel(
        _ product: Product,
        isEligibleForIntro: Bool,
        isFeatured: Bool = false,
        savingsText: String? = nil
    ) -> StoreProductModel {
        let planCode: PlanCode = {
            switch product.id {
            case AppConstants.proMonthlyProductID: return .proMonthly
            case AppConstants.proAnnualProductID: return .proAnnual
            default:
                // Unknown product ID — fall back based on subscription period
                // so the period toggle still works for unexpected catalog entries.
                let isAnnual = product.subscription?.subscriptionPeriod.unit == .year
                return isAnnual ? .proAnnual : .proMonthly
            }
        }()

        let billingPeriodLabel: String = {
            guard let subscription = product.subscription else { return "one-time" }
            switch subscription.subscriptionPeriod.unit {
            case .month: return "per month"
            case .year: return "per year"
            case .week: return "per week"
            case .day: return "per day"
            @unknown default: return "per period"
            }
        }()

        let introOfferText: String? = {
            guard isEligibleForIntro,
                  let introOffer = product.subscription?.introductoryOffer else { return nil }

            let periodValue = introOffer.period.value
            let periodUnit = introOffer.period.unit
            let unitLabel: String
            switch periodUnit {
            case .day: unitLabel = periodValue == 1 ? "day" : "days"
            case .week: unitLabel = periodValue == 1 ? "week" : "weeks"
            case .month: unitLabel = periodValue == 1 ? "month" : "months"
            case .year: unitLabel = periodValue == 1 ? "year" : "years"
            @unknown default: unitLabel = "period"
            }

            if introOffer.paymentMode == .freeTrial {
                let durationUnit: String
                switch periodUnit {
                case .day: durationUnit = "day"
                case .week: durationUnit = "week"
                case .month: durationUnit = "month"
                case .year: durationUnit = "year"
                @unknown default: durationUnit = "period"
                }
                return "\(periodValue)-\(durationUnit) free trial"
            } else {
                return "Intro: \(introOffer.displayPrice) for \(periodValue) \(unitLabel)"
            }
        }()

        return StoreProductModel(
            productId: product.id,
            planCode: planCode,
            displayName: product.displayName,
            description: product.description,
            priceDisplay: product.displayPrice,
            billingPeriodLabel: billingPeriodLabel,
            hasIntroOffer: product.subscription?.introductoryOffer?.paymentMode == .freeTrial,
            introOfferDisplayText: introOfferText,
            isEligibleForIntroOffer: isEligibleForIntro,
            isFeatured: isFeatured,
            savingsText: savingsText
        )
    }
}
