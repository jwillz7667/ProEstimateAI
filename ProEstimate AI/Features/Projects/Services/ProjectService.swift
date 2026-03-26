import Foundation

// MARK: - Protocol

/// Contract for fetching and mutating project data.
/// The mock implementation supplies hard-coded sample projects;
/// the real implementation will call the backend REST API.
protocol ProjectServiceProtocol: Sendable {
    func listProjects() async throws -> [Project]
    func getProject(id: String) async throws -> Project
    func createProject(request: ProjectCreationRequest) async throws -> Project
    func updateProject(id: String, request: ProjectCreationRequest) async throws -> Project
    func deleteProject(id: String) async throws
}

// MARK: - Mock Implementation

final class MockProjectService: ProjectServiceProtocol {
    /// Simulated network delay in nanoseconds (0.8 seconds).
    private let simulatedDelay: UInt64 = 800_000_000

    func listProjects() async throws -> [Project] {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return Self.sampleProjects
    }

    func getProject(id: String) async throws -> Project {
        try await Task.sleep(nanoseconds: simulatedDelay)

        guard let project = Self.sampleProjects.first(where: { $0.id == id }) else {
            throw ProjectServiceError.notFound
        }
        return project
    }

    func createProject(request: ProjectCreationRequest) async throws -> Project {
        try await Task.sleep(nanoseconds: simulatedDelay)

        let now = Date()
        return Project(
            id: "p-\(UUID().uuidString.prefix(8))",
            companyId: "c-001",
            clientId: request.clientId,
            title: request.title,
            description: request.description,
            projectType: request.projectType,
            status: .draft,
            budgetMin: request.budgetMin,
            budgetMax: request.budgetMax,
            qualityTier: request.qualityTier,
            squareFootage: request.squareFootage,
            dimensions: request.dimensions,
            language: request.language,
            createdAt: now,
            updatedAt: now
        )
    }

    func updateProject(id: String, request: ProjectCreationRequest) async throws -> Project {
        try await Task.sleep(nanoseconds: simulatedDelay)

        guard Self.sampleProjects.contains(where: { $0.id == id }) else {
            throw ProjectServiceError.notFound
        }

        return Project(
            id: id,
            companyId: "c-001",
            clientId: request.clientId,
            title: request.title,
            description: request.description,
            projectType: request.projectType,
            status: .draft,
            budgetMin: request.budgetMin,
            budgetMax: request.budgetMax,
            qualityTier: request.qualityTier,
            squareFootage: request.squareFootage,
            dimensions: request.dimensions,
            language: request.language,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func deleteProject(id: String) async throws {
        try await Task.sleep(nanoseconds: simulatedDelay)

        guard Self.sampleProjects.contains(where: { $0.id == id }) else {
            throw ProjectServiceError.notFound
        }
        // Mock: no-op on success
    }
}

// MARK: - Sample Projects

extension MockProjectService {
    static let sampleProjects: [Project] = [
        Project(
            id: "p-001",
            companyId: "c-001",
            clientId: "cl-001",
            title: "Kitchen Remodel – Mitchell Residence",
            description: "Full kitchen remodel with new cabinets, countertops, and island.",
            projectType: .kitchen,
            status: .generationComplete,
            budgetMin: 15000,
            budgetMax: 35000,
            qualityTier: .premium,
            squareFootage: 250,
            dimensions: "20x12.5",
            language: "en",
            createdAt: Calendar.current.date(byAdding: .day, value: -10, to: Date())!,
            updatedAt: Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        ),
        Project(
            id: "p-002",
            companyId: "c-001",
            clientId: "cl-002",
            title: "Master Bathroom Renovation",
            description: "Walk-in shower conversion, double vanity, heated floors.",
            projectType: .bathroom,
            status: .estimateCreated,
            budgetMin: 8000,
            budgetMax: 18000,
            qualityTier: .luxury,
            squareFootage: 120,
            dimensions: "12x10",
            language: "en",
            createdAt: Calendar.current.date(byAdding: .day, value: -7, to: Date())!,
            updatedAt: Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        ),
        Project(
            id: "p-003",
            companyId: "c-001",
            clientId: "cl-003",
            title: "Exterior Painting – Davis Home",
            description: "Full exterior repaint, two-story colonial, trim and siding.",
            projectType: .painting,
            status: .completed,
            budgetMin: 4000,
            budgetMax: 7000,
            qualityTier: .standard,
            squareFootage: 2800,
            dimensions: nil,
            language: "en",
            createdAt: Calendar.current.date(byAdding: .day, value: -30, to: Date())!,
            updatedAt: Calendar.current.date(byAdding: .day, value: -5, to: Date())!
        ),
        Project(
            id: "p-004",
            companyId: "c-001",
            clientId: nil,
            title: "Hardwood Flooring Install",
            description: "Engineered hardwood throughout first floor, remove existing carpet.",
            projectType: .flooring,
            status: .draft,
            budgetMin: 6000,
            budgetMax: 12000,
            qualityTier: .premium,
            squareFootage: 1100,
            dimensions: nil,
            language: "en",
            createdAt: Calendar.current.date(byAdding: .day, value: -2, to: Date())!,
            updatedAt: Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        ),
        Project(
            id: "p-005",
            companyId: "c-001",
            clientId: "cl-001",
            title: "Roof Replacement – Mitchell Residence",
            description: "Full tear-off and replace with architectural shingles.",
            projectType: .roofing,
            status: .archived,
            budgetMin: 10000,
            budgetMax: 20000,
            qualityTier: .standard,
            squareFootage: 2200,
            dimensions: nil,
            language: "en",
            createdAt: Calendar.current.date(byAdding: .day, value: -60, to: Date())!,
            updatedAt: Calendar.current.date(byAdding: .day, value: -45, to: Date())!
        ),
    ]
}

// MARK: - Sample Clients for Creation Flow

extension MockProjectService {
    /// Convenience list of sample clients available during project creation.
    static let sampleClients: [Client] = [
        Client(
            id: "cl-001",
            companyId: "c-001",
            name: "Sarah Mitchell",
            email: "sarah@example.com",
            phone: "512-555-0300",
            address: "4200 Elm Dr",
            city: "Austin",
            state: "TX",
            zip: "78704",
            notes: nil,
            createdAt: Date(),
            updatedAt: Date()
        ),
        Client(
            id: "cl-002",
            companyId: "c-001",
            name: "James Rodriguez",
            email: "james.r@example.com",
            phone: "512-555-0401",
            address: "1800 Oak Hill Blvd",
            city: "Austin",
            state: "TX",
            zip: "78735",
            notes: nil,
            createdAt: Date(),
            updatedAt: Date()
        ),
        Client(
            id: "cl-003",
            companyId: "c-001",
            name: "Linda Davis",
            email: "linda.davis@example.com",
            phone: "512-555-0502",
            address: "900 Pecan St",
            city: "Round Rock",
            state: "TX",
            zip: "78664",
            notes: nil,
            createdAt: Date(),
            updatedAt: Date()
        ),
        Client(
            id: "cl-004",
            companyId: "c-001",
            name: "Carlos Hernandez",
            email: "carlos.h@example.com",
            phone: "512-555-0603",
            address: "3100 Lamar Ave",
            city: "Austin",
            state: "TX",
            zip: "78705",
            notes: nil,
            createdAt: Date(),
            updatedAt: Date()
        ),
    ]
}

// MARK: - Errors

enum ProjectServiceError: LocalizedError {
    case notFound
    case invalidData
    case networkError
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            "Project not found."
        case .invalidData:
            "Invalid project data."
        case .networkError:
            "Unable to connect. Please check your internet connection."
        case .serverError(let message):
            message
        }
    }
}
