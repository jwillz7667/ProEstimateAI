import SwiftUI

struct MetricCard: View {
    let label: String
    let value: String
    var trend: Trend? = nil

    enum Trend {
        case up(String)
        case down(String)
        case neutral(String)

        var color: Color {
            switch self {
            case .up: ColorTokens.success
            case .down: ColorTokens.error
            case .neutral: ColorTokens.secondaryText
            }
        }

        var icon: String {
            switch self {
            case .up: "arrow.up.right"
            case .down: "arrow.down.right"
            case .neutral: "minus"
            }
        }

        var text: String {
            switch self {
            case .up(let t), .down(let t), .neutral(let t): t
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            Text(label)
                .font(TypographyTokens.metricLabel)
                .foregroundStyle(ColorTokens.secondaryText)

            Text(value)
                .font(TypographyTokens.metricValue)
                .foregroundStyle(ColorTokens.primaryText)

            if let trend {
                HStack(spacing: SpacingTokens.xxs) {
                    Image(systemName: trend.icon)
                        .font(.caption2)
                    Text(trend.text)
                        .font(TypographyTokens.caption2)
                }
                .foregroundStyle(trend.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SpacingTokens.md)
        .background(
            ColorTokens.elevatedSurface,
            in: RoundedRectangle(cornerRadius: RadiusTokens.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: RadiusTokens.card)
                .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
    }
}
