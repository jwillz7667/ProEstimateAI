/// The standalone runner does not render SwiftUI. This supplies only the
/// badge-style token referenced by the actual Invoice model's display helper.
enum StatusBadge {
    enum Style {
        case neutral, warning, error, success, info
    }
}

/// The runner injects a deterministic service into every view-model test.
/// Resolve the unused production default initializer without networking code.
typealias LiveInvoiceService = MockInvoiceService

/// The feature gate's catalog loader is not exercised against the network.
typealias CommerceAPIClient = MockCommerceAPIClient
