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
    var invoices: [Invoice] = []
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
    private let estimateExportService: EstimateExportServiceProtocol
    private let proposalService: ProposalServiceProtocol
    private let invoiceService: InvoiceServiceProtocol

    // MARK: - Init

    init(
        projectService: ProjectServiceProtocol = LiveProjectService(),
        generationService: GenerationServiceProtocol = LiveGenerationService(),
        estimateService: EstimateServiceProtocol = LiveEstimateService(),
        clientService: ClientServiceProtocol = LiveClientService(),
        estimateExportService: EstimateExportServiceProtocol = LiveEstimateExportService(),
        proposalService: ProposalServiceProtocol = LiveProposalService(),
        invoiceService: InvoiceServiceProtocol = LiveInvoiceService()
    ) {
        self.projectService = projectService
        self.generationService = generationService
        self.estimateService = estimateService
        self.clientService = clientService
        self.estimateExportService = estimateExportService
        self.proposalService = proposalService
        self.invoiceService = invoiceService
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
        async let exportsTask: Void = loadEstimateExports(projectId: id)
        async let proposalsTask: Void = loadProposals(projectId: id)
        async let invoicesTask: Void = loadInvoices(projectId: id)

        _ = await (gensTask, estimatesTask, assetsTask, activityTask, clientTask, exportsTask, proposalsTask, invoicesTask)

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
        for material in materials {
            materialSelectionState[material.id] = material.isSelected
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
        }
    }

    private func loadGenerations(projectId: String) async {
        generations = (try? await generationService.listGenerations(projectId: projectId)) ?? []
    }

    private func loadEstimates(projectId: String) async {
        estimates = (try? await estimateService.listByProject(projectId: projectId)) ?? []
    }

    private func loadProposals(projectId: String) async {
        proposals = (try? await proposalService.listByProject(projectId: projectId)) ?? []
    }

    private func loadInvoices(projectId: String) async {
        invoices = (try? await invoiceService.listByProject(projectId: projectId)) ?? []
    }

    /// Refresh just the proposal + invoice lists. Called when a billing sheet
    /// dismisses so a status change (sent / paid) reflects on the project
    /// without re-running the full project load + generation lifecycle wiring.
    func reloadBilling() async {
        guard let projectId = project?.id else { return }
        async let proposalsTask: Void = loadProposals(projectId: projectId)
        async let invoicesTask: Void = loadInvoices(projectId: projectId)
        _ = await (proposalsTask, invoicesTask)
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

    /// Pull every persisted PDF export for this project's estimates and
    /// bucket them by `estimateId` so the per-row UI can render its
    /// "Saved exports" sublist without a second round-trip per estimate.
    private func loadEstimateExports(projectId: String) async {
        let all = (try? await estimateExportService.listByProject(projectId: projectId)) ?? []
        estimateExports = Dictionary(grouping: all, by: { $0.estimateId })
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
            // Backend has consumed one starter credit inside the gate's
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
        let coordinator = GenerationLifecycleCoordinator.shared
        for inFlight in generations where inFlight.status == .processing || inFlight.status == .queued {
            coordinator.cancel(generationId: inFlight.id)
        }
        stopObservingLifecycle()
        isGenerating = false
        awaitingGenerationId = nil
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
        do {
            let body = GenerateAIEstimateBody(projectId: project.id)
            let estimate: Estimate = try await APIClient.shared.request(.generateAIEstimate(body: body))
            estimates.insert(estimate, at: 0)
            return estimate
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Proposal & Invoice Creation

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

    /// Create an invoice from an existing estimate, seeding its line items.
    /// Requires the project to have a client (invoices are billed to a client).
    /// Errors are rethrown so the caller can route `APIError.paywall` to the
    /// paywall and surface other failures inline.
    func createInvoice(fromEstimateId estimateId: String) async throws -> Invoice {
        guard let estimate = estimates.first(where: { $0.id == estimateId }) else {
            throw InvoiceServiceError.notFound
        }
        guard let clientId = project?.clientId, !clientId.isEmpty else {
            throw InvoiceServiceError.missingClient
        }
        let lineItems = try await estimateService.getLineItems(estimateId: estimateId)
        let invoice = try await invoiceService.createFromEstimate(
            estimate: estimate,
            lineItems: lineItems,
            clientId: clientId
        )
        invoices.insert(invoice, at: 0)
        return invoice
    }

    /// Replace a proposal in local state after it round-trips (e.g. a send).
    func updateLocalProposal(_ proposal: Proposal) {
        if let index = proposals.firstIndex(where: { $0.id == proposal.id }) {
            proposals[index] = proposal
        } else {
            proposals.insert(proposal, at: 0)
        }
    }

    /// Replace an invoice in local state after it round-trips (e.g. send / paid).
    func updateLocalInvoice(_ invoice: Invoice) {
        if let index = invoices.firstIndex(where: { $0.id == invoice.id }) {
            invoices[index] = invoice
        } else {
            invoices.insert(invoice, at: 0)
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
