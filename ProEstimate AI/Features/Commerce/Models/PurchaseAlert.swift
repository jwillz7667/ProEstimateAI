import Foundation
import SwiftUI

/// Modal alert state for the paywall purchase + restore flows.
///
/// The paywall surfaces transactional outcomes through `.alert(...)` rather
/// than an inline banner so the user can never miss the result of their tap.
/// Each `Kind` carries its own copy + recovery actions, and `Context` lets
/// the same case (e.g. `.networkProblem`) wire its "Try Again" button to
/// either the purchase or the restore flow.
struct PurchaseAlert: Identifiable, Sendable {
    /// Unique per instance so SwiftUI re-presents the alert when the same
    /// kind fires twice in a row (retry → second network failure should
    /// still show the alert).
    let id = UUID()

    /// Semantic category — drives copy.
    let kind: Kind

    /// Which flow triggered the alert. Determines what "Try Again" does.
    let context: Context

    init(kind: Kind, context: Context = .purchase) {
        self.kind = kind
        self.context = context
    }

    enum Context: Sendable, Hashable {
        case purchase
        case restore
    }

    enum Kind: Sendable, Hashable {
        /// User tapped "Subscribe" with no plan selected (defensive — the
        /// view model normally seeds a default selection).
        case selectionRequired
        /// StoreKit returned `pending` (Ask to Buy / parental approval).
        case pendingApproval
        /// Local Apple ID does not match the ProEstimate account.
        case accountMismatch
        /// `AppStore.canMakePayments` is false — IAP disabled by Screen
        /// Time, MDM, or unsupported region.
        case paymentsNotAllowed
        /// JWS / signature verification failed on a transaction.
        case verificationFailed
        /// The selected StoreKit product couldn't be resolved.
        case productUnavailable
        /// Network round-trip failed — retryable.
        case networkProblem
        /// Unexpected error — body falls back to the inner message.
        case genericFailure(message: String)
        /// Restore completed but no active subscription was found.
        case nothingToRestore
        /// Restore threw a non-purchase error (rare).
        case restoreFailed
    }

    // MARK: - Static factories
    //
    // Most call sites are in the purchase flow, so the no-arg factories
    // default to `Context.purchase`. The two restore-only cases bake in
    // `Context.restore` since they cannot occur during a purchase.

    static let selectionRequired = PurchaseAlert(kind: .selectionRequired)
    static let pendingApproval = PurchaseAlert(kind: .pendingApproval)
    static let accountMismatch = PurchaseAlert(kind: .accountMismatch)
    static let paymentsNotAllowed = PurchaseAlert(kind: .paymentsNotAllowed)
    static let verificationFailed = PurchaseAlert(kind: .verificationFailed)
    static let productUnavailable = PurchaseAlert(kind: .productUnavailable)
    static let networkProblem = PurchaseAlert(kind: .networkProblem)
    static func genericFailure(message: String) -> PurchaseAlert {
        PurchaseAlert(kind: .genericFailure(message: message))
    }
    static let restoreNothingToRestore = PurchaseAlert(kind: .nothingToRestore, context: .restore)
    static let restoreFailed = PurchaseAlert(kind: .restoreFailed, context: .restore)

    // MARK: - Display

    /// Localized headline shown at the top of the alert.
    var title: String {
        switch kind {
        case .selectionRequired:
            return String(
                localized: "purchase.alert.selection_required.title",
                defaultValue: "Choose a Plan"
            )
        case .pendingApproval:
            return String(
                localized: "purchase.alert.pending.title",
                defaultValue: "Approval Required"
            )
        case .accountMismatch:
            return String(
                localized: "purchase.alert.account_mismatch.title",
                defaultValue: "Apple ID Mismatch"
            )
        case .paymentsNotAllowed:
            return String(
                localized: "purchase.alert.payments_not_allowed.title",
                defaultValue: "Purchases Disabled"
            )
        case .verificationFailed:
            return String(
                localized: "purchase.alert.verification_failed.title",
                defaultValue: "Couldn't Verify Purchase"
            )
        case .productUnavailable:
            return String(
                localized: "purchase.alert.product_unavailable.title",
                defaultValue: "Plan Unavailable"
            )
        case .networkProblem:
            return String(
                localized: "purchase.alert.network.title",
                defaultValue: "Connection Issue"
            )
        case .genericFailure:
            // A `genericFailure` raised mid-restore reads as "Couldn't Restore",
            // not "Purchase Failed" — match the user's expectation of which
            // flow they were in.
            return context == .restore
                ? String(
                    localized: "purchase.alert.restore_failed.title",
                    defaultValue: "Couldn't Restore Purchases"
                )
                : String(
                    localized: "purchase.alert.generic_failure.title",
                    defaultValue: "Purchase Failed"
                )
        case .nothingToRestore:
            return String(
                localized: "purchase.alert.restore_nothing.title",
                defaultValue: "Nothing to Restore"
            )
        case .restoreFailed:
            return String(
                localized: "purchase.alert.restore_failed.title",
                defaultValue: "Couldn't Restore Purchases"
            )
        }
    }

    /// Localized body explaining what happened + recovery steps.
    var message: String {
        switch kind {
        case .selectionRequired:
            return String(
                localized: "purchase.alert.selection_required.message",
                defaultValue: "Pick a subscription plan to continue."
            )
        case .pendingApproval:
            return String(
                localized: "purchase.alert.pending.message",
                defaultValue: "Your purchase is waiting for approval. We'll unlock Pro features as soon as it's approved."
            )
        case .accountMismatch:
            return String(
                localized: "purchase.alert.account_mismatch.message",
                defaultValue: "We detected a different Apple ID than the one linked to your ProEstimate account. Sign out of the other Apple ID in Settings → App Store, or tap Restore Purchases if you've already subscribed."
            )
        case .paymentsNotAllowed:
            return String(
                localized: "purchase.alert.payments_not_allowed.message",
                defaultValue: "This Apple ID can't make purchases. Check Screen Time restrictions in Settings, or sign in with an account that supports In-App Purchases."
            )
        case .verificationFailed:
            return String(
                localized: "purchase.alert.verification_failed.message",
                defaultValue: "We couldn't verify your transaction. Please try again — your subscription will only be charged once."
            )
        case .productUnavailable:
            return String(
                localized: "purchase.alert.product_unavailable.message",
                defaultValue: "The plan you selected is temporarily unavailable. Please try again in a moment."
            )
        case .networkProblem:
            return String(
                localized: "purchase.alert.network.message",
                defaultValue: "Couldn't reach our servers. Check your connection and try again — your subscription won't be double-charged."
            )
        case .genericFailure(let message):
            return message
        case .nothingToRestore:
            return String(
                localized: "purchase.alert.restore_nothing.message",
                defaultValue: "We didn't find an active subscription on this Apple ID. If you previously subscribed with a different Apple ID, sign in with that account first."
            )
        case .restoreFailed:
            return String(
                localized: "purchase.alert.restore_failed.message",
                defaultValue: "Something went wrong while restoring purchases. Please check your connection and try again."
            )
        }
    }

    /// Recovery actions surfaced as buttons. SwiftUI uses the cancel-role
    /// button as the dismiss target, and the last default-role button is
    /// the visual primary — so for retry-style alerts the order is
    /// `[dismiss, tryAgain]`.
    var actions: [Action] {
        switch kind {
        case .selectionRequired,
             .pendingApproval,
             .productUnavailable,
             .nothingToRestore,
             .paymentsNotAllowed:
            return [.dismiss]
        case .accountMismatch:
            return [.dismiss, .restorePurchases]
        case .verificationFailed,
             .networkProblem,
             .genericFailure,
             .restoreFailed:
            return [.dismiss, .tryAgain]
        }
    }

    /// Discrete recovery action available from an alert button.
    enum Action: Sendable, Hashable {
        /// Close the alert without taking action. `.cancel` role.
        case dismiss
        /// Re-run the flow named by `PurchaseAlert.context` — purchase
        /// or restore.
        case tryAgain
        /// Trigger the restore flow regardless of which flow opened the
        /// alert (only surfaced for `.accountMismatch`).
        case restorePurchases

        /// Localized button label.
        var title: String {
            switch self {
            case .dismiss:
                return String(
                    localized: "purchase.alert.action.dismiss",
                    defaultValue: "OK"
                )
            case .tryAgain:
                return String(
                    localized: "purchase.alert.action.try_again",
                    defaultValue: "Try Again"
                )
            case .restorePurchases:
                return String(
                    localized: "purchase.alert.action.restore",
                    defaultValue: "Restore Purchases"
                )
            }
        }

        /// SwiftUI button role for visual hierarchy.
        var buttonRole: ButtonRole? {
            switch self {
            case .dismiss:
                return .cancel
            case .tryAgain, .restorePurchases:
                return nil
            }
        }
    }
}
