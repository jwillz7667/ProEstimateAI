import Foundation
import Observation

/// Centralized paywall presentation coordinator.
/// Any view or viewmodel can trigger a paywall by calling `present(_:)`.
/// The app root observes `activeDecision` and presents `PaywallHostView` as a sheet.
@Observable
final class PaywallPresenter {
    var activeDecision: PaywallDecision?

    func present(_ decision: PaywallDecision) {
        activeDecision = decision
    }

    func dismiss() {
        activeDecision = nil
    }
}
