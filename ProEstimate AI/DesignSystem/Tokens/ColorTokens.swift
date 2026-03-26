import SwiftUI

enum ColorTokens {
    // MARK: - Primary
    static let primaryOrange = Color(hex: 0xF97316)

    // MARK: - Backgrounds
    static let lightBackground = Color(hex: 0xFFFFFF)
    static let lightSurface = Color(hex: 0xF8F9FB)
    static let darkBackground = Color(hex: 0x0B0B0C)
    static let darkSurface = Color(hex: 0x111214)

    // MARK: - Borders
    static let lightBorder = Color(hex: 0xE5E7EB)
    static let darkBorder = Color(hex: 0x1F2937)

    // MARK: - Text
    static let lightPrimaryText = Color(hex: 0x111827)
    static let lightSecondaryText = Color(hex: 0x6B7280)
    static let darkPrimaryText = Color(hex: 0xF9FAFB)
    static let darkSecondaryText = Color(hex: 0x9CA3AF)

    // MARK: - Semantic
    static let success = Color(hex: 0x22C55E)
    static let warning = Color(hex: 0xF59E0B)
    static let error = Color(hex: 0xEF4444)

    // MARK: - Adaptive helpers
    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkBackground : lightBackground
    }

    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkSurface : lightSurface
    }

    static func border(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkBorder : lightBorder
    }

    static func primaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkPrimaryText : lightPrimaryText
    }

    static func secondaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkSecondaryText : lightSecondaryText
    }
}
