import SwiftUI

/// Multi-step project creation flow presented as a full-screen cover.
///
/// Two input pages: project setup → photos/notes. Paid lawn-care projects
/// add measurement, then the save/generation pipeline runs inline.
/// The trailing "generating" page runs the create+upload+AI pipeline
/// inline so the user sees one continuous loading screen and lands on a
/// fully-rendered project detail screen rather than a half-loaded shell.
struct ProjectCreationFlowView: View {
    /// Fires when the project + AI generation pipeline completes (or
    /// the user opts to open the project anyway after a soft failure).
    /// The second parameter is kept for backward compatibility with the
    /// old auto-generate handoff; in this flow it's always `false`
    /// because the save/optional-AI pipeline is already handled by the wizard.
    var onProjectCreated: ((_ projectId: String, _ autoGenerate: Bool) -> Void)?

    @State private var viewModel = ProjectCreationViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(EntitlementStore.self) private var entitlementStore
    @Environment(FeatureGateCoordinator.self) private var featureGate
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var activePaywall: PaywallDecision?
    @State private var limitNotice: PaywallDecision?
    @State private var hasConfiguredDefaults = false

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
        .tint(ColorTokens.primaryOrange)
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
            guard !hasConfiguredDefaults else { return }
            hasConfiguredDefaults = true
            viewModel.shouldGenerateAI = entitlementStore.hasProAccess
            viewModel.canUsePaidMaps = entitlementStore.hasProAccess
            // Seed the wizard's per-project AI-preview toggle from the
            // company-wide default. The VM reads this lazily for remodel
            // trades; service trades ignore it and stay off. Seed this draft
            // once so returning from a paywall never overwrites its choices.
            if let company = appState.currentCompany {
                viewModel.companyDefaultGeneratesImage = company.defaultAiPreviewEnabled
            }
        }
        .onChange(of: entitlementStore.hasProAccess) { _, hasAccess in
            viewModel.canUsePaidMaps = hasAccess
            if !hasAccess, viewModel.currentStepEnum == .lawnMap {
                viewModel.currentStep = ProjectCreationStep.photos.rawValue
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
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            Text("Step \(viewModel.currentInputStepIndex + 1) of \(viewModel.navigableStepCount)")
                .font(TypographyTokens.caption)
                .foregroundStyle(ColorTokens.secondaryText)
            HStack(spacing: SpacingTokens.xxs) {
                ForEach(0 ..< viewModel.navigableStepCount, id: \.self) { step in
                    Capsule()
                        .fill(step <= viewModel.currentInputStepIndex ? ColorTokens.primaryOrange : ColorTokens.progressTrack)
                        .frame(height: 4)
                }
            }
            .accessibilityHidden(true)
        }
    }

    // MARK: - Navigation Buttons

    @ViewBuilder
    private var navigationButtons: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: SpacingTokens.sm) {
                forwardButton
                backButton
            }
        } else {
            HStack(spacing: SpacingTokens.sm) {
                backButton
                forwardButton
            }
        }
    }

    @ViewBuilder
    private var backButton: some View {
        if viewModel.currentInputStepIndex > 0 {
            SecondaryButton(title: "Back", icon: "chevron.left") {
                viewModel.previousStep()
            }
        }
    }

    @ViewBuilder
    private var forwardButton: some View {
        if viewModel.isLastInputStep {
            PrimaryCTAButton(
                title: viewModel.shouldGenerateAI ? "Create with AI" : "Save Project",
                icon: viewModel.shouldGenerateAI ? "sparkles" : "checkmark",
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
                title: "Continue",
                icon: "chevron.right",
                isDisabled: !viewModel.canProceed
            ) {
                viewModel.nextStep()
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
