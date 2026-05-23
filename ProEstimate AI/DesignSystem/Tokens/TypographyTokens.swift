import SwiftUI

enum TypographyTokens {
    // MARK: - Display

    /// Used for hero greetings ("Hello, Alex") and screen-defining titles.
    static let largeTitle = Font.system(.largeTitle, design: .default, weight: .bold)
    /// Section-defining titles ("Recent Visions", "Active Quotes").
    static let title = Font.system(.title, design: .default, weight: .bold)
    static let title2 = Font.system(.title2, design: .default, weight: .bold)
    static let title3 = Font.system(.title3, design: .default, weight: .semibold)

    // MARK: - Body

    /// Card titles ("The Hawthorne Estate", "Modern Coastal Kitchen").
    static let cardTitle = Font.system(.headline, design: .default, weight: .semibold)
    static let headline = Font.headline
    static let body = Font.body
    static let bodyEmphasized = Font.body.weight(.medium)
    static let callout = Font.callout
    static let subheadline = Font.subheadline
    static let footnote = Font.footnote
    static let caption = Font.caption
    static let caption2 = Font.caption2
    /// Uppercase labels above inputs ("EMAIL ADDRESS").
    static let inputLabel = Font.system(.caption, design: .default, weight: .semibold)
    /// Pill / badge text ("Accepted", "Draft").
    static let pillLabel = Font.system(.caption, design: .default, weight: .semibold)

    // MARK: - Buttons

    /// All-caps wide-tracking primary button label.
    static let buttonPrimary = Font.system(.subheadline, design: .default, weight: .bold)
    static let buttonSecondary = Font.system(.subheadline, design: .default, weight: .semibold)

    // MARK: - Numbers / Money

    static let moneyLarge = Font.system(.title, design: .rounded, weight: .bold).monospacedDigit()
    static let moneyMedium = Font.system(.title3, design: .rounded, weight: .semibold).monospacedDigit()
    static let moneySmall = Font.system(.body, design: .rounded, weight: .medium).monospacedDigit()
    static let moneyCaption = Font.system(.caption, design: .rounded, weight: .medium).monospacedDigit()

    // MARK: - Metrics

    static let metricValue = Font.system(.title, design: .rounded, weight: .bold)
    static let metricLabel = Font.caption.weight(.medium)
}
