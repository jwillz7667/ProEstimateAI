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

    var selectedMaterialCount: Int {
        materialSelectionState.values.filter { $0 }.count
    }

    var selectedMaterialsTotal: Decimal {
        materials
            .filter { materialSelectionState[$0.id] ?? $0.isSelected }
            .reduce(Decimal.zero) { $0 + $1.lineTotal }
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

            // Load data from real API in parallel
            async let gensTask = generationService.listGenerations(projectId: id)
            async let estimatesTask = estimateService.listByProject(projectId: id)
            async let assetsTask: [Asset] = APIClient.shared.request(.listAssets(projectId: id))

            generations = try await gensTask
            estimates = try await estimatesTask
            assets = (try? await assetsTask) ?? []

            // Load materials from completed generations
            await loadMaterials()

            // Load client if project has one
            if let clientId = project?.clientId {
                client = try? await clientService.getClient(id: clientId)
            }

            // Initialize selection state from server values
            for material in materials {
                materialSelectionState[material.id] = material.isSelected
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
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

            // Poll for completion — Nano Banana 2 typically takes 15-35 seconds
            var completed = generation
            for _ in 0..<24 {
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 second intervals
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
    /// Returns the created Estimate or nil on failure.
    func createEstimate() async -> Estimate? {
        guard let project else { return nil }

        do {
            let body = CreateEstimateBody(projectId: project.id)
            let estimate: Estimate = try await APIClient.shared.request(.createEstimate(body: body))
            estimates.insert(estimate, at: 0)
            return estimate
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Material Selection

    func toggleMaterial(id: String) {
        materialSelectionState[id] = !(materialSelectionState[id] ?? false)
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
