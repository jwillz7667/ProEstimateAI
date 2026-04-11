import SwiftUI

enum ColorTokens {
    // MARK: - Primary
    static let primaryOrange = Color(hex: 0xF97316)

    // MARK: - Brand Neutrals (from logo)
    static let brandDark = Color(hex: 0x1C1C1E)
    static let brandGray = Color(hex: 0x69717F)

    // MARK: - Backgrounds (adaptive light/dark)
    static let background = Color("Background", bundle: nil)
    static let surface = Color("Surface", bundle: nil)
    static let elevatedSurface = Color("ElevatedSurface", bundle: nil)

    // MARK: - Dark Mode Explicit (for overlays/cards in dark contexts)
    static let darkBackground = Color(hex: 0x000000)
    static let darkSurface = Color(hex: 0x0A0A0A)
    static let darkElevated = Color(hex: 0x1C1C1E)
    static let cardOverlay = Color("CardOverlay", bundle: nil)
    static let subtleBorder = Color("SubtleBorder", bundle: nil)

    // MARK: - Legacy aliases
    static let lightBackground = Color("Background", bundle: nil)
    static let lightSurface = Color("Surface", bundle: nil)

    // MARK: - Borders
    static let border = Color(.separator)
    static let lightBorder = Color(.separator)

    // MARK: - Text
    static let primaryText = Color(.label)
    static let secondaryText = Color(.secondaryLabel)
    static let lightPrimaryText = Color(.label)
    static let lightSecondaryText = Color(.secondaryLabel)
    static let tertiaryText = Color(.tertiaryLabel)

    // MARK: - Semantic
    static let success = Color(hex: 0x22C55E)
    static let warning = Color(hex: 0xF59E0B)
    static let error = Color(hex: 0xEF4444)

    // MARK: - Surfaces for inputs/cards
    static let inputBackground = Color("InputBackground", bundle: nil)
    static let progressTrack = Color("ProgressTrack", bundle: nil)
}
