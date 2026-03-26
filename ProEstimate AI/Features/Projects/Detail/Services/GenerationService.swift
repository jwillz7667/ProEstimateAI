import Foundation

// MARK: - Protocol

/// Contract for triggering and polling AI generation jobs.
/// The mock implementation simulates asynchronous progress through
/// the five generation stages.
protocol GenerationServiceProtocol: Sendable {
    func startGeneration(projectId: String, prompt: String) async throws -> AIGeneration
    func getGenerationStatus(id: String) async throws -> AIGeneration
    func listGenerations(projectId: String) async throws -> [AIGeneration]
}

// MARK: - Mock Implementation

final class MockGenerationService: GenerationServiceProtocol {
    private let simulatedDelay: UInt64 = 600_000_000

    func startGeneration(projectId: String, prompt: String) async throws -> AIGeneration {
        try await Task.sleep(nanoseconds: simulatedDelay)

        return AIGeneration(
            id: "gen-\(UUID().uuidString.prefix(8))",
            projectId: projectId,
            prompt: prompt,
            status: .queued,
            previewURL: nil,
            thumbnailURL: nil,
            generationDurationMs: nil,
            errorMessage: nil,
            createdAt: Date()
        )
    }

    func getGenerationStatus(id: String) async throws -> AIGeneration {
        try await Task.sleep(nanoseconds: simulatedDelay)

        // Mock: always return completed status
        return AIGeneration(
            id: id,
            projectId: "p-001",
            prompt: "Modern kitchen with white shaker cabinets and quartz countertops",
            status: .completed,
            previewURL: URL(string: "https://cdn.proestimate.ai/gen/\(id).jpg"),
            thumbnailURL: URL(string: "https://cdn.proestimate.ai/gen/\(id)-thumb.jpg"),
            generationDurationMs: 2400,
            errorMessage: nil,
            createdAt: Date()
        )
    }

    func listGenerations(projectId: String) async throws -> [AIGeneration] {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return Self.sampleGenerations.filter { $0.projectId == projectId }
    }
}

// MARK: - Generation Stage

/// Visual stages displayed to the user during AI generation.
/// These map to the internal processing pipeline on the backend.
enum GenerationStage: Int, CaseIterable, Sendable {
    case uploading = 0
    case analyzing = 1
    case generating = 2
    case enhancing = 3
    case complete = 4

    var title: String {
        switch self {
        case .uploading: "Uploading"
        case .analyzing: "Analyzing"
        case .generating: "Generating"
        case .enhancing: "Enhancing"
        case .complete: "Complete"
        }
    }

    var icon: String {
        switch self {
        case .uploading: "icloud.and.arrow.up"
        case .analyzing: "eye.trianglebadge.exclamationmark"
        case .generating: "wand.and.stars"
        case .enhancing: "sparkles"
        case .complete: "checkmark.circle.fill"
        }
    }
}

// MARK: - Generation Progress State

/// Tracks which stage is currently active for the progress card animation.
enum StageState: Sendable {
    case pending
    case active
    case complete
}

// MARK: - Sample Data

extension MockGenerationService {
    static let sampleGenerations: [AIGeneration] = [
        AIGeneration(
            id: "gen-001",
            projectId: "p-001",
            prompt: "Modern kitchen with white shaker cabinets and quartz countertops",
            status: .completed,
            previewURL: URL(string: "https://cdn.proestimate.ai/gen/gen-001.jpg"),
            thumbnailURL: URL(string: "https://cdn.proestimate.ai/gen/gen-001-thumb.jpg"),
            generationDurationMs: 2400,
            errorMessage: nil,
            createdAt: Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        ),
        AIGeneration(
            id: "gen-002",
            projectId: "p-001",
            prompt: "Transitional kitchen with navy blue cabinets, brass hardware, and butcher block island",
            status: .completed,
            previewURL: URL(string: "https://cdn.proestimate.ai/gen/gen-002.jpg"),
            thumbnailURL: URL(string: "https://cdn.proestimate.ai/gen/gen-002-thumb.jpg"),
            generationDurationMs: 3100,
            errorMessage: nil,
            createdAt: Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        ),
        AIGeneration(
            id: "gen-003",
            projectId: "p-002",
            prompt: "Spa bathroom with walk-in shower, marble tile, and freestanding soaking tub",
            status: .completed,
            previewURL: URL(string: "https://cdn.proestimate.ai/gen/gen-003.jpg"),
            thumbnailURL: URL(string: "https://cdn.proestimate.ai/gen/gen-003-thumb.jpg"),
            generationDurationMs: 2800,
            errorMessage: nil,
            createdAt: Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        ),
    ]

    static let sampleMaterials: [MaterialSuggestion] = [
        MaterialSuggestion(
            id: "ms-001",
            generationId: "gen-001",
            projectId: "p-001",
            name: "Quartz Countertop – Calacatta",
            category: "Countertops",
            estimatedCost: 75,
            unit: "sq ft",
            quantity: 45,
            supplierName: "Home Depot",
            supplierURL: URL(string: "https://homedepot.com/p/quartz-calacatta"),
            isSelected: true,
            sortOrder: 0
        ),
        MaterialSuggestion(
            id: "ms-002",
            generationId: "gen-001",
            projectId: "p-001",
            name: "White Shaker Cabinets – 10x10 Set",
            category: "Cabinets",
            estimatedCost: 3200,
            unit: "set",
            quantity: 1,
            supplierName: "IKEA",
            supplierURL: URL(string: "https://ikea.com/cabinets"),
            isSelected: true,
            sortOrder: 1
        ),
        MaterialSuggestion(
            id: "ms-003",
            generationId: "gen-001",
            projectId: "p-001",
            name: "Subway Tile Backsplash – White 3x6",
            category: "Tile",
            estimatedCost: 8,
            unit: "sq ft",
            quantity: 30,
            supplierName: "Floor & Decor",
            supplierURL: nil,
            isSelected: false,
            sortOrder: 2
        ),
        MaterialSuggestion(
            id: "ms-004",
            generationId: "gen-001",
            projectId: "p-001",
            name: "Pendant Light – Brushed Brass",
            category: "Lighting",
            estimatedCost: 189,
            unit: "each",
            quantity: 3,
            supplierName: "Lowe's",
            supplierURL: URL(string: "https://lowes.com/pendant-brass"),
            isSelected: true,
            sortOrder: 3
        ),
        MaterialSuggestion(
            id: "ms-005",
            generationId: "gen-001",
            projectId: "p-001",
            name: "Engineered Hardwood – Natural Oak",
            category: "Flooring",
            estimatedCost: 6.50,
            unit: "sq ft",
            quantity: 250,
            supplierName: "Lumber Liquidators",
            supplierURL: nil,
            isSelected: false,
            sortOrder: 4
        ),
    ]

    static let sampleEstimates: [Estimate] = [
        Estimate(
            id: "e-001",
            projectId: "p-001",
            companyId: "c-001",
            estimateNumber: "EST-1001",
            version: 1,
            status: .draft,
            subtotalMaterials: 12500,
            subtotalLabor: 8000,
            subtotalOther: 500,
            taxAmount: 1732.50,
            discountAmount: 0,
            totalAmount: 22732.50,
            notes: "Price valid for 30 days.",
            validUntil: Calendar.current.date(byAdding: .day, value: 30, to: Date()),
            createdAt: Calendar.current.date(byAdding: .day, value: -3, to: Date())!,
            updatedAt: Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        ),
    ]
}
