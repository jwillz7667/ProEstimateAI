import SwiftUI

/// Root of the Quotes tab — unified estimate / proposal / invoice pipeline.
/// Owns the `quotesPath` NavigationStack. Wraps the existing
/// `EstimateListView` until task #7 replaces the body with the Quote Center.
struct QuotesRootView: View {
    var body: some View {
        EstimateListView()
    }
}
