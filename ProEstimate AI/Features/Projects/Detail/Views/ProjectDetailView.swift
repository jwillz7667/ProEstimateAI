import SwiftUI

/// Full project detail screen. Shows overview, images, AI preview,
/// materials, estimates, and activity in a scrollable layout.
/// Loaded by project ID from the navigation stack.
struct ProjectDetailView: View {
    let projectId: String

    @State private var viewModel = ProjectDetailViewModel()
    @Environment(AppRouter.self) private var router

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
                    // Edit action placeholder
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
                ProjectImagesSection(assets: ProjectImagesSection.mockAssets)

                // AI Preview
                AIPreviewSection(
                    generations: viewModel.generations,
                    isGenerating: viewModel.isGenerating,
                    currentGenerationStage: viewModel.currentGenerationStage,
                    onGenerate: {
                        Task { await viewModel.startGeneration() }
                    }
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
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ProjectDetailView(projectId: "p-001")
    }
    .environment(AppRouter())
}
