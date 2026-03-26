import SwiftUI

struct LoadingStateView: View {
    var message: String = "Loading..."

    var body: some View {
        VStack(spacing: SpacingTokens.md) {
            ProgressView()
                .controlSize(.large)
                .tint(ColorTokens.primaryOrange)

            Text(message)
                .font(TypographyTokens.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
