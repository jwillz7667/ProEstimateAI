import SwiftUI

/// Multi-step project creation flow presented as a full-screen cover.
/// Shows a progress indicator, step content, and Back/Next navigation
/// buttons. Dismisses on successful creation or explicit cancel.
struct ProjectCreationFlowView: View {
    /// Fires when the project is successfully created. The second parameter
    /// mirrors the "auto-generate preview" toggle from the review step so
    /// the caller can kick off generation right after navigating.
    var onProjectCreated: ((_ projectId: String, _ autoGenerate: Bool) -> Void)?
    @State private var viewModel = ProjectCreationViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress indicator
                progressBar
                    .padding(.horizontal, SpacingTokens.md)
                    .padding(.top, SpacingTokens.sm)
                    .padding(.bottom, SpacingTokens.md)

                // Step content
                TabView(selection: $viewModel.currentStep) {
                    ProjectTypeSelectionStep(viewModel: viewModel)
                        .tag(0)

                    ClientSelectionStep(viewModel: viewModel)
                        .tag(1)

                    ImageUploadStep(viewModel: viewModel)
                        .tag(2)

                    ProjectPromptStep(viewModel: viewModel)
                        .tag(3)

                    ProjectDetailsStep(viewModel: viewModel)
                        .tag(4)

                    ProjectReviewStep(viewModel: viewModel)
                        .tag(5)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)

                // Navigation buttons
                navigationButtons
                    .padding(.horizontal, SpacingTokens.md)
                    .padding(.vertical, SpacingTokens.md)
            }
            .navigationTitle(viewModel.currentStepEnum.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onChange(of: viewModel.createdProject) { _, newValue in
                if let project = newValue {
                    onProjectCreated?(project.id, viewModel.autoGenerateEnabled)
                    dismiss()
                }
            }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack(spacing: SpacingTokens.xxs) {
            ForEach(0..<viewModel.totalSteps, id: \.self) { step in
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

            if viewModel.currentStep < viewModel.totalSteps - 1 {
                PrimaryCTAButton(
                    title: "Next",
                    icon: "chevron.right",
                    isDisabled: !viewModel.canProceed
                ) {
                    viewModel.nextStep()
                }
            } else {
                PrimaryCTAButton(
                    title: "Create Project",
                    icon: "plus.circle.fill",
                    isLoading: viewModel.isSubmitting,
                    isDisabled: !viewModel.canProceed
                ) {
                    Task { await viewModel.createProject() }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ProjectCreationFlowView()
}
