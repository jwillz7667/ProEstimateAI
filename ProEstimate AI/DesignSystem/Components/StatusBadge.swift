import SwiftUI

struct StatusBadge: View {
    let text: String
    let style: Style

    enum Style {
        case success, warning, error, info, neutral

        var backgroundColor: Color {
            switch self {
            case .success: ColorTokens.success.opacity(0.15)
            case .warning: ColorTokens.warning.opacity(0.15)
            case .error: ColorTokens.error.opacity(0.15)
            case .info: ColorTokens.primaryOrange.opacity(0.15)
            case .neutral: Color.gray.opacity(0.15)
            }
        }

        var foregroundColor: Color {
            switch self {
            case .success: ColorTokens.success
            case .warning: ColorTokens.warning
            case .error: ColorTokens.error
            case .info: ColorTokens.primaryOrange
            case .neutral: .gray
            }
        }
    }

    var body: some View {
        Text(text)
            .font(TypographyTokens.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, SpacingTokens.xs)
            .padding(.vertical, SpacingTokens.xxs)
            .background(style.backgroundColor, in: Capsule())
            .foregroundStyle(style.foregroundColor)
    }
}
