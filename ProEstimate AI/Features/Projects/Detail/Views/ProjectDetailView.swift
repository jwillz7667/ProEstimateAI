import SwiftUI

/// Full project detail screen. Shows overview, images, AI preview,
/// materials, estimates, and activity in a scrollable layout.
/// Loaded by project ID from the navigation stack.
struct ProjectDetailView: View {
    let projectId: String

    @State private var viewModel = ProjectDetailViewModel()
    @State private var hasCompletedFirstGeneration = false
    @State private var showEditSheet = false
    @Environment(AppRouter.self) private var router
    @Environment(FeatureGateCoordinator.self) private var featureGateCoordinator
    @Environment(PaywallPresenter.self) private var paywallPresenter

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.project == nil {
                LoadingStateView(message: "Loading project...")
            } else if let error = viewModel.errorMessage, viewModel.project == nil {
                RetryStateView(message: error) {
                    Task { await viewModel.loadProject(id: projectId) }
                }
            } else if let project = viewModel.project {
                projectContent(project)
            }
        }
        .navigationTitle(viewModel.project?.title ?? "Project")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                }

                ShareLink(
                    item: "Check out this project: \(viewModel.project?.title ?? "")",
                    subject: Text(viewModel.project?.title ?? "Project"),
                    message: Text("ProEstimate AI project details")
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .refreshable {
            await viewModel.loadProject(id: projectId)
        }
        .task {
            if viewModel.project == nil {
                await viewModel.loadProject(id: projectId)
            }
        }
        .fullScreenCover(isPresented: $showEditSheet) {
            Task { await viewModel.loadProject(id: projectId) }
        } content: {
            ProjectCreationFlowView()
        }
    }

    // MARK: - Content

    private func projectContent(_ project: Project) -> some View {
        ScrollView {
            LazyVStack(spacing: SpacingTokens.lg) {
                // Overview
                ProjectOverviewSection(
                    project: project,
                    clientName: viewModel.clientName,
                    onClientTapped: {
                        if let clientId = project.clientId {
                            router.navigate(to: .clientDetail(id: clientId))
                        }
                    }
                )
                .padding(.horizontal, SpacingTokens.md)

                // Images
                ProjectImagesSection(assets: viewModel.assets)

                // AI Preview
                AIPreviewSection(
                    generations: viewModel.generations,
                    isGenerating: viewModel.isGenerating,
                    currentGenerationStage: viewModel.currentGenerationStage,
                    onGenerate: {
                        handleGenerate()
                    },
                    assets: viewModel.assets
                )

                // Materials
                MaterialSuggestionsSection(
                    materials: viewModel.materials,
                    selectionState: viewModel.materialSelectionState,
                    selectedCount: viewModel.selectedMaterialCount,
                    selectedTotal: viewModel.selectedMaterialsTotal,
                    onToggle: { id in viewModel.toggleMaterial(id: id) }
                )

                // Estimates
                ProjectEstimatesSection(estimates: viewModel.estimates)

                // Activity
                ProjectActivitySection(entries: viewModel.activityLog)

                // Bottom spacer
                Spacer(minLength: SpacingTokens.huge)
            }
            .padding(.vertical, SpacingTokens.sm)
        }
    }

    // MARK: - Feature-Gated Actions

    private func handleGenerate() {
        let result = featureGateCoordinator.guardGeneratePreview()
        switch result {
        case .allowed:
            Task {
                await viewModel.startGeneration()
                // After first successful generation, show soft upsell
                if !hasCompletedFirstGeneration {
                    hasCompletedFirstGeneration = true
                    paywallPresenter.present(.sampleSoftGate)
                }
            }
        case .blocked(let decision):
            paywallPresenter.present(decision)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ProjectDetailView(projectId: "p-001")
    }
    .environment(AppRouter())
    .environment(FeatureGateCoordinator.preview())
    .environment(PaywallPresenter())
}
