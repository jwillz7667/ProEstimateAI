import SwiftUI

/// Root view that checks authentication state and routes to either
/// the main tab interface or the login screen with an animated transition.
/// On cold launch, attempts to restore a previous session from stored tokens.
struct AuthGateView: View {
    @Environment(AppState.self) private var appState
    @State private var isRestoring = true

    var body: some View {
        Group {
            if isRestoring {
                splashView
            } else if appState.isAuthenticated {
                MainTabView(appState: appState)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                LoginView()
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: appState.isAuthenticated)
        .animation(.easeInOut(duration: 0.25), value: isRestoring)
        .task {
            await restoreSession()
        }
    }

    private var splashView: some View {
        VStack(spacing: SpacingTokens.lg) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 56))
                .foregroundStyle(ColorTokens.primaryOrange)

            Text("ProEstimate AI")
                .font(TypographyTokens.largeTitle)

            ProgressView()
                .tint(ColorTokens.primaryOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func restoreSession() async {
        if TokenStore.shared.hasTokens {
            // Tokens exist — restore session with mock user data for now.
            // When the backend exists, we'd validate the token here.
            appState.currentUser = AppState.CurrentUser(
                id: "restored-user",
                email: "user@proestimate.ai",
                fullName: "Restored User",
                avatarURL: nil
            )
            appState.currentCompany = AppState.CurrentCompany(
                id: "restored-company",
                name: "My Company",
                logoURL: nil
            )
            appState.isAuthenticated = true
        }

        // Brief delay so splash is visible even on fast restore
        try? await Task.sleep(for: .milliseconds(400))
        isRestoring = false
    }
}
