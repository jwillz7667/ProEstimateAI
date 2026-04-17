import SwiftUI

/// Full-screen 3-page onboarding carousel shown once after signup.
///
/// Hosts a paged `TabView` over `OnboardingViewModel.Page`, a shared
/// orange-tinted gradient backdrop, and a persistent top-right Skip button.
/// The `onComplete` closure is invoked exactly once — either from the final
/// page's CTA, from Skip on any page, or from the "Not Now" permission button.
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
        ZStack {
            ColorTokens.overlayBackground
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    ColorTokens.primaryOrange.opacity(0.35),
                    ColorTokens.primaryOrange.opacity(0.08),
                    ColorTokens.overlayBackground.opacity(0),
                ],
                center: .top,
                startRadius: 40,
                endRadius: 520
            )
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

                // Skip is suppressed on the terminal page because the
                // "Not Now" secondary button already fulfills that role.
                if !viewModel.currentPage.isLast {
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
            .padding(.top, SpacingTokens.xs)

            Spacer()
        }
    }
}

#Preview {
    OnboardingFlowView(onComplete: {})
}
