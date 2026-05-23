import SwiftUI

enum ColorTokens {
    // MARK: - Primary Brand

    /// ProEstimate orange (#F97316). Used for primary CTAs, status accents, and selection highlights.
    static let primaryOrange = Color(hex: 0xF97316)
    /// Soft warm tint behind the primary orange (used for selected chips, hero subtle fills).
    static let accentSoft = Color("AccentSoft", bundle: nil)

    // MARK: - Brand Neutrals (logo-derived)

    static let brandDark = Color(hex: 0x0E1A2E)
    static let brandGray = Color(hex: 0x6B7280)

    // MARK: - Canvas / Surfaces (adaptive)

    /// Outer screen background — soft cool gray in light, near-black in dark.
    static let background = Color("Background", bundle: nil)
    /// Card surface — pure white in light mode.
    static let surface = Color("Surface", bundle: nil)
    /// Elevated surface — slight lift above `surface` in dark mode; white in light mode.
    static let elevatedSurface = Color("ElevatedSurface", bundle: nil)

    // MARK: - Semantic Text (adaptive — prefer these over Apple's labels for brand consistency)

    static let textPrimary = Color("TextPrimary", bundle: nil)
    static let textSecondary = Color("TextSecondary", bundle: nil)
    static let textTertiary = Color("TextTertiary", bundle: nil)

    // MARK: - Strokes / Borders

    /// Default 1pt card hairline.
    static let cardStroke = Color("CardStroke", bundle: nil)
    /// Subtle separator (slightly more visible than `cardStroke`).
    static let subtleBorder = Color("SubtleBorder", bundle: nil)

    // MARK: - Pills / Status Chips

    static let pillBackground = Color("PillBackground", bundle: nil)
    static let pillForeground = Color("PillForeground", bundle: nil)

    // MARK: - Hero Surfaces (deep navy "Ready to build?" cards, paywall hero)

    static let heroBackground = Color("HeroBackground", bundle: nil)
    static let heroForeground = Color("HeroForeground", bundle: nil)

    // MARK: - Brand Logo

    /// Pale tinted square that backs the auth-screen brand mark.
    static let brandLogoTint = Color("BrandLogoTint", bundle: nil)

    // MARK: - Inputs

    static let inputBackground = Color("InputBackground", bundle: nil)
    static let formFieldBackground = Color("InputBackground", bundle: nil)
    static let progressTrack = Color("ProgressTrack", bundle: nil)
    static let cardOverlay = Color("CardOverlay", bundle: nil)

    // MARK: - Semantic Status

    static let success = Color(hex: 0x22C55E)
    static let warning = Color(hex: 0xF59E0B)
    static let error = Color(hex: 0xEF4444)

    // MARK: - Accent Palette (category icons, status badges)

    static let accentBlue = Color(hex: 0x3B82F6)
    static let accentPurple = Color(hex: 0x8B5CF6)
    static let accentTeal = Color(hex: 0x14B8A6)
    static let accentGreen = Color(hex: 0x22C55E)
    static let accentRed = Color(hex: 0xEF4444)

    // MARK: - Overlay Surfaces (paywall + dark hero backdrops)

    /// Deep charcoal used as the primary paywall backdrop.
    static let overlayBackground = Color(hex: 0x0B0B0C)
    /// Warm mid-tone gradient stop layered over `overlayBackground`.
    static let overlayAccent = Color(hex: 0x1A0E05)

    // MARK: - On-Dark Text Opacity Scale

    /// Hierarchy for text rendered on top of `overlayBackground` / `heroBackground`.
    static let onDarkPrimary = Color.white.opacity(0.96)
    static let onDarkSecondary = Color.white.opacity(0.72)
    static let onDarkTertiary = Color.white.opacity(0.55)
    static let onDarkQuaternary = Color.white.opacity(0.40)
    static let onDarkDisabled = Color.white.opacity(0.30)

    // MARK: - On-Dark Chrome

    static let onDarkSeparator = Color.white.opacity(0.15)
    static let onDarkFillSubtle = Color.white.opacity(0.08)

    // MARK: - Backwards-Compat Aliases

    static let primaryText = textPrimary
    static let secondaryText = textSecondary
    static let tertiaryText = textTertiary
    static let lightPrimaryText = textPrimary
    static let lightSecondaryText = textSecondary
    static let lightBackground = background
    static let lightSurface = surface
    static let darkBackground = Color(UIColor.systemBackground)
    static let darkSurface = Color(UIColor.secondarySystemBackground)
    static let darkElevated = Color(UIColor.tertiarySystemBackground)
    static let border = subtleBorder
    static let lightBorder = subtleBorder
}
