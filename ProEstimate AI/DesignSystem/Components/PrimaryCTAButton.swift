import SwiftUI

struct PrimaryCTAButton: View {
    let title: String
    var icon: String? = nil
    var trailingIcon: String? = nil
    var isLoading: Bool = false
    var isDisabled: Bool = false
    var style: Style = .orange
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    enum Style {
        case orange
        case dark
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: SpacingTokens.xs) {
                if isLoading {
                    ProgressView()
                        .tint(colorScheme == .light ? Color.black : Color.white)
                } else {
                    if let icon {
                        Image(systemName: icon)
                    }
                    Text(title)
                        .font(TypographyTokens.headline)
                    if let trailingIcon {
                        Image(systemName: trailingIcon)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SpacingTokens.sm)
            .padding(.horizontal, SpacingTokens.md)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.button)
                    .fill(isDisabled ? backgroundColor.opacity(0.4) : backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.button)
                    .strokeBorder(
                        borderColor,
                        lineWidth: borderWidth
                    )
            )
            .foregroundStyle(foregroundColor)
        }
        .disabled(isDisabled || isLoading)
    }

    private var foregroundColor: Color {
        switch style {
        case .orange:
            colorScheme == .light ? Color.black : Color.white
        case .dark:
            Color.white
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .orange:
            ColorTokens.primaryOrange
        case .dark:
            Color.black
        }
    }

    private var borderColor: Color {
        switch style {
        case .orange:
            colorScheme == .light ? Color.black : Color.clear
        case .dark:
            Color.clear
        }
    }

    private var borderWidth: CGFloat {
        switch style {
        case .orange:
            colorScheme == .light ? 2 : 0
        case .dark:
            0
        }
    }
}
