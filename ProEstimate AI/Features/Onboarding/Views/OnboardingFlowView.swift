import SwiftUI

/// Full-screen 4-page onboarding carousel shown once after signup.
///
/// Hosts a paged `TabView` over `OnboardingViewModel.Page`, a shared
/// orange-tinted gradient backdrop, and a top-right Skip button that
/// hides on both the permissions page (App Store Guideline 5.1.1(iv)
/// compliance — the user must always proceed to the system permission
/// prompt) and the final offer page. The `onComplete` closure is invoked
/// exactly once — from Skip, from the offer page's continue-free path,
/// or after the trial paywall closes.
struct OnboardingFlowView: View {
    @State private var viewModel = OnboardingViewModel()
    @State private var trialPaywall: PaywallDecision?
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            backgroundGradient

            TabView(selection: Binding(
                get: { viewModel.currentPage },
                set: { viewModel.currentPage = $0 }
            )) {
                OnboardingWelcomePage(
                    onPrimary: advance,
                    onSkip: complete
                )
                .tag(OnboardingViewModel.Page.welcome)

                OnboardingValuePropPage(
                    onPrimary: advance,
                    onSkip: complete
                )
                .tag(OnboardingViewModel.Page.valueProp)

                OnboardingPermissionsPage(
                    viewModel: viewModel,
                    onContinue: advance
                )
                .tag(OnboardingViewModel.Page.permissions)

                OnboardingOfferPage(
                    onStartTrial: presentTrial,
                    onContinueFree: complete
                )
                .tag(OnboardingViewModel.Page.offer)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .animation(.easeInOut(duration: 0.3), value: viewModel.currentPage)

            skipOverlay
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .sheet(item: $trialPaywall) { decision in
            // Reuse the production paywall — full StoreKit flow, 3.1.2 disclosures,
            // and restore-purchases support. On success or dismiss we complete
            // onboarding either way so the user lands in the app.
            PaywallHostView(decision: decision) {
                trialPaywall = nil
                complete()
            }
        }
    }

    // MARK: - Actions

    private func advance() {
        withAnimation(.easeInOut(duration: 0.3)) {
            viewModel.advance()
        }
    }

    private func complete() {
        onComplete()
    }

    private func presentTrial() {
        trialPaywall = .onboardingOffer
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        // Flat charcoal canvas with a subtle warm-to-dark vertical wash —
        // the previous top-anchored orange RadialGradient was reading as
        // a "glow" behind the hero badges and competing with the orange
        // brand glyphs inside each page. Pulling it removes the visual
        // double-up while keeping the page distinct from the system
        // background via the bottom-darkening linear gradient.
        ZStack {
            ColorTokens.overlayBackground
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.clear,
                    ColorTokens.overlayAccent.opacity(0.7),
                    ColorTokens.overlayBackground,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Skip Overlay

    private var skipOverlay: some View {
        VStack {
            HStack {
                Spacer()

                // Skip is suppressed on the permissions page (App Store
                // 5.1.1(iv) requires the user to always proceed to the
                // system permission prompt) and on the terminal offer page.
                if viewModel.currentPage != .permissions && !viewModel.currentPage.isLast {
                    Button(action: complete) {
                        Text("Skip")
                            .font(TypographyTokens.subheadline)
                            .foregroundStyle(ColorTokens.onDarkSecondary)
                            .padding(.vertical, SpacingTokens.xs)
                            .padding(.horizontal, SpacingTokens.sm)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .accessibilityLabel("Skip onboarding")
                }
            }
            .padding(.horizontal, SpacingTokens.lg)
            // Sit the Skip pill flush with the top safe-area edge — the
            // 8pt cushion previously pushed it noticeably below the
            // status bar on iPad, leaving a dead band of empty header
            // space.
            .padding(.top, 0)

            Spacer()
        }
    }
}

#Preview {
    OnboardingFlowView(onComplete: {})
}
