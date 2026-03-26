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

    // MARK: - Init

    init(
        projectService: ProjectServiceProtocol = MockProjectService(),
        generationService: GenerationServiceProtocol = MockGenerationService()
    ) {
        self.projectService = projectService
        self.generationService = generationService
    }

    // MARK: - Loading

    func loadProject(id: String) async {
        isLoading = true
        errorMessage = nil

        do {
            project = try await projectService.getProject(id: id)
            async let gens = generationService.listGenerations(projectId: id)
            generations = try await gens

            // Load mock materials and estimates
            materials = MockGenerationService.sampleMaterials.filter { $0.projectId == id }
            estimates = MockGenerationService.sampleEstimates.filter { $0.projectId == id }
            activityLog = ActivityLogEntry.samples.filter { $0.projectId == id }

            // Initialize selection state from server values
            for material in materials {
                materialSelectionState[material.id] = material.isSelected
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - AI Generation

    func startGeneration() async {
        guard let project else { return }

        isGenerating = true
        currentGenerationStage = 0

        // Start the timer to simulate progress through stages
        startProgressSimulation()

        do {
            let generation = try await generationService.startGeneration(
                projectId: project.id,
                prompt: project.description ?? "Generate a remodel preview"
            )

            // Poll for completion (mock completes quickly)
            try await Task.sleep(nanoseconds: 3_000_000_000)
            let completed = try await generationService.getGenerationStatus(id: generation.id)
            generations.insert(completed, at: 0)
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

    // MARK: - Material Selection

    func toggleMaterial(id: String) {
        materialSelectionState[id] = !(materialSelectionState[id] ?? false)
    }

    // MARK: - Computed Helpers

    /// The client name for display, derived from mock data.
    var clientName: String? {
        guard let clientId = project?.clientId else { return nil }
        return MockProjectService.sampleClients.first(where: { $0.id == clientId })?.name
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
