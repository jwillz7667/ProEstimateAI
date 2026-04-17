import SwiftUI

/// Third onboarding screen — primes the camera permission request.
/// Tapping "Enable Camera" triggers the AVFoundation system prompt; the
/// flow advances regardless of the user's decision so they are never
/// trapped on this screen.
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
                Text("Enable Camera Access")
                    .font(TypographyTokens.largeTitle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(ColorTokens.onDarkPrimary)

                Text("ProEstimate AI works best when you can snap project photos directly from the app. You can always skip and add photos later.")
                    .font(TypographyTokens.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(ColorTokens.onDarkSecondary)
                    .padding(.horizontal, SpacingTokens.md)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            VStack(spacing: SpacingTokens.sm) {
                PrimaryCTAButton(
                    title: "Enable Camera",
                    icon: "camera.fill",
                    isLoading: viewModel.isRequestingPermission,
                    action: {
                        Task {
                            await viewModel.requestCameraAccess()
                            onContinue()
                        }
                    }
                )

                Button {
                    onContinue()
                } label: {
                    Text("Not Now")
                        .font(TypographyTokens.subheadline)
                        .foregroundStyle(ColorTokens.onDarkSecondary)
                        .padding(.vertical, SpacingTokens.xs)
                }
            }
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
