import SwiftUI

/// Pastel pill used for project / quote / invoice statuses.
/// Visual language matches the overhaul screenshots — soft tinted background,
/// readable mid-saturation foreground, no border.
struct StatusBadge: View {
    let text: String
    let style: Style

    enum Style {
        case success, warning, error, info, neutral, accent

        var background: Color {
            switch self {
            case .success: ColorTokens.success.opacity(0.14)
            case .warning: ColorTokens.warning.opacity(0.16)
            case .error: ColorTokens.error.opacity(0.14)
            case .info: ColorTokens.pillBackground
            case .neutral: ColorTokens.background
            case .accent: ColorTokens.accentSoft
            }
        }

        var foreground: Color {
            switch self {
            case .success: ColorTokens.success
            case .warning: ColorTokens.warning
            case .error: ColorTokens.error
            case .info: ColorTokens.pillForeground
            case .neutral: ColorTokens.textSecondary
            case .accent: ColorTokens.primaryOrange
            }
        }
    }

    var body: some View {
        Text(text)
            .font(TypographyTokens.pillLabel)
            .padding(.horizontal, SpacingTokens.sm)
            .padding(.vertical, 5)
            .background(style.background, in: Capsule())
            .foregroundStyle(style.foreground)
    }
}
