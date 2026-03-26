import SwiftUI

struct RetryStateView: View {
    let message: String
    let retryAction: () -> Void

    var body: some View {
        VStack(spacing: SpacingTokens.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(ColorTokens.warning)

            Text(message)
                .font(TypographyTokens.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            SecondaryButton(title: "Try Again", icon: "arrow.clockwise", action: retryAction)
                .frame(maxWidth: 200)
        }
        .padding(SpacingTokens.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
