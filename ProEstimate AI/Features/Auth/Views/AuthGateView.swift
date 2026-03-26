import SwiftUI

/// Root view that checks authentication state and routes to either
/// the main tab interface or the login screen with an animated transition.
struct AuthGateView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.isAuthenticated {
                MainTabView(appState: appState)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                LoginView()
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: appState.isAuthenticated)
    }
}
