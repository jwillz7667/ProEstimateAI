import Foundation
import StoreKit
import os.log

/// Production implementation of `StoreKitCatalogProviding`.
/// Loads subscription products from the App Store using StoreKit 2 APIs
/// and checks introductory offer eligibility against the subscription group.
final class StoreKitCatalogService: StoreKitCatalogProviding {
    private let productIDs: Set<String>
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "StoreKitCatalog")

    /// Cached products after the first load to avoid redundant App Store calls.
    private var cachedProducts: [Product]?

    init(productIDs: Set<String>? = nil) {
        self.productIDs = productIDs ?? [
            AppConstants.monthlyProductID,
            AppConstants.annualProductID
        ]
    }

    // MARK: - StoreKitCatalogProviding

    func loadProducts() async throws -> [Product] {
        if let cached = cachedProducts {
            return cached
        }

        logger.info("Loading StoreKit products: \(self.productIDs)")

        do {
            let products = try await Product.products(for: productIDs)

            if products.isEmpty {
                logger.warning("No products returned from StoreKit for IDs: \(self.productIDs)")
            } else {
                logger.info("Loaded \(products.count) products from StoreKit")
            }

            cachedProducts = products
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

    func isEligibleForIntroOffer(groupID: String) async -> Bool {
        do {
            let products = try await loadProducts()

            // Find any product in the subscription group and check eligibility.
            guard let subscriptionProduct = products.first(where: { product in
                product.subscription?.subscriptionGroupID == groupID
            }) else {
                logger.warning("No products found in subscription group: \(groupID)")
                return false
            }

            let isEligible = await subscriptionProduct.subscription?.isEligibleForIntroOffer ?? false
            logger.info("Intro offer eligibility for group \(groupID): \(isEligible)")
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
        let planCode: PlanCode = product.id == AppConstants.annualProductID
            ? .proAnnual
            : .proMonthly

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
                return "\(periodValue)-\(unitLabel) free trial"
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
            hasIntroOffer: product.subscription?.introductoryOffer != nil,
            introOfferDisplayText: introOfferText,
            isEligibleForIntroOffer: isEligibleForIntro,
            isFeatured: isFeatured,
            savingsText: savingsText
        )
    }
}
