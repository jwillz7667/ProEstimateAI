import SwiftUI

/// Shows the five stages of an AI generation in progress.
/// Each stage has an icon, label, and animated state indicator
/// (pending, active, or complete). Stages advance via a timer
/// driven from the view model.
struct GenerationProgressCard: View {
    let currentStage: Int

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: SpacingTokens.md) {
                HStack(spacing: SpacingTokens.xs) {
                    Image(systemName: "wand.and.stars")
                        .font(.title3)
                        .foregroundStyle(ColorTokens.primaryOrange)
                    Text("Generating Preview")
                        .font(TypographyTokens.headline)
                }

                ForEach(GenerationStage.allCases, id: \.rawValue) { stage in
                    stageRow(stage: stage, state: stateFor(stage))
                }
            }
        }
    }

    // MARK: - Subviews

    private func stageRow(stage: GenerationStage, state: StageState) -> some View {
        HStack(spacing: SpacingTokens.sm) {
            // State indicator
            ZStack {
                switch state {
                case .pending:
                    Circle()
                        .strokeBorder(Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)

                case .active:
                    ProgressView()
                        .controlSize(.small)
                        .tint(ColorTokens.primaryOrange)
                        .frame(width: 24, height: 24)

                case .complete:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(ColorTokens.success)
                        .frame(width: 24, height: 24)
                }
            }

            Image(systemName: stage.icon)
                .font(.caption)
                .foregroundStyle(iconColor(for: state))
                .frame(width: 20)

            Text(stage.title)
                .font(TypographyTokens.subheadline)
                .foregroundStyle(textColor(for: state))

            Spacer()

            if state == .complete {
                Image(systemName: "checkmark")
                    .font(.caption2)
                    .foregroundStyle(ColorTokens.success)
            }
        }
        .padding(.vertical, SpacingTokens.xxs)
        .animation(.easeInOut(duration: 0.3), value: state == .active)
    }

    // MARK: - Helpers

    private func stateFor(_ stage: GenerationStage) -> StageState {
        if stage.rawValue < currentStage {
            return .complete
        } else if stage.rawValue == currentStage {
            return .active
        } else {
            return .pending
        }
    }

    private func iconColor(for state: StageState) -> Color {
        switch state {
        case .pending: Color.gray.opacity(0.4)
        case .active: ColorTokens.primaryOrange
        case .complete: ColorTokens.success
        }
    }

    private func textColor(for state: StageState) -> Color {
        switch state {
        case .pending: .secondary
        case .active: .primary
        case .complete: .primary
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: SpacingTokens.md) {
        GenerationProgressCard(currentStage: 0)
        GenerationProgressCard(currentStage: 2)
        GenerationProgressCard(currentStage: 4)
    }
    .padding()
}
