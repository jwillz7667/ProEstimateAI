import SwiftUI

/// Shows remaining free-tier credits as color-coded progress bars.
/// Displays "X of 3 AI Generations remaining" and "X of 3 Quote Exports remaining".
/// Bar color transitions from green to orange to red as credits decrease.
///
/// This view reads directly from `UsageMeterStore` in the environment.
struct FreeUsageMeterView: View {
    @State private var usageMeterStore = UsageMeterStore.shared

    var body: some View {
        VStack(spacing: SpacingTokens.md) {
            // Section header.
            HStack {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .foregroundStyle(ColorTokens.primaryOrange)

                Text("Your Free Credits")
                    .font(TypographyTokens.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Spacer()
            }

            // AI Generations meter.
            creditMeter(
                label: "AI Generations",
                icon: "sparkles",
                remaining: usageMeterStore.generationsRemaining,
                total: usageMeterStore.generationsTotal
            )

            // Quote Exports meter.
            creditMeter(
                label: "Quote Exports",
                icon: "doc.text",
                remaining: usageMeterStore.quotesRemaining,
                total: usageMeterStore.quotesTotal
            )
        }
        .padding(SpacingTokens.md)
        .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: RadiusTokens.card))
        .overlay(
            RoundedRectangle(cornerRadius: RadiusTokens.card)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Credit Meter

    private func creditMeter(
        label: String,
        icon: String,
        remaining: Int,
        total: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))

                Text(label)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                Text("\(remaining) of \(total) remaining")
                    .font(TypographyTokens.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(meterColor(remaining: remaining, total: total))
            }

            // Progress bar.
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track.
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.08))
                        .frame(height: 6)

                    // Fill.
                    RoundedRectangle(cornerRadius: 4)
                        .fill(meterColor(remaining: remaining, total: total))
                        .frame(
                            width: max(0, geometry.size.width * progressFraction(remaining: remaining, total: total)),
                            height: 6
                        )
                        .animation(.easeInOut(duration: 0.3), value: remaining)
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - Helpers

    /// Progress fraction (0.0 to 1.0).
    private func progressFraction(remaining: Int, total: Int) -> CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(remaining) / CGFloat(total)
    }

    /// Color based on remaining credits: green (>66%), orange (33-66%), red (<33%).
    private func meterColor(remaining: Int, total: Int) -> Color {
        guard total > 0 else { return ColorTokens.error }
        let fraction = Double(remaining) / Double(total)
        if fraction > 0.66 {
            return ColorTokens.success
        } else if fraction > 0.33 {
            return ColorTokens.warning
        } else {
            return ColorTokens.error
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        FreeUsageMeterView()
            .padding()
    }
}
