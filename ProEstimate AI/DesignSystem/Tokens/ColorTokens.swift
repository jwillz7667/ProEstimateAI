import SwiftUI

enum ColorTokens {
    // MARK: - Primary
    static let primaryOrange = Color(hex: 0xFF9230)

    // MARK: - Brand Neutrals (from logo)
    static let brandDark = Color(hex: 0x1C1C1E)
    static let brandGray = Color(hex: 0x69717F)

    // MARK: - Backgrounds (adaptive light/dark)
    static let background = Color("Background", bundle: nil)
    static let surface = Color("Surface", bundle: nil)
    static let elevatedSurface = Color("ElevatedSurface", bundle: nil)

    // MARK: - Dark Mode Explicit (for overlays/cards in dark contexts)
    static let darkBackground = Color(UIColor.systemBackground)
    static let darkSurface = Color(UIColor.secondarySystemBackground)
    static let darkElevated = Color(UIColor.tertiarySystemBackground)
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

    // MARK: - Accent Colors (for category icons, status badges, toggles)
    static let accentBlue = Color(hex: 0x3B82F6)
    static let accentPurple = Color(hex: 0x8B5CF6)
    static let accentTeal = Color(hex: 0x14B8A6)
    static let accentGreen = Color(hex: 0x22C55E)
    static let accentRed = Color(hex: 0xEF4444)

    // MARK: - Surfaces for inputs/cards
    static let inputBackground = Color("InputBackground", bundle: nil)
    static let progressTrack = Color("ProgressTrack", bundle: nil)

    // MARK: - Form Inputs
    static let formFieldBackground = Color("InputBackground", bundle: nil)

    // MARK: - Overlay Surfaces (paywall + hero backdrops)
    /// Deep charcoal used as the primary paywall backdrop.
    static let overlayBackground = Color(hex: 0x0B0B0C)
    /// Warm mid-tone accent used as the gradient mid-stop on the paywall backdrop.
    static let overlayAccent = Color(hex: 0x1A0E05)

    // MARK: - On-Dark Text Opacity Scale
    /// For text rendered on top of overlayBackground / dark gradients.
    /// Opacity scale intentionally mirrors Apple's label hierarchy.
    static let onDarkPrimary = Color.white.opacity(0.92)
    static let onDarkSecondary = Color.white.opacity(0.70)
    static let onDarkTertiary = Color.white.opacity(0.55)
    static let onDarkQuaternary = Color.white.opacity(0.40)
    static let onDarkDisabled = Color.white.opacity(0.30)

    // MARK: - On-Dark Chrome (separators, hairlines, subtle fills)
    static let onDarkSeparator = Color.white.opacity(0.15)
    static let onDarkFillSubtle = Color.white.opacity(0.08)
}
