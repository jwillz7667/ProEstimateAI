import SwiftUI

struct SecondaryButton: View {
    let title: String
    var icon: String? = nil
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SpacingTokens.xs) {
                if isLoading {
                    ProgressView()
                        .tint(ColorTokens.primaryOrange)
                } else {
                    if let icon {
                        Image(systemName: icon)
                    }
                    Text(title)
                        .font(TypographyTokens.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SpacingTokens.sm)
            .padding(.horizontal, SpacingTokens.md)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.button)
                    .strokeBorder(ColorTokens.primaryOrange, lineWidth: 1.5)
            )
            .foregroundStyle(ColorTokens.primaryOrange)
        }
        .disabled(isLoading)
    }
}
