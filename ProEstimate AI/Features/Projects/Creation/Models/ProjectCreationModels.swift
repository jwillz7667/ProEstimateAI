import Foundation

// MARK: - Project Creation Request

/// The payload sent to the backend when creating a new project.
/// Images are uploaded separately via multipart form data; this struct
/// carries the metadata for the project creation endpoint.
struct ProjectCreationRequest: Codable, Sendable {
    let title: String
    let projectType: Project.ProjectType
    let clientId: String?
    let description: String?
    let budgetMin: Decimal?
    let budgetMax: Decimal?
    let qualityTier: Project.QualityTier
    let squareFootage: Decimal?
    let dimensions: String?
    let language: String?
    // Recurring contract terms — only sent for projects the wizard
    // configured as recurring (LAWN_CARE today). All optional so a
    // standard install bid carries the keys as null and the backend
    // takes its `is_recurring=false` default.
    let isRecurring: Bool?
    let recurrenceFrequency: String?
    let visitsPerMonth: Decimal?
    let contractMonths: Int?
    let recurrenceStartDate: Date?

    enum CodingKeys: String, CodingKey {
        case title
        case projectType = "project_type"
        case clientId = "client_id"
        case description
        case budgetMin = "budget_min"
        case budgetMax = "budget_max"
        case qualityTier = "quality_tier"
        case squareFootage = "square_footage"
        case dimensions
        case language
        case isRecurring = "is_recurring"
        case recurrenceFrequency = "recurrence_frequency"
        case visitsPerMonth = "visits_per_month"
        case contractMonths = "contract_months"
        case recurrenceStartDate = "recurrence_start_date"
    }
}

// MARK: - Project Status Filter

/// Filter options for the project list segmented control.
enum ProjectStatusFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case active
    case completed
    case archived

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all: "All"
        case .active: "Active"
        case .completed: "Completed"
        case .archived: "Archived"
        }
    }

    /// Returns which project statuses belong to this filter bucket.
    var matchingStatuses: [Project.Status] {
        switch self {
        case .all:
            return Project.Status.allCases
        case .active:
            return [
                .draft,
                .photosUploaded,
                .generating,
                .generationComplete,
                .estimateCreated,
                .proposalSent,
                .approved,
                .declined,
                .invoiced,
            ]
        case .completed:
            return [.completed]
        case .archived:
            return [.archived]
        }
    }
}

// MARK: - Creation Step

/// The six sequential steps of the project creation flow.
enum ProjectCreationStep: Int, CaseIterable, Sendable {
    case type = 0
    case client = 1
    case photos = 2
    case prompt = 3
    case details = 4
    case review = 5

    var title: String {
        switch self {
        case .type: "Type"
        case .client: "Client"
        case .photos: "Photos"
        case .prompt: "Description"
        case .details: "Details"
        case .review: "Review"
        }
    }

    var stepCount: Int {
        ProjectCreationStep.allCases.count
    }
}

// NOTE: ActivityLogEntry is defined in Core/Models/ActivityLogEntry.swift
