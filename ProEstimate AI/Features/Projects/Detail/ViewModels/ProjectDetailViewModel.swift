import Foundation

/// Drives the project detail screen. Loads the full project, its AI
/// generations, material suggestions, linked estimates, and activity log.
/// Manages generation initiation and polling.
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
    var generationProgressTimer: Timer?

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

    func startGeneration() async {
        guard let project else { return }

        isGenerating = true
        currentGenerationStage = 0

        // Start the timer to animate progress stages
        startProgressSimulation()

        do {
            let generation = try await generationService.startGeneration(
                projectId: project.id,
                prompt: project.description ?? "Generate a remodel preview for \(project.title)"
            )

            // Poll for completion — PiAPI typically takes 60-130 seconds
            var completed = generation
            for _ in 0..<60 {
                try await Task.sleep(nanoseconds: 3_000_000_000) // 3 second intervals (max 3 min)
                completed = try await generationService.getGenerationStatus(id: generation.id)
                if completed.status == .completed || completed.status == .failed {
                    break
                }
            }

            generations.insert(completed, at: 0)

            if completed.status == .completed {
                // Reload materials from the new generation
                await loadMaterials()
                for material in materials {
                    if materialSelectionState[material.id] == nil {
                        materialSelectionState[material.id] = material.isSelected
                    }
                }
            } else if completed.status == .failed {
                errorMessage = completed.errorMessage ?? "Image generation failed. Please try again."
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        stopProgressSimulation()
        isGenerating = false
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

    // MARK: - Progress Simulation

    private func startProgressSimulation() {
        let totalStages = GenerationStage.allCases.count
        generationProgressTimer = Timer.scheduledTimer(
            withTimeInterval: 0.8,
            repeats: true
        ) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            if self.currentGenerationStage < totalStages - 1 {
                self.currentGenerationStage += 1
            } else {
                timer.invalidate()
            }
        }
    }

    private func stopProgressSimulation() {
        generationProgressTimer?.invalidate()
        generationProgressTimer = nil
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
