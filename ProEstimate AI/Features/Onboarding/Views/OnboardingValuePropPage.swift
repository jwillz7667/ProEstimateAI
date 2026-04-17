import SwiftUI

/// Second onboarding screen — three benefit rows that walk the user through
/// the core product loop (photo → AI preview → estimate).
struct OnboardingValuePropPage: View {
    let onPrimary: () -> Void
    let onSkip: () -> Void

    private let benefits: [Benefit] = [
        Benefit(
            icon: "camera.fill",
            title: "Snap a photo",
            subtitle: "Capture the space you want to remodel."
        ),
        Benefit(
            icon: "sparkles",
            title: "See it reimagined",
            subtitle: "Nano Banana generates a photorealistic preview with AI."
        ),
        Benefit(
            icon: "doc.text.fill",
            title: "Ship the estimate",
            subtitle: "Materials, labor, and pricing auto-fill. Export a branded PDF."
        ),
    ]

    var body: some View {
        VStack(spacing: SpacingTokens.xl) {
            Spacer(minLength: SpacingTokens.xxl)

            VStack(spacing: SpacingTokens.sm) {
                Text("How it works")
                    .font(TypographyTokens.largeTitle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(ColorTokens.onDarkPrimary)

                Text("Three steps from site visit to signed estimate.")
                    .font(TypographyTokens.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(ColorTokens.onDarkSecondary)
                    .padding(.horizontal, SpacingTokens.md)
            }

            VStack(spacing: SpacingTokens.md) {
                ForEach(benefits) { benefit in
                    BenefitRow(benefit: benefit)
                }
            }
            .padding(.top, SpacingTokens.sm)

            Spacer()

            VStack(spacing: SpacingTokens.sm) {
                PrimaryCTAButton(title: "Next", action: onPrimary)

                Button(action: onSkip) {
                    Text("Skip")
                        .font(TypographyTokens.subheadline)
                        .foregroundStyle(ColorTokens.onDarkSecondary)
                        .padding(.vertical, SpacingTokens.xs)
                }
                .accessibilityLabel("Skip onboarding")
            }
            .padding(.bottom, SpacingTokens.xxl)
        }
        .padding(.horizontal, SpacingTokens.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Row

private struct Benefit: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
}

private struct BenefitRow: View {
    let benefit: Benefit

    var body: some View {
        HStack(alignment: .top, spacing: SpacingTokens.md) {
            ZStack {
                RoundedRectangle(cornerRadius: RadiusTokens.button, style: .continuous)
                    .fill(ColorTokens.primaryOrange.opacity(0.18))
                    .frame(width: 48, height: 48)

                Image(systemName: benefit.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(ColorTokens.primaryOrange)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                Text(benefit.title)
                    .font(TypographyTokens.headline)
                    .foregroundStyle(ColorTokens.onDarkPrimary)

                Text(benefit.subtitle)
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(ColorTokens.onDarkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(SpacingTokens.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: RadiusTokens.card, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: RadiusTokens.card, style: .continuous)
                .strokeBorder(ColorTokens.onDarkSeparator, lineWidth: 1)
        )
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        OnboardingValuePropPage(onPrimary: {}, onSkip: {})
    }
}
