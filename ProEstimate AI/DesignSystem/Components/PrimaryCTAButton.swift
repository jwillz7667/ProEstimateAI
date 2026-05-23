import SwiftUI

/// Primary CTA button. Defaults to orange; switch to `.dark` for the
/// black "SIGN IN" / "Generate Vision" treatment from the overhaul screenshots.
struct PrimaryCTAButton: View {
    let title: String
    var icon: String? = nil
    var trailingIcon: String? = nil
    var isLoading: Bool = false
    var isDisabled: Bool = false
    var style: Style = .orange
    let action: () -> Void

    enum Style {
        case orange
        case dark

        var background: Color {
            switch self {
            case .orange: ColorTokens.primaryOrange
            case .dark: Color.black
            }
        }

        var disabledBackground: Color {
            switch self {
            case .orange: ColorTokens.primaryOrange.opacity(0.4)
            case .dark: Color.black.opacity(0.4)
            }
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: SpacingTokens.xs) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    if let icon {
                        Image(systemName: icon)
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(title)
                        .font(TypographyTokens.buttonPrimary)
                        .tracking(0.6)
                    if let trailingIcon {
                        Image(systemName: trailingIcon)
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, SpacingTokens.lg)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.button)
                    .fill(isDisabled ? style.disabledBackground : style.background)
            )
            .foregroundStyle(.white)
        }
        .disabled(isDisabled || isLoading)
    }
}
