import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var ctaTitle: String? = nil
    var ctaAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: SpacingTokens.md) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(ColorTokens.primaryOrange.opacity(0.6))

            Text(title)
                .font(TypographyTokens.title3)

            if let subtitle {
                Text(subtitle)
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let ctaTitle, let ctaAction {
                PrimaryCTAButton(title: ctaTitle, action: ctaAction)
                    .frame(maxWidth: 240)
                    .padding(.top, SpacingTokens.xs)
            }
        }
        .padding(SpacingTokens.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
