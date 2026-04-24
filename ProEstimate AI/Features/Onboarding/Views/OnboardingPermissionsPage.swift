import SwiftUI

/// Third onboarding screen — informs the user about the camera feature,
/// then triggers the iOS system permission prompt. Per App Store
/// Guideline 5.1.1(iv), this screen must NOT offer a dismiss button:
/// tapping the primary CTA always proceeds to the system prompt, and
/// the flow advances regardless of the user's decision.
struct OnboardingPermissionsPage: View {
    @Bindable var viewModel: OnboardingViewModel
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: SpacingTokens.xl) {
            Spacer(minLength: SpacingTokens.xxl)

            ZStack {
                Circle()
                    .fill(ColorTokens.primaryOrange.opacity(0.18))
                    .frame(width: 180, height: 180)
                    .blur(radius: 24)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                ColorTokens.primaryOrange,
                                ColorTokens.primaryOrange.opacity(0.82),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 128, height: 128)
                    .shadow(color: ColorTokens.primaryOrange.opacity(0.55), radius: 24, x: 0, y: 12)

                Image(systemName: "camera.aperture")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
            .padding(.bottom, SpacingTokens.md)

            VStack(spacing: SpacingTokens.sm) {
                Text("Capture Your Projects")
                    .font(TypographyTokens.largeTitle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(ColorTokens.onDarkPrimary)

                Text("ProEstimate AI uses your camera to snap before‑and‑after photos of every job and turn them straight into AI‑powered estimates and client‑ready proposals.")
                    .font(TypographyTokens.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(ColorTokens.onDarkSecondary)
                    .padding(.horizontal, SpacingTokens.md)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            PrimaryCTAButton(
                title: "Continue",
                isLoading: viewModel.isRequestingPermission,
                action: {
                    Task {
                        await viewModel.requestCameraAccess()
                        onContinue()
                    }
                }
            )
            .padding(.bottom, SpacingTokens.xxl)
        }
        .padding(.horizontal, SpacingTokens.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        OnboardingPermissionsPage(
            viewModel: OnboardingViewModel(),
            onContinue: {}
        )
    }
}
