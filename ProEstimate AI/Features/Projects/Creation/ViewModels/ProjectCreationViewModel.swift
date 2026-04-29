import Foundation
import PhotosUI
import SwiftUI

/// Drives the four-step project creation flow.
///
/// Inputs flow forward only — no review step. After the user taps
/// "Create Project" on the details step, the view model transitions to
/// the `.generating` step and runs a four-stage pipeline (create →
/// upload photos → start generation → poll until complete) so the user
/// sees a single continuous loading screen and lands on a fully-rendered
/// project detail screen instead of a half-loaded shell.
@Observable
@MainActor
final class ProjectCreationViewModel {
    // MARK: - Step Navigation

    var currentStep: Int = 0

    var totalSteps: Int {
        ProjectCreationStep.allCases.count
    }

    /// Number of navigable input steps in the active flow (excludes the
    /// trailing `.generating` loading step, and excludes `.lawnMap`
    /// unless the user picked a lawn-care project type). Drives the
    /// progress-indicator pill count so the bar is accurate per flow.
    var navigableStepCount: Int {
        // Standard: type + photos + details = 3. Lawn care adds the
        // lawnMap step between photos and details for a total of 4.
        isLawnCareFlow ? 4 : 3
    }

    var currentStepEnum: ProjectCreationStep {
        ProjectCreationStep(rawValue: currentStep) ?? .type
    }

    /// Whether the active flow needs the lawn measurement step. Lawn-
    /// care contracts price by measured area (per-sq-ft fertilizer,
    /// per-acre treatments) so the polygon is the load-bearing input —
    /// the AI estimate downstream reads the same `lawn_area_sq_ft`
    /// the map captures here.
    var isLawnCareFlow: Bool {
        selectedProjectType == .lawnCare
    }

    // MARK: - Step 0: Project Type

    var selectedProjectType: Project.ProjectType?

    // MARK: - Step 1: Photos + Prompt

    var selectedPhotosItems: [PhotosPickerItem] = []
    var selectedImageData: [Data] = []
    var isLoadingImages: Bool = false
    /// User-facing error if one or more picker items failed to transfer
    /// from the Photos library. Cleared on a successful retry.
    var imageLoadError: String?

    /// User-tapped suggestion card — drives the AI prompt's stylistic
    /// baseline. `nil` means the user is going prompt-only.
    var selectedPromptCard: PromptCard?

    /// Free-form additions the user types beneath the suggestion cards.
    /// Combined with the selected card's prompt at submission time.
    var customInstructions: String = ""

    let maxCustomInstructionsLength: Int = 1000

    var customInstructionsCharacterCount: Int {
        customInstructions.count
    }

    // MARK: - Lawn Measurement (lawn-care flow only)

    /// The map-driven lawn polygon capture VM. Lazily instantiated on
    /// first access so non-lawn-care flows never spin up MapKit
    /// machinery. The wizard owns this lifecycle so the polygon survives
    /// step navigation (Back from `.lawnMap` keeps the existing
    /// vertices) and so the pipeline can persist the area to the
    /// project after creation.
    @ObservationIgnored
    private var _lawnMeasurementVM: LawnMeasurementViewModel?

    var lawnMeasurementVM: LawnMeasurementViewModel {
        if let vm = _lawnMeasurementVM { return vm }
        let vm = LawnMeasurementViewModel(
            projectId: nil,
            initialCenter: nil,
            service: mapsService
        )
        _lawnMeasurementVM = vm
        return vm
    }

    /// Whether the user has dropped enough vertices for a valid polygon
    /// (3+). Mirrors the lawn VM's gate so the wizard's `canProceed`
    /// can drive the Next button without leaking MapKit types into the
    /// rest of the wizard.
    var hasValidLawnPolygon: Bool {
        _lawnMeasurementVM?.hasValidPolygon ?? false
    }

    // MARK: - Step 2: Details

    /// Optional user-supplied project title. When empty, `generatedTitle`
    /// falls back to a sensible default built from the selected type.
    var customTitle: String = ""

    var squareFootageText: String = ""
    var lotSizeText: String = ""
    var budgetMinText: String = ""
    var budgetMaxText: String = ""
    var qualityTier: Project.QualityTier = .standard

    var squareFootage: Decimal? {
        Decimal(string: squareFootageText)
    }

    var lotSize: Decimal? {
        Decimal(string: lotSizeText)
    }

    var budgetMin: Decimal? {
        Decimal(string: budgetMinText)
    }

    var budgetMax: Decimal? {
        Decimal(string: budgetMaxText)
    }

    // MARK: - Step 3: Generation Pipeline

    /// Stage of the post-create pipeline. `.idle` until the user taps
    /// "Create Project" on the details step.
    var pipelineStage: CreationPipelineStage = .idle

    /// The newly created project, set once the create-project API call
    /// succeeds. Used by the wizard host to fire `onProjectCreated`.
    var createdProject: Project?

    /// The first generation kicked off by the pipeline, polled to
    /// completion before the wizard dismisses.
    var pendingGeneration: AIGeneration?

    /// Long-form pipeline error (after retries / on hard failure).
    /// Drives the inline retry banner on the loading screen.
    var pipelineError: String?

    /// Whether any pipeline stage is currently running. Disables back
    /// navigation and the dismiss gesture during in-flight work.
    var isPipelineRunning: Bool {
        switch pipelineStage {
        case .creating, .uploadingPhotos, .startingGeneration, .generating, .generatingMaterials:
            return true
        case .idle, .completed, .failed:
            return false
        }
    }

    // MARK: - Submission Convenience

    var isSubmitting: Bool {
        isPipelineRunning
    }

    // MARK: - Dependencies

    private let projectService: ProjectServiceProtocol
    private let generationService: GenerationServiceProtocol
    private let mapsService: MapsServiceProtocol
    private let apiClient: APIClientProtocol

    /// Polling cadence for generation status. 3s strikes a balance
    /// between perceived responsiveness and backend load.
    private let pollInterval: UInt64 = 3_000_000_000

    /// Hard ceiling on poll attempts. 60 attempts × 3s ≈ 3 minutes —
    /// well past the typical 60–90s generation time but bounded so a
    /// stalled job can't keep the wizard open forever.
    private let maxPollAttempts: Int = 60

    // MARK: - Init

    init(
        projectService: ProjectServiceProtocol = LiveProjectService(),
        generationService: GenerationServiceProtocol = LiveGenerationService(),
        mapsService: MapsServiceProtocol = LiveMapsService(),
        apiClient: APIClientProtocol = APIClient.shared
    ) {
        self.projectService = projectService
        self.generationService = generationService
        self.mapsService = mapsService
        self.apiClient = apiClient
    }

    // MARK: - Computed Validation

    /// Whether the user can proceed from the current step.
    var canProceed: Bool {
        switch currentStepEnum {
        case .type:
            return selectedProjectType != nil
        case .photos:
            // Lawn-care projects don't need an uploaded photo — the
            // generation works from the lawn-care prompt + the
            // measured polygon captured in the next step. Other types
            // still need at least one before-photo so the AI has a
            // surface to remodel against. A resolved prompt (either a
            // suggestion card or custom instructions) is always
            // required.
            if isLawnCareFlow {
                return hasResolvedPrompt
            }
            return !selectedImageData.isEmpty && hasResolvedPrompt
        case .lawnMap:
            // Polygon must be closed (3+ vertices) before we can
            // estimate per-area pricing.
            return hasValidLawnPolygon
        case .details:
            // Name + advanced fields are all optional.
            return true
        case .generating:
            return false
        }
    }

    /// True when the user has supplied either a tapped suggestion card
    /// or non-empty custom instructions (or both).
    var hasResolvedPrompt: Bool {
        if selectedPromptCard != nil { return true }
        return !customInstructions
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    /// Final prompt sent to the generation pipeline. Combines the
    /// selected card's baseline with the user's custom layer.
    var resolvedPrompt: String {
        var parts: [String] = []
        if let card = selectedPromptCard {
            parts.append(card.prompt)
        }
        let custom = customInstructions
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            parts.append(custom)
        }
        return parts.joined(separator: " ")
    }

    var detectedLanguage: String {
        // Simple heuristic: if prompt contains common Spanish words, hint Spanish.
        let spanishIndicators = [
            "cocina", "bano", "piso", "techo", "pintura", "habitacion", "remodelacion",
        ]
        let lowered = resolvedPrompt.lowercased()
        for word in spanishIndicators where lowered.contains(word) {
            return "Spanish"
        }
        return "English"
    }

    /// Project title that gets sent to the backend. Uses `customTitle`
    /// when the user has filled it in; otherwise falls back to an
    /// auto-generated string built from the selected type.
    var generatedTitle: String {
        let trimmed = customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }

        guard let type = selectedProjectType else { return "Project" }
        switch type {
        case .kitchen: return "Kitchen Remodel"
        case .bathroom: return "Bathroom Renovation"
        case .flooring: return "Flooring Install"
        case .roofing: return "Roof Replacement"
        case .painting: return "Painting Project"
        case .siding: return "Siding Replacement"
        case .roomRemodel: return "Room Remodel"
        case .exterior: return "Exterior Renovation"
        case .landscaping: return "Landscape Install"
        case .lawnCare: return "Lawn Care Contract"
        case .custom: return "Custom Project"
        }
    }

    /// Free-text dimensions field appended to the project record. Lot
    /// size doesn't have a dedicated backend column, so we compose a
    /// human-readable summary the AI material/labor pass can reference.
    var composedDimensions: String? {
        var parts: [String] = []
        if let sqft = squareFootage {
            parts.append("Project: \(formatDecimal(sqft)) sqft")
        }
        if let lot = lotSize {
            parts.append("Lot: \(formatDecimal(lot)) sqft")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func formatDecimal(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    // MARK: - Step Actions

    func nextStep() {
        guard canProceed, currentStep < totalSteps - 1 else { return }
        var next = currentStep + 1
        // Skip the lawn measurement step when the user isn't building a
        // lawn-care project. The map step is only meaningful when we're
        // about to estimate per-area pricing.
        if ProjectCreationStep(rawValue: next) == .lawnMap, !isLawnCareFlow {
            next += 1
        }
        guard next < totalSteps else { return }
        currentStep = next
    }

    func previousStep() {
        // Guard against going back into the loading step or pre-step 0.
        guard !isPipelineRunning, currentStep > 0 else { return }
        var prev = currentStep - 1
        // Mirror the forward skip — non-lawn-care flows never see
        // `.lawnMap`, so Back from `.details` jumps straight to
        // `.photos` instead of an empty map step.
        if ProjectCreationStep(rawValue: prev) == .lawnMap, !isLawnCareFlow {
            prev -= 1
        }
        currentStep = prev
    }

    /// Jump straight to the loading step. Called when the user taps
    /// "Create Project" on the details step.
    func enterGeneratingStep() {
        currentStep = ProjectCreationStep.generating.rawValue
    }

    func selectPromptCard(_ card: PromptCard) {
        selectedPromptCard = card
    }

    func clearPromptCard() {
        selectedPromptCard = nil
    }

    // MARK: - Photos

    func loadImages() async {
        isLoadingImages = true
        imageLoadError = nil

        var loadedData: [Data] = []
        var failedCount = 0

        for item in selectedPhotosItems {
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    loadedData.append(data)
                } else {
                    failedCount += 1
                }
            } catch {
                failedCount += 1
            }
        }

        selectedImageData = loadedData
        isLoadingImages = false

        if failedCount > 0 {
            let plural = failedCount == 1 ? "photo" : "photos"
            imageLoadError = "\(failedCount) \(plural) couldn't be loaded. Retry, or continue with the \(loadedData.count) that loaded."
        }
    }

    /// Clear the image-load error banner.
    func clearImageLoadError() {
        imageLoadError = nil
    }

    func removeImage(at index: Int) {
        guard index < selectedImageData.count else { return }
        selectedImageData.remove(at: index)
        if index < selectedPhotosItems.count {
            selectedPhotosItems.remove(at: index)
        }
    }

    /// Adds an image captured from the camera to the selected images array.
    func addCameraImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        selectedImageData.append(data)
    }

    // MARK: - Pipeline

    /// Runs the full create → upload → generate → poll pipeline. The
    /// caller (the wizard's `Generating` step view) drives this and
    /// observes `pipelineStage` to render the progress checklist.
    func runCreationPipeline() async {
        guard let projectType = selectedProjectType else {
            pipelineStage = .failed("Select a project category to continue.")
            return
        }

        pipelineError = nil

        // Stage 1: create project
        pipelineStage = .creating

        // Lawn-care projects are recurring contracts — flag them at
        // creation so the backend persists the recurrence defaults
        // and the project detail UI immediately surfaces per-visit /
        // monthly / annual rollups instead of a single total.
        let isLawnCare = projectType == .lawnCare

        let request = ProjectCreationRequest(
            title: generatedTitle,
            projectType: projectType,
            clientId: nil,
            description: resolvedPrompt.isEmpty ? nil : resolvedPrompt,
            budgetMin: budgetMin,
            budgetMax: budgetMax,
            qualityTier: qualityTier,
            squareFootage: squareFootage,
            dimensions: composedDimensions,
            language: detectedLanguage == "Spanish" ? "es" : "en",
            isRecurring: isLawnCare ? true : nil,
            recurrenceFrequency: isLawnCare ? "weekly" : nil,
            visitsPerMonth: nil,
            contractMonths: nil,
            recurrenceStartDate: nil
        )

        let project: Project
        do {
            project = try await projectService.createProject(request: request)
            createdProject = project
        } catch {
            pipelineStage = .failed(error.localizedDescription)
            pipelineError = error.localizedDescription
            return
        }

        // Stage 1.5: persist the captured lawn polygon for lawn-care
        // projects so the backend stores `lawn_area_sq_ft` +
        // `property_latitude/longitude` on the project. Failure here
        // is non-fatal: the area can be re-measured from the project
        // detail's Property Scouting card without losing the project.
        if isLawnCare, hasValidLawnPolygon {
            do {
                _ = try await mapsService.measureLawn(
                    polygon: lawnMeasurementVM.vertices,
                    projectId: project.id
                )
            } catch {
                // Surface to logs only — the project itself is created.
            }
        }

        // Stage 2: upload photos. Photo upload failures are *not* fatal
        // — the project exists and the user can re-upload from detail.
        pipelineStage = .uploadingPhotos
        await uploadPhotos(projectId: project.id)

        // Stage 3: kick off generation
        pipelineStage = .startingGeneration
        let generation: AIGeneration
        do {
            generation = try await generationService.startGeneration(
                projectId: project.id,
                prompt: resolvedPrompt,
                materials: nil
            )
            pendingGeneration = generation
        } catch {
            // Generation failed to start. Surface the error but treat
            // the project as created — the user can retry from detail.
            pipelineStage = .failed(error.localizedDescription)
            pipelineError = error.localizedDescription
            return
        }

        // Stage 4: poll until complete or until we hit the ceiling
        pipelineStage = .generating
        await pollGeneration(initial: generation)
    }

    private func uploadPhotos(projectId: String) async {
        for imageData in selectedImageData {
            let compressed = Self.compressImage(imageData, maxBytes: 1_000_000)
            let base64 = compressed.base64EncodedString()
            let body = AssetUploadBody(
                url: "data:image/jpeg;base64,\(base64)",
                assetType: "original"
            )
            do {
                let _: Asset = try await apiClient.request(
                    .uploadAsset(projectId: projectId, body: body)
                )
            } catch {
                // Non-critical: project was created, photo upload failed silently.
            }
        }
    }

    private func pollGeneration(initial: AIGeneration) async {
        var generation = initial
        var attempts = 0

        while attempts < maxPollAttempts {
            switch generation.status {
            case .completed:
                pendingGeneration = generation
                // Image is ready, but the backend then kicks off the
                // material/labor estimate generation as a non-critical
                // follow-up. Wait for that too so the user lands on a
                // project detail screen with both the preview AND the
                // materials list populated.
                await pollMaterials(generationId: generation.id)
                return
            case .failed:
                let message = generation.errorMessage ?? "Generation failed. You can retry from your project."
                pipelineError = message
                pipelineStage = .failed(message)
                return
            case .queued, .processing:
                break
            }

            try? await Task.sleep(nanoseconds: pollInterval)
            attempts += 1

            // Cancellation check — caller may have dismissed the wizard.
            if Task.isCancelled { return }

            do {
                generation = try await generationService.getGenerationStatus(id: generation.id)
                pendingGeneration = generation
            } catch {
                // Don't surface transient poll errors immediately —
                // network blips happen during long polls. Hold the
                // existing snapshot and try again next tick.
                continue
            }
        }

        // Timeout: surface a friendly message but treat the project as
        // created. The user can open it and the generation may still
        // complete in the background.
        pipelineError = "This is taking longer than expected. You can open your project and we'll keep working in the background."
        pipelineStage = .failed(pipelineError ?? "Generation timeout")
    }

    /// Wait for the AI material/labor suggestions to appear after image
    /// generation completes. The backend creates the image first and
    /// then fires the materials pass as a non-critical background task,
    /// so this poll typically resolves within 10–30s after the image is
    /// done. We cap the wait so a stalled materials pass can't trap the
    /// user — when the cap is hit we still call the pipeline complete
    /// and let the user open the project; materials will continue to
    /// land in the background and appear when they arrive.
    private func pollMaterials(generationId: String) async {
        pipelineStage = .generatingMaterials

        // 60s ceiling — enough time for the typical materials pass to
        // resolve, while bounded so a timeout still gives the user
        // their project promptly. Materials are non-critical to the
        // project being usable.
        let maxAttempts = 20
        var attempts = 0

        while attempts < maxAttempts {
            if Task.isCancelled { return }

            do {
                let materials: [MaterialSuggestion] = try await apiClient.request(
                    .listMaterialSuggestions(generationId: generationId)
                )
                if !materials.isEmpty {
                    pipelineStage = .completed
                    return
                }
            } catch {
                // Transient error — hold and retry next tick.
            }

            try? await Task.sleep(nanoseconds: pollInterval)
            attempts += 1
        }

        // Timeout: don't penalize the user. The image is done and the
        // project is created — open it. Materials will populate in the
        // background and the project detail view re-fetches on appear.
        pipelineStage = .completed
    }

    /// Retry just the generation portion of the pipeline. Used by the
    /// inline retry button on the loading screen — the project itself
    /// was already created, so we restart from `.startingGeneration`.
    func retryGeneration() async {
        guard let project = createdProject else {
            // Nothing to retry against — restart the full pipeline.
            await runCreationPipeline()
            return
        }

        pipelineError = nil
        pipelineStage = .startingGeneration

        do {
            let generation = try await generationService.startGeneration(
                projectId: project.id,
                prompt: resolvedPrompt,
                materials: nil
            )
            pendingGeneration = generation
            pipelineStage = .generating
            await pollGeneration(initial: generation)
        } catch {
            pipelineError = error.localizedDescription
            pipelineStage = .failed(error.localizedDescription)
        }
    }

    // MARK: - Image Compression

    private static func compressImage(_ data: Data, maxBytes: Int) -> Data {
        guard let uiImage = UIImage(data: data) else { return data }
        var quality: CGFloat = 0.8
        while quality > 0.1 {
            if let compressed = uiImage.jpegData(compressionQuality: quality),
               compressed.count <= maxBytes
            {
                return compressed
            }
            quality -= 0.1
        }
        return uiImage.jpegData(compressionQuality: 0.1) ?? data
    }
}

// MARK: - Pipeline Stage

/// Stages of the post-create pipeline. Drives the loading-screen UI.
enum CreationPipelineStage: Sendable, Equatable {
    case idle
    case creating
    case uploadingPhotos
    case startingGeneration
    case generating
    case generatingMaterials
    case completed
    case failed(String)

    var rank: Int {
        switch self {
        case .idle: return 0
        case .creating: return 1
        case .uploadingPhotos: return 2
        case .startingGeneration: return 3
        case .generating: return 4
        case .generatingMaterials: return 5
        case .completed: return 6
        case .failed: return -1
        }
    }
}

// MARK: - Asset Upload Body

private struct AssetUploadBody: Encodable, Sendable {
    let url: String
    let assetType: String

    enum CodingKeys: String, CodingKey {
        case url
        case assetType = "asset_type"
    }
}
