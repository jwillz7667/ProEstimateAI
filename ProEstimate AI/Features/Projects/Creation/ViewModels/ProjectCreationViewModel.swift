import Foundation
import PhotosUI
import SwiftUI

/// Manages the full multi-step project creation flow.
/// Tracks the current step, validates per-step input, collects all form
/// data, and submits the creation request to the backend.
@Observable
final class ProjectCreationViewModel {
    // MARK: - Step Navigation

    var currentStep: Int = 0
    var totalSteps: Int { ProjectCreationStep.allCases.count }

    var currentStepEnum: ProjectCreationStep {
        ProjectCreationStep(rawValue: currentStep) ?? .type
    }

    // MARK: - Step 0: Project Type

    var selectedProjectType: Project.ProjectType?

    // MARK: - Step 1: Client Selection

    var selectedClient: Client?
    var clientSearchText: String = ""
    var availableClients: [Client] = MockProjectService.sampleClients

    var filteredClients: [Client] {
        guard !clientSearchText.isEmpty else { return availableClients }
        let query = clientSearchText.lowercased()
        return availableClients.filter { $0.name.lowercased().contains(query) }
    }

    // MARK: - Step 2: Image Upload

    var selectedPhotosItems: [PhotosPickerItem] = []
    var selectedImageData: [Data] = []
    var isLoadingImages: Bool = false

    // MARK: - Step 3: Prompt / Description

    var prompt: String = ""
    let maxPromptLength: Int = 1000

    var promptCharacterCount: Int { prompt.count }

    var detectedLanguage: String {
        // Simple heuristic: if prompt contains common Spanish words, hint Spanish
        let spanishIndicators = ["cocina", "bano", "piso", "techo", "pintura", "habitacion", "remodelacion"]
        let lowered = prompt.lowercased()
        for word in spanishIndicators {
            if lowered.contains(word) { return "Spanish" }
        }
        return "English"
    }

    // MARK: - Step 4: Details

    var budgetMinText: String = ""
    var budgetMaxText: String = ""
    var qualityTier: Project.QualityTier = .standard
    var squareFootageText: String = ""
    var dimensions: String = ""

    var budgetMin: Decimal? {
        Decimal(string: budgetMinText)
    }

    var budgetMax: Decimal? {
        Decimal(string: budgetMaxText)
    }

    var squareFootage: Decimal? {
        Decimal(string: squareFootageText)
    }

    // MARK: - Submission State

    var isSubmitting: Bool = false
    var submissionError: String?
    var createdProject: Project?

    // MARK: - Dependencies

    private let projectService: ProjectServiceProtocol

    // MARK: - Init

    init(projectService: ProjectServiceProtocol = MockProjectService()) {
        self.projectService = projectService
    }

    // MARK: - Computed Validation

    /// Whether the user can proceed from the current step.
    var canProceed: Bool {
        switch currentStepEnum {
        case .type:
            return selectedProjectType != nil
        case .client:
            // Client is optional — always allow proceeding
            return true
        case .photos:
            return !selectedImageData.isEmpty
        case .prompt:
            return !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .details:
            // Details are optional
            return true
        case .review:
            return true
        }
    }

    /// Auto-generated title based on selected type and client.
    var generatedTitle: String {
        let typeName: String = {
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
            case .custom: return "Custom Project"
            }
        }()

        if let client = selectedClient {
            let lastName = client.name.split(separator: " ").last.map(String.init) ?? client.name
            return "\(typeName) – \(lastName) Residence"
        }
        return typeName
    }

    // MARK: - Actions

    func nextStep() {
        guard canProceed, currentStep < totalSteps - 1 else { return }
        currentStep += 1
    }

    func previousStep() {
        guard currentStep > 0 else { return }
        currentStep -= 1
    }

    func loadImages() async {
        isLoadingImages = true
        var loadedData: [Data] = []

        for item in selectedPhotosItems {
            if let data = try? await item.loadTransferable(type: Data.self) {
                loadedData.append(data)
            }
        }

        selectedImageData = loadedData
        isLoadingImages = false
    }

    func removeImage(at index: Int) {
        guard index < selectedImageData.count else { return }
        selectedImageData.remove(at: index)
        if index < selectedPhotosItems.count {
            selectedPhotosItems.remove(at: index)
        }
    }

    func createProject() async {
        guard let projectType = selectedProjectType else { return }

        isSubmitting = true
        submissionError = nil

        let request = ProjectCreationRequest(
            title: generatedTitle,
            projectType: projectType,
            clientId: selectedClient?.id,
            description: prompt.isEmpty ? nil : prompt,
            budgetMin: budgetMin,
            budgetMax: budgetMax,
            qualityTier: qualityTier,
            squareFootage: squareFootage,
            dimensions: dimensions.isEmpty ? nil : dimensions,
            language: detectedLanguage == "Spanish" ? "es" : "en"
        )

        do {
            let project = try await projectService.createProject(request: request)
            createdProject = project
        } catch {
            submissionError = error.localizedDescription
        }

        isSubmitting = false
    }
}
