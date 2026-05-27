import SwiftUI

/// Bordered secondary action — neutral by default, orange when `emphasis: .accent`.
struct SecondaryButton: View {
    let title: String
    var icon: String? = nil
    var isLoading: Bool = false
    var emphasis: Emphasis = .neutral
    let action: () -> Void

    enum Emphasis {
        case neutral
        case accent

        var foreground: Color {
            switch self {
            case .neutral: ColorTokens.textPrimary
            case .accent: ColorTokens.primaryOrange
            }
        }

        var stroke: Color {
            switch self {
            case .neutral: ColorTokens.cardStroke
            case .accent: ColorTokens.primaryOrange
            }
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: SpacingTokens.xs) {
                if isLoading {
                    ProgressView()
                        .tint(emphasis.foreground)
                } else {
                    if let icon {
                        Image(systemName: icon)
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(title)
                        .font(TypographyTokens.buttonSecondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, SpacingTokens.md)
            .background(ColorTokens.surface, in: RoundedRectangle(cornerRadius: RadiusTokens.button))
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.button)
                    .strokeBorder(emphasis.stroke, lineWidth: 1)
            )
            .foregroundStyle(emphasis.foreground)
        }
        .disabled(isLoading)
    }
}
