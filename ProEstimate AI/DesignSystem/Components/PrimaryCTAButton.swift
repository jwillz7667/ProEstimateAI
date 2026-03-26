import SwiftUI

struct PrimaryCTAButton: View {
    let title: String
    var icon: String? = nil
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SpacingTokens.xs) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
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
                    .fill(isDisabled ? ColorTokens.primaryOrange.opacity(0.4) : ColorTokens.primaryOrange)
            )
            .foregroundStyle(.white)
        }
        .disabled(isDisabled || isLoading)
    }
}
