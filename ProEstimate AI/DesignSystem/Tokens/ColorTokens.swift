import SwiftUI

enum ColorTokens {
    // MARK: - Primary
    static let primaryOrange = Color(hex: 0xF97316)

    // MARK: - Backgrounds (light mode, iOS system colors)
    static let background = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemGroupedBackground)
    static let elevatedSurface = Color(.tertiarySystemGroupedBackground)

    // MARK: - Legacy aliases (used across views)
    static let lightBackground = Color(.systemBackground)
    static let lightSurface = Color(.secondarySystemGroupedBackground)

    // MARK: - Borders
    static let border = Color(.separator)
    static let lightBorder = Color(.separator)

    // MARK: - Text
    static let primaryText = Color(.label)
    static let secondaryText = Color(.secondaryLabel)
    static let lightPrimaryText = Color(.label)
    static let lightSecondaryText = Color(.secondaryLabel)

    // MARK: - Semantic
    static let success = Color(hex: 0x22C55E)
    static let warning = Color(hex: 0xF59E0B)
    static let error = Color(hex: 0xEF4444)
}
