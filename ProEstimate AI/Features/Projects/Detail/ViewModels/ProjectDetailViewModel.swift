import Foundation

/// Drives the project detail screen. Loads the full project, its AI
/// generations, material suggestions, linked estimates, and activity log.
/// Manages generation initiation and polling.
@MainActor
@Observable
final class ProjectDetailViewModel {
    // MARK: - State

    var project: Project?
    var generations: [AIGeneration] = []
    var materials: [MaterialSuggestion] = []
    var estimates: [Estimate] = []
    var activityLog: [ActivityLogEntry] = []
    var client: Client?
    var assets: [Asset] = []

    var isLoading: Bool = false
    var errorMessage: String?

    // MARK: - Generation State

    var isGenerating: Bool = false
    var currentGenerationStage: Int = 0

    /// Backing tasks for in-flight generation work so we can cancel on view disappear.
    private var generationTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?

    // MARK: - Material Selection

    /// Local toggle state for material suggestions. Key = material ID.
    var materialSelectionState: [String: Bool] = [:]

    /// Whether the user plans to do the work themselves (no labor costs).
    var isDIY: Bool = false

    var selectedMaterialCount: Int {
        materialSelectionState.values.filter { $0 }.count
    }

    var selectedMaterialsTotal: Decimal {
        materials
            .filter { materialSelectionState[$0.id] ?? $0.isSelected }
            .reduce(Decimal.zero) { $0 + $1.lineTotal }
    }

    /// Returns the currently selected materials.
    var selectedMaterials: [MaterialSuggestion] {
        materials.filter { materialSelectionState[$0.id] ?? $0.isSelected }
    }

    // MARK: - Dependencies

    private let projectService: ProjectServiceProtocol
    private let generationService: GenerationServiceProtocol
    private let estimateService: EstimateServiceProtocol
    private let clientService: ClientServiceProtocol

    // MARK: - Init

    init(
        projectService: ProjectServiceProtocol = LiveProjectService(),
        generationService: GenerationServiceProtocol = LiveGenerationService(),
        estimateService: EstimateServiceProtocol = LiveEstimateService(),
        clientService: ClientServiceProtocol = LiveClientService()
    ) {
        self.projectService = projectService
        self.generationService = generationService
        self.estimateService = estimateService
        self.clientService = clientService
    }

    // MARK: - Loading

    func loadProject(id: String) async {
        isLoading = true
        errorMessage = nil

        do {
            project = try await projectService.getProject(id: id)
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return
        }

        // Load sub-resources independently — one failure must not block the others
        async let gensTask: Void = loadGenerations(projectId: id)
        async let estimatesTask: Void = loadEstimates(projectId: id)
        async let assetsTask: Void = loadAssets(projectId: id)
        async let activityTask: Void = loadActivity(projectId: id)
        async let clientTask: Void = loadClient()

        _ = await (gensTask, estimatesTask, assetsTask, activityTask, clientTask)

        // Load materials from completed generations
        await loadMaterials()

        // Initialize selection state from server values
        for material in materials {
            materialSelectionState[material.id] = material.isSelected
        }

        isLoading = false
    }

    private func loadGenerations(projectId: String) async {
        generations = (try? await generationService.listGenerations(projectId: projectId)) ?? []
    }

    private func loadEstimates(projectId: String) async {
        estimates = (try? await estimateService.listByProject(projectId: projectId)) ?? []
    }

    private func loadAssets(projectId: String) async {
        assets = (try? await APIClient.shared.request(.listAssets(projectId: projectId))) ?? []
    }

    private func loadActivity(projectId: String) async {
        activityLog = (try? await APIClient.shared.request(.listActivityLog(projectId: projectId, cursor: nil))) ?? []
    }

    private func loadClient() async {
        guard let clientId = project?.clientId else { return }
        client = try? await clientService.getClient(id: clientId)
    }

    /// Fetch material suggestions from all completed generations.
    private func loadMaterials() async {
        var allMaterials: [MaterialSuggestion] = []
        for generation in generations where generation.status == .completed {
            if let mats: [MaterialSuggestion] = try? await APIClient.shared.request(
                .listMaterialSuggestions(generationId: generation.id)
            ) {
                allMaterials.append(contentsOf: mats)
            }
        }
        materials = allMaterials
    }

    // MARK: - AI Generation

    func startGeneration(prompt: String? = nil, materials: [MaterialSpec]? = nil) async {
        guard let project else { return }

        // If a previous run is still in flight, cancel it before starting a new one.
        cancelGeneration()

        isGenerating = true
        currentGenerationStage = 0

        // Start the progress simulation.
        startProgressSimulation()

        let effectivePrompt = prompt ?? project.description ?? "Generate a remodel preview for \(project.title)"

        // If the user has selected materials from a prior generation, pass them so the
        // new image reflects the chosen finishes.
        let effectiveMaterials: [MaterialSpec]? = materials ?? {
            let selected = selectedMaterials
            guard !selected.isEmpty else { return nil }
            return selected.map { MaterialSpec(from: $0) }
        }()

        // Drive the actual generation + polling on a cancellable Task so navigating
        // away tears it down cleanly.
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.stopProgressSimulation()
                self.isGenerating = false
            }

            do {
                let generation = try await self.generationService.startGeneration(
                    projectId: project.id,
                    prompt: effectivePrompt,
                    materials: effectiveMaterials
                )

                // Poll for completion — PiAPI typically takes 60-130 seconds.
                var completed = generation
                for _ in 0..<60 {
                    if Task.isCancelled { return }
                    try await Task.sleep(for: .seconds(3))
                    if Task.isCancelled { return }
                    completed = try await self.generationService.getGenerationStatus(id: generation.id)
                    if completed.status == .completed || completed.status == .failed {
                        break
                    }
                }

                if Task.isCancelled { return }
                self.generations.insert(completed, at: 0)

                if completed.status == .completed {
                    // Reload materials from the new generation.
                    await self.loadMaterials()
                    for material in self.materials {
                        if self.materialSelectionState[material.id] == nil {
                            self.materialSelectionState[material.id] = material.isSelected
                        }
                    }
                    // Reload estimates — backend may have auto-created one from materials.
                    await self.loadEstimates(projectId: project.id)
                } else if completed.status == .failed {
                    self.errorMessage = completed.errorMessage ?? "Image generation failed. Please try again."
                }
            } catch is CancellationError {
                // Silent — caller cancelled deliberately.
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }

        generationTask = task
        await task.value
    }

    /// Cancel any in-flight generation polling and progress simulation.
    /// Call from `.onDisappear` so navigating away doesn't leak background work.
    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        progressTask?.cancel()
        progressTask = nil
    }

    // MARK: - Deletion

    /// Permanently delete this project (and its cascading generations, assets,
    /// materials, estimates, proposals, and invoices). Returns `true` on success.
    @discardableResult
    func deleteProject() async -> Bool {
        guard let project else { return false }
        cancelGeneration()
        do {
            try await projectService.deleteProject(id: project.id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func refreshGenerationStatus() async {
        guard let project else { return }

        do {
            generations = try await generationService.listGenerations(projectId: project.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Estimate Creation

    /// Create a new estimate for this project via the backend.
    /// Automatically imports selected materials as line items.
    /// If `isDIY` is true, markup is 0 and no labor items are added.
    /// Returns the created Estimate or nil on failure.
    func createEstimate() async -> Estimate? {
        guard let project else { return nil }

        do {
            let body = CreateEstimateBody(projectId: project.id)
            let estimate: Estimate = try await APIClient.shared.request(.createEstimate(body: body))

            // Import selected materials as line items
            let materialsToImport = selectedMaterials
            for (index, material) in materialsToImport.enumerated() {
                let draft = LineItemDraft(
                    from: material,
                    estimateId: estimate.id,
                    isDIY: isDIY,
                    sortOrder: index
                )
                let lineItem = draft.toLineItem()
                let _: EstimateLineItem = try await APIClient.shared.request(
                    .createEstimateLineItem(estimateId: estimate.id, body: lineItem)
                )
            }

            // If professional mode (not DIY), add a placeholder labor line item
            if !isDIY && !materialsToImport.isEmpty {
                let laborDraft = LineItemDraft.defaultLabor(
                    estimateId: estimate.id,
                    projectType: project.projectType,
                    materialsCost: selectedMaterialsTotal,
                    sortOrder: 0
                )
                let laborItem = laborDraft.toLineItem()
                let _: EstimateLineItem = try await APIClient.shared.request(
                    .createEstimateLineItem(estimateId: estimate.id, body: laborItem)
                )
            }

            estimates.insert(estimate, at: 0)
            return estimate
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Material Selection

    func toggleMaterial(id: String) {
        let newValue = !(materialSelectionState[id] ?? false)
        materialSelectionState[id] = newValue
        Task {
            let _: MaterialSuggestion? = try? await APIClient.shared.request(
                .updateMaterialSelection(id: id, isSelected: newValue)
            )
        }
    }

    // MARK: - Computed Helpers

    /// The client name for display.
    var clientName: String? {
        client?.name
    }

    /// Whether the project has completed AI generations.
    var hasCompletedGenerations: Bool {
        generations.contains { $0.status == .completed }
    }

    /// Most recent completed generation.
    var latestGeneration: AIGeneration? {
        generations.first { $0.status == .completed }
    }

    /// Whether AI-generated estimates exist (auto-created after generation).
    var hasAIEstimate: Bool {
        !estimates.isEmpty && hasCompletedGenerations
    }

    /// The most recent estimate (typically the auto-created AI estimate).
    var latestEstimate: Estimate? {
        estimates.first
    }

    // MARK: - Progress Simulation

    private func startProgressSimulation() {
        let totalStages = GenerationStage.allCases.count
        progressTask?.cancel()
        progressTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for stage in 1..<totalStages {
                try? await Task.sleep(for: .milliseconds(800))
                if Task.isCancelled { return }
                self.currentGenerationStage = stage
            }
        }
    }

    private func stopProgressSimulation() {
        progressTask?.cancel()
        progressTask = nil
        currentGenerationStage = GenerationStage.allCases.count - 1
    }
}

// MARK: - Request Body

/// Body sent to POST /estimates to create a new estimate for a project.
private struct CreateEstimateBody: Encodable, Sendable {
    let projectId: String

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
    }
}
