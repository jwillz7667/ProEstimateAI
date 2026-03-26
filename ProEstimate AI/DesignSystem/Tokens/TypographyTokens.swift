import SwiftUI

enum TypographyTokens {
    // MARK: - Display
    static let largeTitle = Font.largeTitle.weight(.bold)
    static let title = Font.title.weight(.bold)
    static let title2 = Font.title2.weight(.semibold)
    static let title3 = Font.title3.weight(.semibold)

    // MARK: - Body
    static let headline = Font.headline
    static let body = Font.body
    static let callout = Font.callout
    static let subheadline = Font.subheadline
    static let footnote = Font.footnote
    static let caption = Font.caption
    static let caption2 = Font.caption2

    // MARK: - Numbers / Money
    static let moneyLarge = Font.system(.title, design: .rounded, weight: .bold).monospacedDigit()
    static let moneyMedium = Font.system(.title3, design: .rounded, weight: .semibold).monospacedDigit()
    static let moneySmall = Font.system(.body, design: .rounded, weight: .medium).monospacedDigit()
    static let moneyCaption = Font.system(.caption, design: .rounded, weight: .medium).monospacedDigit()

    // MARK: - Metrics
    static let metricValue = Font.system(.title, design: .rounded, weight: .bold)
    static let metricLabel = Font.caption.weight(.medium)
}
