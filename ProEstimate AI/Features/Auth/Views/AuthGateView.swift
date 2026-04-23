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

    /// Hard deadline for the cold-launch session restore. If the backend is
    /// unreachable (Railway cold start, offline, DNS hiccup), we drop the
    /// stored tokens and show login rather than trap the user at the splash.
    private static let restoreTimeout: Duration = .seconds(8)

    private func restoreSession() async {
        if TokenStore.shared.hasTokens {
            let result = await fetchSessionWithTimeout()
            switch result {
            case .success(let user, let company):
                appState.currentUser = AppState.CurrentUser(
                    id: user.id,
                    email: user.email,
                    fullName: user.fullName,
                    avatarURL: user.avatarURL
                )
                appState.currentCompany = AppState.CurrentCompany.from(company)
                appState.isAuthenticated = true

            case .failure:
                // Auth failed, network failed, or the call didn't come back in
                // time — clear tokens so the user is routed to login instead
                // of staring at a stuck splash.
                TokenStore.shared.clearTokens()
            }
        }

        // Brief delay so the splash is visible even on fast restore.
        try? await Task.sleep(for: .milliseconds(400))
        isRestoring = false
    }

    private enum SessionOutcome {
        case success(user: User, company: Company)
        case failure
    }

    /// Fetch the current user + company, racing against `restoreTimeout` so a
    /// hanging backend never blocks launch.
    private func fetchSessionWithTimeout() async -> SessionOutcome {
        await withTaskGroup(of: SessionOutcome.self) { group in
            group.addTask {
                do {
                    async let userTask: User = APIClient.shared.request(.getMe)
                    async let companyTask: Company = APIClient.shared.request(.getCompany)
                    return .success(user: try await userTask, company: try await companyTask)
                } catch {
                    return .failure
                }
            }

            group.addTask {
                try? await Task.sleep(for: Self.restoreTimeout)
                return .failure
            }

            // Take whichever task completes first, cancel the other.
            let outcome = await group.next() ?? .failure
            group.cancelAll()
            return outcome
        }
    }
}
