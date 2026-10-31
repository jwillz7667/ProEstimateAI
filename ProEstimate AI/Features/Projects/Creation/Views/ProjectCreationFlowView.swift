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
    @Environment(AppState.self) private var appState
    @Environment(EntitlementStore.self) private var entitlementStore
    @Environment(FeatureGateCoordinator.self) private var featureGate
    @State private var activePaywall: PaywallDecision?
    @State private var limitNotice: PaywallDecision?

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

                if viewModel.currentStepEnum == .details || viewModel.currentStepEnum == .photos {
                    VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                        Toggle("Use AI for this project", isOn: $viewModel.shouldGenerateAI)
                        Text("AI requires an active Pro subscription or trial. Leave this off to save your project and photos and build estimates manually for free.")
                            .font(TypographyTokens.caption)
                            .foregroundStyle(ColorTokens.secondaryText)
                    }
                    .padding(.horizontal, SpacingTokens.md)
                }
                if viewModel.currentStepEnum != .generating {
                    navigationButtons
                        .padding(.horizontal, SpacingTokens.md)
                        .padding(.vertical, SpacingTokens.md)
                }
            }
            .navigationTitle(stepTitle)
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
        .sheet(item: $activePaywall) { decision in
            PaywallHostView(decision: decision) {
                activePaywall = nil
            }
        }
        .alert(limitNotice?.headline ?? "Plan Limit Reached", isPresented: Binding(
            get: { limitNotice != nil }, set: { if !$0 { limitNotice = nil } }
        )) {
            Button("OK", role: .cancel) { limitNotice = nil }
        } message: {
            Text(limitNotice?.subheadline ?? "Try again when your allowance resets.")
        }
        .onChange(of: viewModel.pipelinePaywall) { _, decision in
            guard let decision else { return }
            present(decision)
            viewModel.pipelinePaywall = nil
        }
        .onAppear {
            viewModel.shouldGenerateAI = entitlementStore.hasProAccess
            viewModel.canUsePaidMaps = entitlementStore.hasProAccess
            // Seed the wizard's per-project AI-preview toggle from the
            // company-wide default. The VM reads this lazily for remodel
            // trades; service trades ignore it and stay off. Setting it here
            // (rather than in the VM init) keeps the VM free of environment
            // coupling and lets the value follow a mid-session settings change.
            if let company = appState.currentCompany {
                viewModel.companyDefaultGeneratesImage = company.defaultAiPreviewEnabled
            }
        }
    }

    // MARK: - Step Content

    private var stepTitle: String {
        if !viewModel.shouldGenerateAI {
            if viewModel.currentStepEnum == .generating { return "Saving Project" }
            if viewModel.currentStepEnum == .photos { return "Photos & Notes" }
        }
        return viewModel.currentStepEnum.title
    }

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
                    title: viewModel.shouldGenerateAI ? "Create with AI" : "Save Project",
                    icon: "plus.circle.fill",
                    isLoading: viewModel.isPipelineRunning,
                    isDisabled: !viewModel.canProceed || viewModel.isPipelineRunning
                ) {
                    if viewModel.shouldGenerateAI,
                       case let .blocked(decision) = featureGate.guardGeneratePreview() {
                        present(decision)
                    } else {
                        viewModel.enterGeneratingStep()
                    }
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
    private func present(_ decision: PaywallDecision) {
        if decision.placement.isUsageLimit { limitNotice = decision }
        else { activePaywall = decision }
    }

}

// MARK: - Preview

#Preview {
    ProjectCreationFlowView()
}
