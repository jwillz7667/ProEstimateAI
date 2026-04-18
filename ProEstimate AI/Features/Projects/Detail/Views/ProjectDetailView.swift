import SwiftUI

/// Full project detail screen. Shows overview, images, AI preview,
/// materials, estimates, and activity in a scrollable layout.
/// Loaded by project ID from the navigation stack.
struct ProjectDetailView: View {
    let projectId: String

    @State private var viewModel = ProjectDetailViewModel()
    @State private var hasCompletedFirstGeneration = false
    @State private var showEditSheet = false
    @State private var activeEstimate: ActiveEstimate?
    @State private var activeInvoice: ActiveInvoice?
    @State private var isCreatingEstimate = false
    @State private var isCreatingInvoice = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false

    /// Identifiable wrapper used to drive the estimate editor sheet via
    /// `.sheet(item:)`. This avoids the race where `.sheet(isPresented:)` +
    /// `if let id = optionalId` can render an empty sheet if the bool flips
    /// to `true` before the id state commits.
    private struct ActiveEstimate: Identifiable, Hashable {
        let id: String
    }

    /// Identifiable wrapper used to drive the invoice preview sheet the same
    /// way `ActiveEstimate` drives the estimate-editor sheet.
    private struct ActiveInvoice: Identifiable, Hashable {
        let id: String
    }
    @Environment(AppRouter.self) private var router
    @Environment(FeatureGateCoordinator.self) private var featureGateCoordinator
    @Environment(PaywallPresenter.self) private var paywallPresenter
    @Environment(AppState.self) private var appState

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
            } else {
                // Fallback: if task didn't fire, show loading and trigger load
                LoadingStateView(message: "Loading project...")
                    .onAppear {
                        Task { await viewModel.loadProject(id: projectId) }
                    }
            }
        }
        .navigationTitle(viewModel.project?.title ?? "Project")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ShareLink(
                    item: "Check out this project: \(viewModel.project?.title ?? "")",
                    subject: Text(viewModel.project?.title ?? "Project"),
                    message: Text("ProEstimate AI project details")
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share")
                .accessibilityHint("Share this project")

                Menu {
                    Button {
                        showEditSheet = true
                    } label: {
                        Label("Edit Project", systemImage: "pencil")
                    }

                    Divider()

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Project", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More options")
                .accessibilityHint("Edit or delete this project")
                .disabled(viewModel.project == nil || isDeleting)
            }
        }
        .confirmationDialog(
            "Delete Project",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                Task { await performProjectDeletion() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the project and all linked photos, AI previews, materials, estimates, proposals, and invoices. This cannot be undone.")
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
        .sheet(item: $activeEstimate, onDismiss: {
            Task { await viewModel.loadProject(id: projectId) }
        }) { active in
            NavigationStack {
                EstimateEditorView(estimateId: active.id, initialDIY: viewModel.isDIY)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { activeEstimate = nil }
                        }
                    }
            }
        }
        .sheet(item: $activeInvoice, onDismiss: {
            Task { await viewModel.loadProject(id: projectId) }
        }) { active in
            NavigationStack {
                InvoicePreviewView(invoiceId: active.id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { activeInvoice = nil }
                        }
                    }
            }
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { viewModel.project != nil && viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            if let message = viewModel.errorMessage {
                Text(message)
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
                ProjectImagesSection(assets: viewModel.assets)

                // AI Preview
                AIPreviewSection(
                    generations: viewModel.generations,
                    isGenerating: viewModel.isGenerating,
                    currentGenerationStage: viewModel.currentGenerationStage,
                    onGenerate: { prompt in
                        handleGenerate(prompt: prompt)
                    },
                    defaultPrompt: viewModel.project?.description ?? "",
                    assets: viewModel.assets
                )

                // AI Estimate Ready card (shown when backend auto-created an estimate)
                if let latestEstimate = viewModel.latestEstimate, viewModel.hasAIEstimate {
                    AIEstimateReadyCard(
                        estimate: latestEstimate,
                        onReview: {
                            activeEstimate = ActiveEstimate(id: latestEstimate.id)
                        }
                    )
                }

                // Materials
                MaterialSuggestionsSection(
                    materials: viewModel.materials,
                    selectionState: viewModel.materialSelectionState,
                    selectedCount: viewModel.selectedMaterialCount,
                    selectedTotal: viewModel.selectedMaterialsTotal,
                    isDIY: viewModel.isDIY,
                    hasExistingEstimate: viewModel.hasAIEstimate,
                    onToggle: { id in viewModel.toggleMaterial(id: id) },
                    onToggleDIY: { viewModel.isDIY.toggle() },
                    onAddToEstimate: {
                        handleCreateEstimate()
                    }
                )

                // Estimates
                ProjectEstimatesSection(
                    estimates: viewModel.estimates,
                    onCreateEstimate: {
                        handleCreateEstimate()
                    },
                    onEstimateTap: { estimateId in
                        activeEstimate = ActiveEstimate(id: estimateId)
                    },
                    onCreateInvoice: { estimateId in
                        handleCreateInvoice(fromEstimateId: estimateId)
                    }
                )

                // Activity
                ProjectActivitySection(entries: viewModel.activityLog)

                // Bottom spacer
                Spacer(minLength: SpacingTokens.huge)
            }
            .padding(.vertical, SpacingTokens.sm)
        }
        .overlay {
            if isCreatingEstimate || isCreatingInvoice {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .overlay {
                        ProgressView(isCreatingInvoice ? "Creating invoice..." : "Creating estimate...")
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
            }
        }
    }

    // MARK: - Feature-Gated Actions

    private func handleGenerate(prompt: String) {
        let result = featureGateCoordinator.guardGeneratePreview()
        switch result {
        case .allowed:
            Task {
                await viewModel.startGeneration(prompt: prompt)
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

    private func handleCreateEstimate() {
        isCreatingEstimate = true
        Task {
            let estimate = await viewModel.createEstimate()
            isCreatingEstimate = false
            if let estimate {
                activeEstimate = ActiveEstimate(id: estimate.id)
            }
            // On nil: `viewModel.errorMessage` is set by createEstimate() and
            // surfaces via the `.alert` attached at the top of the view.
        }
    }

    private func handleCreateInvoice(fromEstimateId estimateId: String) {
        let result = featureGateCoordinator.guardCreateInvoice()
        switch result {
        case .allowed:
            isCreatingInvoice = true
            Task {
                let invoice = await viewModel.createInvoice(fromEstimateId: estimateId)
                isCreatingInvoice = false
                if let invoice {
                    activeInvoice = ActiveInvoice(id: invoice.id)
                }
            }
        case .blocked(let decision):
            paywallPresenter.present(decision)
        }
    }

    private func performProjectDeletion() async {
        isDeleting = true
        defer { isDeleting = false }
        let succeeded = await viewModel.deleteProject()
        if succeeded {
            // Return to the Projects tab list by popping the navigation stack.
            appState.selectedTab = .projects
            router.projectsPath = NavigationPath()
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
