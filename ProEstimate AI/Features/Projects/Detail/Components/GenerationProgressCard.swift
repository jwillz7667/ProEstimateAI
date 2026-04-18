import Combine
import SwiftUI

/// Live progress card shown while an AI preview generation is in flight.
/// A large animated hero icon, an elapsed-time counter, a linear progress
/// track, and a horizontal row of stage chips. Paced to match the real
/// backend latency (roughly 60–130 seconds); never jumps to "Complete" on
/// its own — the view model advances the final stage only when the
/// generation actually finishes.
struct GenerationProgressCard: View {
    /// Current stage index from `GenerationStage`. Drives both the stage
    /// chips and the linear progress track.
    let currentStage: Int

    @State private var elapsedSeconds: Int = 0
    @State private var iconPulse: Bool = false

    /// Update the elapsed counter every second for as long as the card is
    /// on screen. We own this locally because "how long have we been
    /// waiting" is a pure UI concern tied to card presentation.
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Expected total duration the user should brace for. Used for the
    /// "~1:30" label next to the elapsed counter.
    private let typicalDurationSeconds: Int = 90

    var body: some View {
        GlassCard {
            VStack(spacing: SpacingTokens.md) {
                headerRow

                progressBar

                stageChips
            }
        }
        .onAppear {
            iconPulse = true
        }
        .onReceive(timer) { _ in
            elapsedSeconds += 1
        }
    }

    // MARK: - Header (hero icon + elapsed + hint)

    private var headerRow: some View {
        HStack(alignment: .center, spacing: SpacingTokens.md) {
            // Animated hero icon — soft radial glow under a sparkle mark.
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                ColorTokens.primaryOrange.opacity(0.35),
                                ColorTokens.primaryOrange.opacity(0.0),
                            ],
                            center: .center,
                            startRadius: 2,
                            endRadius: 34
                        )
                    )
                    .frame(width: 68, height: 68)
                    .scaleEffect(iconPulse ? 1.08 : 0.92)
                    .animation(
                        .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                        value: iconPulse
                    )

                Image(systemName: activeStage.icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(ColorTokens.primaryOrange)
                    .symbolRenderingMode(.hierarchical)
                    .symbolEffect(.pulse, options: .repeating, value: iconPulse)
            }

            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                Text(activeStage.headerTitle)
                    .font(TypographyTokens.headline)

                Text(activeStage.subtitle)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: SpacingTokens.xxs) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text("\(formattedElapsed) of ~\(formattedTypical)")
                        .font(TypographyTokens.caption)
                        .monospacedDigit()
                }
                .foregroundStyle(.tertiary)
                .padding(.top, SpacingTokens.xxs)
            }

            Spacer()
        }
    }

    // MARK: - Linear progress bar with shimmer

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(ColorTokens.progressTrack)
                    .frame(height: 6)

                // Fill — width snaps to clamped stage-based progress (~25% per
                // timer-driven stage). The final quarter doesn't tick down
                // automatically; it fills only when stopProgressSimulation()
                // jumps currentStage to `.complete`.
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                ColorTokens.primaryOrange,
                                ColorTokens.primaryOrange.opacity(0.7),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: proxy.size.width * clampedProgressFraction,
                        height: 6
                    )
                    .overlay(
                        // Subtle shimmer overlay that sweeps across the fill.
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.0),
                                        .white.opacity(0.35),
                                        .white.opacity(0.0),
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 60)
                            .offset(x: iconPulse
                                    ? proxy.size.width * clampedProgressFraction
                                    : -60)
                            .animation(
                                .linear(duration: 1.4).repeatForever(autoreverses: false),
                                value: iconPulse
                            )
                            .mask(
                                Capsule().frame(
                                    width: proxy.size.width * clampedProgressFraction,
                                    height: 6
                                )
                            )
                    )
                    .animation(.easeInOut(duration: 0.6), value: clampedProgressFraction)
            }
        }
        .frame(height: 6)
    }

    // MARK: - Stage chips

    private var stageChips: some View {
        HStack(spacing: SpacingTokens.xxs) {
            ForEach(GenerationStage.allCases, id: \.rawValue) { stage in
                stageChip(stage: stage, state: stateFor(stage))
            }
        }
    }

    private func stageChip(stage: GenerationStage, state: StageState) -> some View {
        HStack(spacing: SpacingTokens.xxs) {
            Group {
                switch state {
                case .complete:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(ColorTokens.success)
                case .active:
                    Image(systemName: "circle.fill")
                        .foregroundStyle(ColorTokens.primaryOrange)
                        .symbolEffect(.pulse, options: .repeating, value: iconPulse)
                case .pending:
                    Image(systemName: "circle")
                        .foregroundStyle(ColorTokens.progressTrack)
                }
            }
            .font(.caption2)

            Text(stage.chipTitle)
                .font(TypographyTokens.caption2.weight(state == .active ? .semibold : .regular))
                .foregroundStyle(textColor(for: state))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, SpacingTokens.xs)
        .padding(.vertical, SpacingTokens.xxs)
        .background(
            Capsule()
                .fill(backgroundColor(for: state))
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    state == .active ? ColorTokens.primaryOrange.opacity(0.5) : .clear,
                    lineWidth: 1
                )
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private var activeStage: GenerationStage {
        GenerationStage(rawValue: min(max(currentStage, 0), GenerationStage.allCases.count - 1))
            ?? .uploading
    }

    private func stateFor(_ stage: GenerationStage) -> StageState {
        if stage.rawValue < currentStage { return .complete }
        if stage.rawValue == currentStage { return .active }
        return .pending
    }

    private func textColor(for state: StageState) -> Color {
        switch state {
        case .pending: .secondary
        case .active: .primary
        case .complete: .primary
        }
    }

    private func backgroundColor(for state: StageState) -> Color {
        switch state {
        case .pending: Color.clear
        case .active: ColorTokens.primaryOrange.opacity(0.14)
        case .complete: ColorTokens.success.opacity(0.10)
        }
    }

    /// Visual progress fraction. Each timer-driven stage fills ~25% of the
    /// bar; the `.complete` stage fills the remaining portion.
    private var clampedProgressFraction: CGFloat {
        let totalVisibleStages = CGFloat(GenerationStage.allCases.count)
        let clamped = max(0, min(CGFloat(currentStage), totalVisibleStages - 1))
        // Give active stage a little extra fill so users see movement even
        // while the timer is waiting at the "enhancing" step.
        let base = (clamped + 0.5) / totalVisibleStages
        return currentStage >= GenerationStage.allCases.count - 1 ? 1.0 : min(0.92, base)
    }

    private var formattedElapsed: String { formatTime(elapsedSeconds) }

    private var formattedTypical: String { formatTime(typicalDurationSeconds) }

    private func formatTime(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Stage copy

private extension GenerationStage {
    /// Title shown in the card header while this stage is active.
    var headerTitle: String {
        switch self {
        case .uploading: "Preparing your photo"
        case .analyzing: "Understanding the space"
        case .generating: "Rendering the remodel"
        case .enhancing: "Polishing the details"
        case .complete: "All set"
        }
    }

    /// Supporting copy under the header.
    var subtitle: String {
        switch self {
        case .uploading: "Sending your photo to the AI service securely."
        case .analyzing: "Detecting surfaces, fixtures, and lighting."
        case .generating: "Composing the before-and-after render."
        case .enhancing: "Upscaling and color-grading the final image."
        case .complete: "Your preview is ready to review."
        }
    }

    /// Short, one-word label used in the stage chips row.
    var chipTitle: String {
        switch self {
        case .uploading: "Upload"
        case .analyzing: "Analyze"
        case .generating: "Render"
        case .enhancing: "Enhance"
        case .complete: "Done"
        }
    }
}

// MARK: - Preview

#Preview("Stages") {
    VStack(spacing: SpacingTokens.md) {
        GenerationProgressCard(currentStage: 0)
        GenerationProgressCard(currentStage: 2)
        GenerationProgressCard(currentStage: 3)
        GenerationProgressCard(currentStage: 4)
    }
    .padding()
    .background(Color.black)
}
