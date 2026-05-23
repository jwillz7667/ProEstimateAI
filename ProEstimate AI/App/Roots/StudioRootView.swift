import SwiftUI

/// Root of the Studio tab — the AI Remodel Studio entry point.
/// `QuickGenerateView` ships its own NavigationStack so the close / generate
/// toolbar sits naturally inside the same context that handles the result
/// and error phases.
struct StudioRootView: View {
    var body: some View {
        QuickGenerateView()
    }
}
