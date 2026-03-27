import Foundation
import PhotosUI
import SwiftUI

/// View model for the streamlined quick AI generation flow.
/// Handles photo selection, project creation, generation, and polling.
@Observable
final class QuickGenerateViewModel {
    // MARK: - Phase

    enum Phase {
        case input
        case generating
        case result
        case error
    }

    var phase: Phase = .input

    // MARK: - Input State

    var photosPickerItem: PhotosPickerItem?
    var selectedImageData: Data?
    var selectedProjectType: Project.ProjectType? = .kitchen
    var prompt: String = ""

    // MARK: - Generation State

    var isSubmitting: Bool = false
    var currentStage: Int = 0
    var completedGeneration: AIGeneration?
    var createdProjectId: String?
    var errorMessage: String?

    private var progressTimer: Timer?

    // MARK: - Dependencies

    private let projectService: ProjectServiceProtocol
    private let generationService: GenerationServiceProtocol

    init(
        projectService: ProjectServiceProtocol = LiveProjectService(),
        generationService: GenerationServiceProtocol = LiveGenerationService()
    ) {
        self.projectService = projectService
        self.generationService = generationService
    }

    // MARK: - Computed

    var canGenerate: Bool {
        selectedImageData != nil &&
        selectedProjectType != nil &&
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Photo Loading

    func loadSelectedPhoto() async {
        guard let item = photosPickerItem else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            selectedImageData = data
        }
    }

    func clearPhoto() {
        photosPickerItem = nil
        selectedImageData = nil
    }

    // MARK: - Generation Flow

    func generate() async {
        guard canGenerate,
              let projectType = selectedProjectType,
              let imageData = selectedImageData else { return }

        isSubmitting = true
        phase = .generating
        currentStage = 0
        startProgressSimulation()

        do {
            // 1. Create a project behind the scenes
            let typeName = titleForType(projectType)
            let request = ProjectCreationRequest(
                title: typeName,
                projectType: projectType,
                clientId: nil,
                description: prompt,
                budgetMin: nil,
                budgetMax: nil,
                qualityTier: .standard,
                squareFootage: nil,
                dimensions: nil,
                language: "en"
            )
            let project = try await projectService.createProject(request: request)
            createdProjectId = project.id

            // 2. Upload photo as asset (compress to max ~1MB JPEG for fast upload)
            let compressedData = Self.compressImage(imageData, maxBytes: 1_000_000)
            let base64 = compressedData.base64EncodedString()
            let uploadBody = AssetUploadRequest(
                url: "data:image/jpeg;base64,\(base64)",
                assetType: "original"
            )
            let _: Asset = try await APIClient.shared.request(
                .uploadAsset(projectId: project.id, body: uploadBody)
            )

            // 3. Start generation
            let generation = try await generationService.startGeneration(
                projectId: project.id,
                prompt: prompt
            )

            // 4. Poll for completion
            var completed = generation
            for _ in 0..<30 {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                completed = try await generationService.getGenerationStatus(id: generation.id)
                if completed.status == .completed || completed.status == .failed {
                    break
                }
            }

            stopProgressSimulation()
            isSubmitting = false

            if completed.status == .completed {
                completedGeneration = completed
                phase = .result
            } else {
                errorMessage = completed.errorMessage ?? "Image generation failed. Please try again."
                phase = .error
            }
        } catch {
            stopProgressSimulation()
            isSubmitting = false
            errorMessage = error.localizedDescription
            phase = .error
        }
    }

    func reset() {
        phase = .input
        photosPickerItem = nil
        selectedImageData = nil
        selectedProjectType = .kitchen
        prompt = ""
        completedGeneration = nil
        createdProjectId = nil
        errorMessage = nil
        currentStage = 0
    }

    // MARK: - Progress Simulation

    private func startProgressSimulation() {
        let totalStages = GenerationStage.allCases.count
        progressTimer = Timer.scheduledTimer(
            withTimeInterval: 0.8,
            repeats: true
        ) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            if self.currentStage < totalStages - 1 {
                self.currentStage += 1
            } else {
                timer.invalidate()
            }
        }
    }

    private func stopProgressSimulation() {
        progressTimer?.invalidate()
        progressTimer = nil
        currentStage = GenerationStage.allCases.count - 1
    }

    // MARK: - Helpers

    /// Compress image data to JPEG at progressively lower quality until it fits within maxBytes.
    private static func compressImage(_ data: Data, maxBytes: Int) -> Data {
        guard let uiImage = UIImage(data: data) else { return data }
        var quality: CGFloat = 0.8
        while quality > 0.1 {
            if let compressed = uiImage.jpegData(compressionQuality: quality),
               compressed.count <= maxBytes {
                return compressed
            }
            quality -= 0.1
        }
        // Last resort: lowest quality
        return uiImage.jpegData(compressionQuality: 0.1) ?? data
    }

    private func titleForType(_ type: Project.ProjectType) -> String {
        switch type {
        case .kitchen: "Kitchen Remodel"
        case .bathroom: "Bathroom Renovation"
        case .flooring: "Flooring Install"
        case .roofing: "Roof Replacement"
        case .painting: "Painting Project"
        case .siding: "Siding Replacement"
        case .roomRemodel: "Room Remodel"
        case .exterior: "Exterior Renovation"
        case .custom: "Custom Project"
        }
    }
}

// MARK: - Request Body

private struct AssetUploadRequest: Encodable, Sendable {
    let url: String
    let assetType: String

    enum CodingKeys: String, CodingKey {
        case url
        case assetType = "asset_type"
    }
}
