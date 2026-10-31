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
    var proposals: [Proposal] = []
    var activityLog: [ActivityLogEntry] = []
    var client: Client?
    var assets: [Asset] = []

    /// Saved PDF exports for each estimate, keyed by `estimate.id`. Hydrated
    /// from `GET /v1/projects/:id/estimate-exports` on project load and
    /// updated locally after a fresh export upload returns.
    var estimateExports: [String: [EstimateExport]] = [:]

    var isLoading: Bool = false
    var errorMessage: String?

    // MARK: - Generation State

    var isGenerating: Bool = false
    var currentGenerationStage: Int = 0

    /// Long-running observer of the App-level generation lifecycle
    /// coordinator. Owned by the VM so its lifetime matches the
    /// detail screen — we never want this to outlive the VM.
    /// Polling itself is owned by the coordinator and is independent
    /// of this Task, so cancelling it never interrupts an in-flight
    /// generation.
    private var lifecycleObservation: Task<Void, Never>?

    /// The generation ID this VM is currently animating progress for.
    /// `nil` when no foreground run is in flight from this screen — a
    /// completion event for any other gen on the project still
    /// refreshes data, but only this ID's terminal event stops the
    /// progress simulation and clears `isGenerating`.
    private var awaitingGenerationId: String?

    /// Backing task for the staged progress simulation. Local to the
    /// VM since it drives only UI animation, not server interaction.
    private var progressTask: Task<Void, Never>?

    // MARK: - Material Selection

    /// Local toggle state for material suggestions. Key = material ID.
    var materialSelectionState: [String: Bool] = [:]
    private var confirmedMaterialSelections: [String: Bool] = [:]
    private var materialSelectionRevisions: [String: Int] = [:]
    private var materialSelectionTasks: [String: Task<Void, Never>] = [:]

    /// Whether the user plans to do the work themselves (no labor costs).
    var isDIY: Bool = false

    var selectedMaterialCount: Int {
        selectedMaterials.count
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
    private let estimateExportService: EstimateExportServiceProtocol
    private let proposalService: ProposalServiceProtocol
    private let apiClient: APIClientProtocol

    // MARK: - Init

    init(
        projectService: ProjectServiceProtocol = LiveProjectService(),
        generationService: GenerationServiceProtocol = LiveGenerationService(),
        estimateService: EstimateServiceProtocol = LiveEstimateService(),
        clientService: ClientServiceProtocol = LiveClientService(),
        estimateExportService: EstimateExportServiceProtocol = LiveEstimateExportService(),
        proposalService: ProposalServiceProtocol = LiveProposalService(),
        apiClient: APIClientProtocol = APIClient.shared
    ) {
        self.projectService = projectService
        self.generationService = generationService
        self.estimateService = estimateService
        self.clientService = clientService
        self.estimateExportService = estimateExportService
        self.proposalService = proposalService
        self.apiClient = apiClient
    }

    // MARK: - Loading

    func loadProject(id: String) async {
        guard !isLoading else { return }
        let selectionRevisionsAtLoad = materialSelectionRevisions
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
        async let exportsTask: Void = loadEstimateExports(projectId: id)
        async let proposalsTask: Void = loadProposals(projectId: id)

        _ = await (gensTask, estimatesTask, assetsTask, activityTask, clientTask, exportsTask, proposalsTask)

        // Warm URLCache for the photo grid (~320pt wide cards) and the
        // before/after preview (full-bleed). Backend snaps to canonical
        // buckets, so 320 → 480 and 960 → 960 in practice. Both fire in
        // parallel; the prefetcher silently dedups against URLs already
        // resolved by the dashboard.
        let assetURLs = assets.flatMap { asset -> [URL] in
            let base = asset.thumbnailURL ?? asset.url
            return [base.thumbnail(width: 320)]
        }
        let generationURLs = generations
            .compactMap { $0.previewURL }
            .map { $0.thumbnail(width: 960) }
        ThumbnailPrefetcher.shared.prefetch(assetURLs + generationURLs)

        // Load materials from completed generations
        await loadMaterials()

        // Initialize selection state from server values
        let activeMaterialIDs = Set(materials.map(\.id))
        materialSelectionState = materialSelectionState.filter { activeMaterialIDs.contains($0.key) }
        for material in materials where materialSelectionTasks[material.id] == nil
            && materialSelectionRevisions[material.id] == selectionRevisionsAtLoad[material.id] {
            materialSelectionState[material.id] = material.isSelected
            confirmedMaterialSelections[material.id] = material.isSelected
        }

        isLoading = false

        // Make sure we're listening for terminal events on any in-flight
        // gen this VM cares about. Idempotent.
        startObservingLifecycleIfNeeded()

        // If the project shows a queued/processing gen on load (either
        // freshly resumed from cold launch by the App-level coordinator
        // or carried over from a previous VM instance), make sure the
        // coordinator is polling it AND that our local UI reflects the
        // in-flight state. Both calls are idempotent so a repeat
        // navigation back to the screen is harmless.
        if let inFlight = generations.first(where: { $0.status == .processing || $0.status == .queued }) {
            GenerationLifecycleCoordinator.shared.registerStart(
                generationId: inFlight.id,
                projectId: id,
                projectTitle: project?.title
            )
            awaitingGenerationId = inFlight.id
            isGenerating = true
            currentGenerationStage = 2
            startProgressSimulation()
        } else if isGenerating, awaitingGenerationId != nil {
            stopProgressSimulation()
            awaitingGenerationId = nil
            isGenerating = false
        }
    }

    private func loadGenerations(projectId: String) async {
        do { generations = try await generationService.listGenerations(projectId: projectId) }
        catch { reportRefreshFailure("AI previews", error: error) }
    }

    private func loadEstimates(projectId: String) async {
        do { estimates = try await estimateService.listByProject(projectId: projectId) }
        catch { reportRefreshFailure("estimates", error: error) }
    }

    private func loadProposals(projectId: String) async {
        do { proposals = try await proposalService.listByProject(projectId: projectId) }
        catch { reportRefreshFailure("proposals", error: error) }
    }

    /// Refresh just the proposal list. Called when the proposal sheet
    /// dismisses so a status change (sent / viewed) reflects on the project
    /// without re-running the full project load + generation lifecycle wiring.
    func reloadProposals() async {
        guard let projectId = project?.id else { return }
        await loadProposals(projectId: projectId)
    }

    private func loadAssets(projectId: String) async {
        do { assets = try await apiClient.request(.listAssets(projectId: projectId)) }
        catch { reportRefreshFailure("photos", error: error) }
    }

    private func loadActivity(projectId: String) async {
        do { activityLog = try await apiClient.request(.listActivityLog(projectId: projectId, cursor: nil)) }
        catch { reportRefreshFailure("activity", error: error) }
    }

    private func loadClient() async {
        guard let clientId = project?.clientId else { client = nil; return }
        do { client = try await clientService.getClient(id: clientId) }
        catch { reportRefreshFailure("client", error: error) }
    }

    /// Pull every persisted PDF export for this project's estimates and
    /// bucket them by `estimateId` so the per-row UI can render its
    /// "Saved exports" sublist without a second round-trip per estimate.
    private func loadEstimateExports(projectId: String) async {
        do {
            let all = try await estimateExportService.listByProject(projectId: projectId)
            estimateExports = Dictionary(grouping: all, by: { $0.estimateId })
        } catch { reportRefreshFailure("saved exports", error: error) }
    }

    /// Insert a freshly-uploaded export at the top of its bucket so the UI
    /// reflects the new save without waiting on the next project refresh.
    func registerNewExport(_ export: EstimateExport) {
        var existing = estimateExports[export.estimateId] ?? []
        existing.insert(export, at: 0)
        estimateExports[export.estimateId] = existing
    }

    /// Remove a deleted export from local state.
    func removeExport(_ export: EstimateExport) {
        guard var bucket = estimateExports[export.estimateId] else { return }
        bucket.removeAll { $0.id == export.id }
        if bucket.isEmpty {
            estimateExports.removeValue(forKey: export.estimateId)
        } else {
            estimateExports[export.estimateId] = bucket
        }
    }

    /// Fetch material suggestions from all completed generations.
    private func loadMaterials() async {
        var allMaterials: [MaterialSuggestion] = []
        for generation in generations where generation.status == .completed {
            do {
                let mats: [MaterialSuggestion] = try await apiClient.request(.listMaterialSuggestions(generationId: generation.id))
                allMaterials.append(contentsOf: mats)
            } catch {
                allMaterials.append(contentsOf: materials.filter { $0.generationId == generation.id })
                reportRefreshFailure("materials", error: error)
            }
        }
        materials = allMaterials
    }

    private func reportRefreshFailure(_ resource: String, error: Error) {
        guard !Task.isCancelled else { return }
        errorMessage = "Couldn't refresh \(resource). \(error.localizedDescription) Pull to refresh to try again."
    }

    // MARK: - AI Generation

    var generationPaywall: PaywallDecision?

    func startGeneration(prompt: String? = nil, materials: [MaterialSpec]? = nil) async {
        // Multiple taps can arrive before SwiftUI redraws the loading state.
        guard !isGenerating, let project else { return }
        errorMessage = nil

        isGenerating = true
        currentGenerationStage = 0
        startProgressSimulation()

        let effectivePrompt = prompt ?? project.description ?? "Generate a remodel preview for \(project.title)"

        // If the user has selected materials from a prior generation, pass them so the
        // new image reflects the chosen finishes.
        let effectiveMaterials: [MaterialSpec]? = materials ?? {
            let selected = selectedMaterials
            guard !selected.isEmpty else { return nil }
            return selected.map { MaterialSpec(from: $0) }
        }()

        do {
            let generation = try await generationService.startGeneration(
                projectId: project.id,
                prompt: effectivePrompt,
                materials: effectiveMaterials,
                generatePreview: project.aiPreviewEnabled
            )
            // The backend has reserved the paid allowance inside the gate's
            // transaction; mirror that locally so the next tap reflects
            // the new remaining count without waiting on entitlement
            // refresh.
            UsageMeterStore.shared.recordGenerationConsumed()

            // Insert the QUEUED record so the UI immediately shows
            // "in progress" state without waiting for a refresh.
            generations.insert(generation, at: 0)
            awaitingGenerationId = generation.id

            // Hand off polling to the coordinator. From here, completion
            // arrives via the lifecycle event stream — this method is
            // free to return.
            GenerationLifecycleCoordinator.shared.registerStart(
                generationId: generation.id,
                projectId: project.id,
                projectTitle: project.title
            )
            startObservingLifecycleIfNeeded()
        } catch let APIError.paywall(decision) {
            stopProgressSimulation()
            isGenerating = false
            generationPaywall = decision
        } catch is CancellationError {
            stopProgressSimulation()
            isGenerating = false
        } catch {
            stopProgressSimulation()
            isGenerating = false
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Lifecycle Observation

    /// Subscribe to the App-level coordinator's event stream, filtering
    /// for events that belong to this project. Idempotent — repeat
    /// calls do not stack observation tasks.
    @MainActor
    func startObservingLifecycleIfNeeded() {
        guard lifecycleObservation == nil else { return }
        let coordinator = GenerationLifecycleCoordinator.shared
        lifecycleObservation = Task { @MainActor [weak self] in
            for await event in coordinator.events {
                guard let self else { return }
                await self.handleLifecycleEvent(event)
            }
        }
    }

    /// Stop observing without cancelling any in-flight polling. Called
    /// from `.onDisappear` and on sign-out so the VM doesn't leak its
    /// observation Task while the coordinator keeps polling globally.
    @MainActor
    func stopObservingLifecycle() {
        lifecycleObservation?.cancel()
        lifecycleObservation = nil
        progressTask?.cancel()
        progressTask = nil
    }

    private func handleLifecycleEvent(_ event: GenerationLifecycleCoordinator.Event) async {
        guard let project, event.projectId == project.id else { return }

        switch event {
        case let .completed(generationId, _):
            // Refresh the canonical generation record + dependent
            // materials/estimates. We re-fetch instead of trusting a
            // local snapshot to avoid stale-write races against the
            // backend's auto-created estimate insert.
            await refreshGenerationStatus()
            await loadMaterials()
            for material in materials {
                if materialSelectionState[material.id] == nil {
                    materialSelectionState[material.id] = material.isSelected
                }
            }
            await loadEstimates(projectId: project.id)

            if generationId == awaitingGenerationId {
                stopProgressSimulation()
                isGenerating = false
                awaitingGenerationId = nil
            }
        case let .failed(generationId, _, message):
            await refreshGenerationStatus()
            errorMessage = message ?? "Image generation failed. Please try again."

            if generationId == awaitingGenerationId {
                stopProgressSimulation()
                isGenerating = false
                awaitingGenerationId = nil
            }
        }
    }

    // MARK: - Deletion

    /// Permanently delete this project (and its cascading generations, assets,
    /// materials, estimates, proposals, and invoices). Returns `true` on success.
    @discardableResult
    func deleteProject() async -> Bool {
        guard let project else { return false }
        // Tear down any in-flight polling for this project's generations
        // so the coordinator doesn't continue ticking against a now-404
        // record after the cascade delete commits server-side.
        do {
            try await projectService.deleteProject(id: project.id)
            GenerationLifecycleCoordinator.shared.cancel(projectId: project.id)
            stopObservingLifecycle()
            stopProgressSimulation()
            isGenerating = false
            awaitingGenerationId = nil
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
        await finishMaterialSelections()

        var createdEstimate: Estimate?
        do {
            let body = CreateEstimateBody(projectId: project.id)
            let estimate: Estimate = try await apiClient.request(.createEstimate(body: body))
            createdEstimate = estimate

            // Import selected materials as line items
            let materialsToImport = selectedMaterials
            var items: [EstimateLineItem] = []
            for (index, material) in materialsToImport.enumerated() {
                let draft = LineItemDraft(
                    from: material,
                    estimateId: estimate.id,
                    isDIY: isDIY,
                    sortOrder: index
                )
                items.append(draft.toLineItem())
            }

            // If professional mode (not DIY), add a placeholder labor line item
            if !isDIY && !materialsToImport.isEmpty {
                let laborDraft = LineItemDraft.defaultLabor(
                    estimateId: estimate.id,
                    projectType: project.projectType,
                    materialsCost: selectedMaterialsTotal,
                    sortOrder: items.count
                )
                items.append(laborDraft.toLineItem())
            }

            if !items.isEmpty {
                let _: [EstimateLineItem] = try await apiClient.request(
                    .batchCreateEstimateLineItems(estimateId: estimate.id, body: EstimateLineItemsBatch(items: items))
                )
            }
            // Line insertion recalculates server totals. Display those totals,
            // rather than the zero-valued snapshot returned before insertion.
            let refreshed: Estimate = try await apiClient.request(.getEstimate(id: estimate.id))
            estimates.insert(refreshed, at: 0)
            return refreshed
        } catch {
            // A transport error may arrive after a successful server write.
            // Retain and refresh the confirmed creation for review.
            if let createdEstimate {
                estimates.insert(createdEstimate, at: 0)
                await loadEstimates(projectId: project.id)
            }
            errorMessage = createdEstimate == nil
                ? error.localizedDescription
                : "The estimate was created, but the remaining steps couldn't finish. Review it before creating another estimate. \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - AI-Generated Estimate

    /// POST /v1/estimates/generate — asks the backend to use Gemini with a
    /// specialized estimator system prompt to produce a full, professional
    /// estimate (title, overview, materials + labor + other line items,
    /// assumptions, exclusions, terms) grounded in the project's selected
    /// materials, the company's branding, and any configured pricing
    /// profile. The backend persists the estimate + every line item, so on
    /// success the caller can navigate directly to the editor.
    func generateAIEstimate() async -> Estimate? {
        guard let project else { return nil }
        await finishMaterialSelections()
        do {
            let body = GenerateAIEstimateBody(projectId: project.id)
            let estimate: Estimate = try await apiClient.request(.generateAIEstimate(body: body))
            estimates.insert(estimate, at: 0)
            return estimate
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Proposal Creation

    /// Create a client-facing proposal from an existing estimate. Errors are
    /// rethrown so the caller can route `APIError.paywall` to the paywall and
    /// surface other failures inline.
    func createProposal(fromEstimateId estimateId: String) async throws -> Proposal {
        let proposal = try await proposalService.createFromEstimate(
            estimateId: estimateId,
            title: nil,
            clientMessage: nil
        )
        proposals.insert(proposal, at: 0)
        return proposal
    }

    /// Replace a proposal in local state after it round-trips (e.g. a send).
    func updateLocalProposal(_ proposal: Proposal) {
        if let index = proposals.firstIndex(where: { $0.id == proposal.id }) {
            proposals[index] = proposal
        } else {
            proposals.insert(proposal, at: 0)
        }
    }

    // MARK: - Material Selection

    func toggleMaterial(id: String) {
        guard let material = materials.first(where: { $0.id == id }) else { return }
        let newValue = !(materialSelectionState[id] ?? material.isSelected)
        materialSelectionState[id] = newValue
        let revision = (materialSelectionRevisions[id] ?? 0) + 1
        materialSelectionRevisions[id] = revision
        let previousTask = materialSelectionTasks[id]
        let sessionID = TokenStore.shared.sessionIdentifier
        let projectID = project?.id
        let task = Task { @MainActor [self] in
            await previousTask?.value
            guard materialSelectionRevisions[id] == revision else { return }
            defer {
                if materialSelectionRevisions[id] == revision { materialSelectionTasks[id] = nil }
            }
            guard TokenStore.shared.sessionIdentifier == sessionID, project?.id == projectID else { return }
            do {
                let updated: MaterialSuggestion = try await apiClient.request(.updateMaterialSelection(id: id, isSelected: newValue))
                guard TokenStore.shared.sessionIdentifier == sessionID, project?.id == projectID else { return }
                confirmedMaterialSelections[id] = updated.isSelected
                if materialSelectionRevisions[id] == revision {
                    materialSelectionState[id] = updated.isSelected
                }
            } catch {
                guard materialSelectionRevisions[id] == revision,
                      TokenStore.shared.sessionIdentifier == sessionID else { return }
                materialSelectionState[id] = confirmedMaterialSelections[id] ?? material.isSelected
                errorMessage = "Couldn't save the material selection. \(error.localizedDescription)"
            }
        }
        materialSelectionTasks[id] = task
    }

    private func finishMaterialSelections() async {
        while !materialSelectionTasks.isEmpty {
            let tasks = Array(materialSelectionTasks.values)
            for task in tasks { await task.value }
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

    /// Dwell time per stage before advancing to the next. Tuned so the
    /// timeline does not sprint to "Complete" in a few seconds while the
    /// real generation takes 60–130s. We never advance past `.enhancing`
    /// from the timer — `stopProgressSimulation()` jumps to `.complete`
    /// when the backend returns a finished generation.
    private static let stageDwellSeconds: [Double] = [
        5,    // .uploading -> .analyzing
        6,    // .analyzing -> .generating
        45,   // .generating -> .enhancing
        // .enhancing is the last timer-driven stage; it stays here until
        // the backend finishes and stopProgressSimulation fires.
    ]

    private func startProgressSimulation() {
        progressTask?.cancel()
        progressTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for (index, dwell) in Self.stageDwellSeconds.enumerated() {
                try? await Task.sleep(for: .seconds(dwell))
                if Task.isCancelled { return }
                // Advance to the NEXT stage (index + 1). The loop therefore
                // walks 0 -> 1 -> 2 -> 3, stopping at `.enhancing`.
                let nextStage = index + 1
                self.currentGenerationStage = nextStage
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

/// Body sent to POST /estimates/generate to AI-generate a full professional
/// estimate from the project context, selected materials, and company data.
private struct GenerateAIEstimateBody: Encodable, Sendable {
    let projectId: String

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
    }
}
