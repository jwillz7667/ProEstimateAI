import Foundation

enum EstimateCreationMethod: String, CaseIterable, Identifiable, Sendable {
    case manual
    case ai

    var id: String { rawValue }
    var title: String { self == .manual ? "Manual" : "AI estimate · Pro" }
}

struct EstimateCreationDraft: Equatable, Sendable {
    var title = ""
    var projectType: Project.ProjectType = .handyman
    var scope = ""
    var method: EstimateCreationMethod = .manual

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedScope: String { scope.trimmingCharacters(in: .whitespacesAndNewlines) }

    var validationMessage: String? {
        if trimmedTitle.isEmpty { return "Give this estimate a name." }
        if trimmedTitle.utf16.count > 255 { return "Keep the estimate name to 255 characters or fewer." }
        if trimmedScope.utf16.count > 5000 { return "Keep the scope to 5,000 characters or fewer." }
        if method == .ai && trimmedScope.count < 20 {
            return "Describe the work in a little more detail so AI can build a useful draft."
        }
        return nil
    }

    func projectRequest(clientId: String?, language: String) -> ProjectCreationRequest {
        ProjectCreationRequest(
            title: trimmedTitle, projectType: projectType, clientId: clientId,
            description: trimmedScope.isEmpty ? nil : trimmedScope,
            budgetMin: nil, budgetMax: nil, qualityTier: nil,
            squareFootage: nil, dimensions: nil, language: language,
            aiPreviewEnabled: false, isRecurring: nil, recurrenceFrequency: nil,
            visitsPerMonth: nil, contractMonths: nil, recurrenceStartDate: nil
        )
    }
}

/// A transport failure after a POST can follow a committed write. Services
/// classify known rejections so creation retries never duplicate uncertain work.
protocol EstimateCreationFailureClassifying: Error {
    var creationWriteIsUnconfirmed: Bool { get }
}

protocol EstimateCreationServing: Sendable {
    func listClients() async throws -> [Client]
    func createProject(request: ProjectCreationRequest) async throws -> Project
    func createEstimate(projectId: String, title: String, method: EstimateCreationMethod) async throws -> Estimate
    func listEstimates(projectId: String) async throws -> [Estimate]
}
