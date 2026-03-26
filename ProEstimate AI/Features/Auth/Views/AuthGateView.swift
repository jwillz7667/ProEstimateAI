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
        .onChange(of: appState.isAuthenticated) { _, isAuth in
            if isAuth {
                // Dismiss keyboard when transitioning to main app
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
        .task {
            await restoreSession()
        }
    }

    private var splashView: some View {
        VStack(spacing: SpacingTokens.lg) {
            Image("housd-icon-light")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 72)

            Text("ProEstimate AI")
                .font(TypographyTokens.largeTitle)

            ProgressView()
                .tint(ColorTokens.primaryOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func restoreSession() async {
        if TokenStore.shared.hasTokens {
            do {
                async let userTask: User = APIClient.shared.request(.getMe)
                async let companyTask: Company = APIClient.shared.request(.getCompany)

                let user = try await userTask
                let company = try await companyTask

                appState.currentUser = AppState.CurrentUser(
                    id: user.id,
                    email: user.email,
                    fullName: user.fullName,
                    avatarURL: user.avatarURL
                )
                appState.currentCompany = AppState.CurrentCompany(
                    id: company.id,
                    name: company.name,
                    logoURL: company.logoURL
                )
                appState.isAuthenticated = true
            } catch {
                // Token refresh failed or network error — clear tokens, show login
                TokenStore.shared.clearTokens()
            }
        }

        // Brief delay so splash is visible even on fast restore
        try? await Task.sleep(for: .milliseconds(400))
        isRestoring = false
    }
}
