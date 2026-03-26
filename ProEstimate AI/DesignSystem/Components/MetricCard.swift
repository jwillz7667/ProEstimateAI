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
            case .up: .white.opacity(0.9)
            case .down: .white.opacity(0.9)
            case .neutral: .white.opacity(0.7)
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
                .foregroundStyle(.white.opacity(0.85))

            Text(value)
                .font(TypographyTokens.metricValue)
                .foregroundStyle(.white)

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
            LinearGradient(
                colors: [ColorTokens.primaryOrange, ColorTokens.primaryOrange.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: RadiusTokens.card)
        )
        .shadow(color: ColorTokens.primaryOrange.opacity(0.25), radius: 4, x: 0, y: 2)
    }
}
