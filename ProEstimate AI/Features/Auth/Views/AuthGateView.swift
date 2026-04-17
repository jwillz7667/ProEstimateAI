import SwiftUI

/// Root view that checks authentication state and routes to either
/// the main tab interface or the login screen with an animated transition.
/// On cold launch, attempts to restore a previous session from stored tokens.
struct AuthGateView: View {
    @Environment(AppState.self) private var appState
    @Environment(OnboardingStore.self) private var onboardingStore
    @State private var isRestoring = true

    var body: some View {
        Group {
            if isRestoring {
                splashView
            } else if appState.isAuthenticated {
                if onboardingStore.hasCompletedOnboarding {
                    MainTabView(appState: appState)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    OnboardingFlowView {
                        onboardingStore.markCompleted()
                    }
                    .transition(.opacity)
                }
            } else {
                LoginView()
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: appState.isAuthenticated)
        .animation(.easeInOut(duration: 0.35), value: onboardingStore.hasCompletedOnboarding)
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
        ZStack {
            // Subtle orange radial glow behind logo
            RadialGradient(
                colors: [
                    ColorTokens.primaryOrange.opacity(0.08),
                    Color.clear,
                ],
                center: .center,
                startRadius: 40,
                endRadius: 260
            )
            .ignoresSafeArea()

            VStack(spacing: SpacingTokens.lg) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 140, height: 140)
                        .shadow(color: ColorTokens.primaryOrange.opacity(0.3), radius: 20, x: 0, y: 8)

                    Image("housd-icon-light")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 80)
                }

                Text("ProEstimate")
                    .font(.system(size: 32, weight: .bold, design: .rounded))

                Spacer()

                VStack(spacing: SpacingTokens.sm) {
                    ProgressView()
                        .tint(ColorTokens.primaryOrange)
                        .controlSize(.regular)

                    Text("Loading your workspace...")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, SpacingTokens.huge)
            }
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
