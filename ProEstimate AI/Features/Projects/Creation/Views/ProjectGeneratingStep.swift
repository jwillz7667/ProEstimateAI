import SwiftUI

/// Step 3 of the simplified creation flow. Non-interactive loading view
/// that runs the full create → upload → generate → poll pipeline. Shows
/// a progress checklist so the wait feels purposeful, with inline retry
/// on failure and an "Open Project Anyway" escape hatch on timeout.
struct ProjectGeneratingStep: View {
    @Bindable var viewModel: ProjectCreationViewModel

    /// Fires when the generation pipeline completes (or the user opts to
    /// open the project anyway after a soft failure). Carries the
    /// project id so the wizard host can navigate to the detail screen.
    var onCompleted: ((_ projectId: String) -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: SpacingTokens.xl) {
                hero

                progressChecklist

                if case let .failed(message) = viewModel.pipelineStage {
                    failureSection(message: message)
                } else {
                    helperFootnote
                }
            }
            .padding(.horizontal, SpacingTokens.lg)
            .padding(.vertical, SpacingTokens.xl)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .task {
            // Only run the pipeline once. The view model's stage starts
            // at `.idle`; the wizard transitions us in only after the
            // user taps Create on the details step.
            if viewModel.pipelineStage == .idle {
                await viewModel.runCreationPipeline()
            }
        }
        .onChange(of: viewModel.pipelineStage) { _, newValue in
            if newValue == .completed, let project = viewModel.createdProject {
                onCompleted?(project.id)
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: SpacingTokens.md) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                ColorTokens.primaryOrange,
                                ColorTokens.primaryOrange.opacity(0.75),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                    .shadow(color: ColorTokens.primaryOrange.opacity(0.4), radius: 18, x: 0, y: 8)

                if isFailed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(.white)
                } else if isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.pulse, options: .repeating, isActive: !isFailed && !isComplete)
                }
            }
            .accessibilityHidden(true)

            VStack(spacing: SpacingTokens.xxs) {
                Text(heroTitle)
                    .font(TypographyTokens.title2)
                    .foregroundStyle(ColorTokens.primaryText)
                    .multilineTextAlignment(.center)

                Text(heroSubtitle)
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(ColorTokens.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var heroTitle: String {
        if isFailed { return "We hit a snag" }
        if isComplete { return "All set!" }
        return "Preparing your project"
    }

    private var heroSubtitle: String {
        if isFailed { return "Your project is created — you can retry the AI preview or open it anyway." }
        if isComplete { return "Opening your project now…" }
        return "This usually takes 60–90 seconds. Stay on this screen and we'll have everything ready for you."
    }

    private var isFailed: Bool {
        if case .failed = viewModel.pipelineStage { return true }
        return false
    }

    private var isComplete: Bool {
        viewModel.pipelineStage == .completed
    }

    // MARK: - Progress Checklist

    private var progressChecklist: some View {
        VStack(spacing: SpacingTokens.sm) {
            ForEach(checklistItems, id: \.id) { item in
                progressRow(item)
            }
        }
        .padding(SpacingTokens.md)
        .glassCard(cornerRadius: RadiusTokens.card)
    }

    private struct ChecklistItem: Identifiable {
        let id: Int
        let title: String
        let subtitle: String
        let stageRank: Int
    }

    private var checklistItems: [ChecklistItem] {
        [
            ChecklistItem(id: 0, title: "Creating project", subtitle: "Saving project details", stageRank: 1),
            ChecklistItem(id: 1, title: "Uploading photos", subtitle: "Securing your before-photos", stageRank: 2),
            ChecklistItem(id: 2, title: "Generating preview", subtitle: "AI render of the finished space", stageRank: 4),
            ChecklistItem(id: 3, title: "Calculating materials", subtitle: "Suggested finishes and quantities", stageRank: 5),
        ]
    }

    private func progressRow(_ item: ChecklistItem) -> some View {
        let state = state(for: item.stageRank)

        return HStack(spacing: SpacingTokens.sm) {
            stateIndicator(state)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(TypographyTokens.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(state == .pending ? ColorTokens.tertiaryText : ColorTokens.primaryText)

                Text(item.subtitle)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.secondaryText)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, SpacingTokens.xxs)
    }

    @ViewBuilder
    private func stateIndicator(_ state: RowState) -> some View {
        switch state {
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(ColorTokens.success)
                .transition(.scale.combined(with: .opacity))
        case .active:
            ProgressView()
                .controlSize(.small)
                .tint(ColorTokens.primaryOrange)
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 22))
                .foregroundStyle(ColorTokens.tertiaryText)
        }
    }

    private enum RowState: Equatable {
        case pending, active, complete
    }

    private func state(for stageRank: Int) -> RowState {
        let current = viewModel.pipelineStage.rank
        if isFailed {
            // Treat steps that completed before the failure as done; the
            // current/next as pending so the failure isn't ambiguous.
            return current >= stageRank ? .complete : .pending
        }
        if current > stageRank { return .complete }
        if current == stageRank { return .active }
        // Special case: when current is 3 (.startingGeneration), the
        // generating row (rank 4) shouldn't already light up — we only
        // mark it active once polling actually begins.
        return .pending
    }

    // MARK: - Failure Section

    private func failureSection(message: String) -> some View {
        VStack(spacing: SpacingTokens.sm) {
            HStack(alignment: .top, spacing: SpacingTokens.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(ColorTokens.warning)
                Text(message)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(SpacingTokens.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .fill(ColorTokens.warning.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: RadiusTokens.small)
                            .stroke(ColorTokens.warning.opacity(0.35), lineWidth: 1)
                    )
            )

            VStack(spacing: SpacingTokens.xs) {
                Button {
                    Task { await viewModel.retryGeneration() }
                } label: {
                    Text("Retry preview")
                        .font(TypographyTokens.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SpacingTokens.md)
                        .background(
                            ColorTokens.primaryOrange,
                            in: RoundedRectangle(cornerRadius: RadiusTokens.button)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    if let project = viewModel.createdProject {
                        onCompleted?(project.id)
                    }
                } label: {
                    Text("Open project anyway")
                        .font(TypographyTokens.callout)
                        .foregroundStyle(ColorTokens.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SpacingTokens.sm)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.createdProject == nil)
            }
        }
    }

    // MARK: - Helper Footnote

    private var helperFootnote: some View {
        Text("You can leave this screen at any time — your project keeps generating in the background.")
            .font(TypographyTokens.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, SpacingTokens.md)
    }
}

// MARK: - Preview

#Preview {
    ProjectGeneratingStep(viewModel: ProjectCreationViewModel())
}
