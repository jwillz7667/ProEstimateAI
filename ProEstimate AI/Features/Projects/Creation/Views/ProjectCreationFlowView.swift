import SwiftUI

/// Multi-step project creation flow presented as a full-screen cover.
///
/// Four pages: category → photos+prompts → name+advanced → generating.
/// The trailing "generating" page runs the create+upload+AI pipeline
/// inline so the user sees one continuous loading screen and lands on a
/// fully-rendered project detail screen rather than a half-loaded shell.
struct ProjectCreationFlowView: View {
    /// Fires when the project + AI generation pipeline completes (or
    /// the user opts to open the project anyway after a soft failure).
    /// The second parameter is kept for backward compatibility with the
    /// old auto-generate handoff; in this flow it's always `false`
    /// because generation has already started in the wizard.
    var onProjectCreated: ((_ projectId: String, _ autoGenerate: Bool) -> Void)?

    @State private var viewModel = ProjectCreationViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Hide the progress bar entirely on the loading step —
                // it's not navigable and the loading screen already
                // signals progress in a richer way.
                if viewModel.currentStepEnum != .generating {
                    progressBar
                        .padding(.horizontal, SpacingTokens.md)
                        .padding(.top, SpacingTokens.sm)
                        .padding(.bottom, SpacingTokens.md)
                }

                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if viewModel.currentStepEnum != .generating {
                    navigationButtons
                        .padding(.horizontal, SpacingTokens.md)
                        .padding(.vertical, SpacingTokens.md)
                }
            }
            .navigationTitle(viewModel.currentStepEnum.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(viewModel.isPipelineRunning)
                }
            }
            .interactiveDismissDisabled(viewModel.isPipelineRunning)
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStepEnum {
        case .type:
            ProjectTypeSelectionStep(viewModel: viewModel)
        case .photos:
            PhotosAndPromptStep(viewModel: viewModel)
        case .lawnMap:
            LawnAreaCaptureStep(viewModel: viewModel)
        case .details:
            ProjectDetailsStep(viewModel: viewModel)
        case .generating:
            ProjectGeneratingStep(viewModel: viewModel) { projectId in
                // Pipeline complete (or "open anyway" tapped). Hand off
                // to the caller and dismiss the wizard.
                onProjectCreated?(projectId, false)
                dismiss()
            }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack(spacing: SpacingTokens.xxs) {
            ForEach(0 ..< viewModel.navigableStepCount, id: \.self) { step in
                Capsule()
                    .fill(step <= viewModel.currentStep ? ColorTokens.primaryOrange : ColorTokens.progressTrack)
                    .frame(height: 4)
                    .animation(.easeInOut(duration: 0.25), value: viewModel.currentStep)
            }
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: SpacingTokens.sm) {
            if viewModel.currentStep > 0 {
                SecondaryButton(title: "Back", icon: "chevron.left") {
                    viewModel.previousStep()
                }
            }

            // Last input step is `.details`; tapping the primary button
            // there should kick off the pipeline by transitioning to
            // the generating step (which auto-runs the pipeline in its
            // .task). All earlier steps just step forward.
            if viewModel.currentStepEnum == .details {
                PrimaryCTAButton(
                    title: "Create Project",
                    icon: "plus.circle.fill",
                    isLoading: viewModel.isPipelineRunning,
                    isDisabled: !viewModel.canProceed || viewModel.isPipelineRunning
                ) {
                    viewModel.enterGeneratingStep()
                }
            } else {
                PrimaryCTAButton(
                    title: "Next",
                    icon: "chevron.right",
                    isDisabled: !viewModel.canProceed
                ) {
                    viewModel.nextStep()
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ProjectCreationFlowView()
}
