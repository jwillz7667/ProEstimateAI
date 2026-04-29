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

/// Steps in the project creation flow.
///
/// Standard projects walk: `type → photos → details → generating`.
/// Lawn-care projects insert a `lawnMap` step between photos and
/// details so the contractor can pin the lawn polygon on a satellite
/// map and capture an area measurement for estimation. The wizard
/// skips `.lawnMap` for any non-lawn-care project type — see
/// `ProjectCreationViewModel.nextStep` / `previousStep` for the
/// step-skipping logic and `navigableStepCount` for the progress-bar
/// length.
///
/// `generating` is a non-interactive loading state — it sits at the
/// end of the enum and is excluded from the navigable count for both
/// flows.
enum ProjectCreationStep: Int, CaseIterable, Sendable {
    case type = 0
    case photos = 1
    case lawnMap = 2
    case details = 3
    case generating = 4

    var title: String {
        switch self {
        case .type: "Category"
        case .photos: "Photos & Vision"
        case .lawnMap: "Measure Lawn"
        case .details: "Details"
        case .generating: "Generating"
        }
    }
}

// NOTE: ActivityLogEntry is defined in Core/Models/ActivityLogEntry.swift
