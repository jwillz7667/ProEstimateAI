import SwiftUI

/// Root view that checks authentication state and routes to either
/// the main tab interface or the login screen with an animated transition.
/// On cold launch, attempts to restore a previous session from stored tokens.
struct AuthGateView: View {
    @Environment(AppState.self) private var appState
    @Environment(OnboardingStore.self) private var onboardingStore
    @Environment(EntitlementStore.self) private var entitlementStore
    @Environment(UsageMeterStore.self) private var usageMeterStore
    @State private var isRestoring = true
    @State private var hasRestoreError = false

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
            } else if hasRestoreError {
                VStack(spacing: SpacingTokens.md) {
                    RetryStateView(message: String(localized: "auth.restore.error")) {
                        Task { await restoreSession() }
                    }
                    // A deleted account or other persistent server failure
                    // must not trap the user on a retry-only screen.
                    Button("Sign Out", role: .destructive) {
                        appState.signOut(
                            entitlementStore: entitlementStore,
                            usageMeterStore: usageMeterStore
                        )
                        hasRestoreError = false
                    }
                    .padding(.bottom, SpacingTokens.xxl)
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
            VStack(spacing: SpacingTokens.lg) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 140, height: 140)
                        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 6)

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
    /// unreachable, retain credentials and offer retry instead of treating
    /// a connection failure as an expired login.
    private static let restoreTimeout: Duration = .seconds(8)

    private func restoreSession() async {
        isRestoring = true
        hasRestoreError = false
        let sessionID = TokenStore.shared.sessionIdentifier
        if TokenStore.shared.hasTokens {
            let result = await fetchSessionWithTimeout()
            guard TokenStore.shared.sessionIdentifier == sessionID else {
                isRestoring = false
                return
            }
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

            case .failure(let isUnauthorized):
                if isUnauthorized {
                    TokenStore.shared.clearTokens()
                } else {
                    hasRestoreError = true
                }
            }
        }

        // Brief delay so the splash is visible even on fast restore.
        try? await Task.sleep(for: .milliseconds(400))
        isRestoring = false
    }

    private enum SessionOutcome {
        case success(user: User, company: Company)
        case failure(isUnauthorized: Bool)
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
                } catch let error as APIError where error == .unauthorized {
                    return .failure(isUnauthorized: true)
                } catch {
                    return .failure(isUnauthorized: false)
                }
            }

            group.addTask {
                try? await Task.sleep(for: Self.restoreTimeout)
                return .failure(isUnauthorized: false)
            }

            // Take whichever task completes first, cancel the other.
            let outcome = await group.next() ?? .failure(isUnauthorized: false)
            group.cancelAll()
            return outcome
        }
    }
}
