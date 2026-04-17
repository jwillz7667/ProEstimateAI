import Foundation
import Observation

/// Lightweight in-memory event bus for cross-feature change notifications
/// that don't warrant a full service dependency.
///
/// Views observe `@Observable` token counters via `.onChange(of:)` so they can
/// refresh when another part of the app mutates backend state the view cares
/// about — e.g., Dashboard revenue needs to pick up an invoice that was just
/// marked paid on a different screen.
///
/// Counters are preferred over timestamps because they are strictly monotonic
/// (no clock skew) and because `.onChange` fires even for rapid successive
/// updates that share a second.
@MainActor
@Observable
final class AppEventBus {
    /// Shared process-wide bus. Inject via `.environment(AppEventBus.shared)`.
    static let shared = AppEventBus()

    /// Incremented whenever a payment-affecting change happens
    /// (invoice marked paid, payment refunded, invoice deleted).
    /// Dashboard and revenue-summary views should observe this.
    private(set) var paymentEventToken: Int = 0

    /// Incremented whenever a project-level mutation happens
    /// (project created/deleted/status changed).
    private(set) var projectEventToken: Int = 0

    /// Note a payment-state change. Safe to call from any `@MainActor` context.
    func notePaymentChange() {
        paymentEventToken &+= 1
    }

    /// Note a project-level change.
    func noteProjectChange() {
        projectEventToken &+= 1
    }
}
