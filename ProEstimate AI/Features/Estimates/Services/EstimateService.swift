import Foundation

// MARK: - Protocol

protocol EstimateServiceProtocol: Sendable {
    func listEstimates() async throws -> [EstimateSummary]
    func listByProject(projectId: String) async throws -> [Estimate]
    func getEstimate(id: String) async throws -> Estimate
    func getLineItems(estimateId: String) async throws -> [EstimateLineItem]
    func createEstimate(_ estimate: Estimate) async throws -> Estimate
    func updateEstimate(_ estimate: Estimate) async throws -> Estimate
    func deleteEstimate(id: String) async throws
    func saveLineItems(_ items: [EstimateLineItem], estimateId: String) async throws -> [EstimateLineItem]
}

// MARK: - Mock Implementation

final class MockEstimateService: EstimateServiceProtocol {
    private let simulatedDelay: UInt64 = 500_000_000 // 0.5s

    func listEstimates() async throws -> [EstimateSummary] {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return Self.sampleSummaries
    }

    func listByProject(projectId: String) async throws -> [Estimate] {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return Self.sampleEstimates.filter { $0.projectId == projectId }
    }

    func getEstimate(id: String) async throws -> Estimate {
        try await Task.sleep(nanoseconds: simulatedDelay)
        guard let estimate = Self.sampleEstimates.first(where: { $0.id == id }) else {
            throw EstimateServiceError.notFound
        }
        return estimate
    }

    func getLineItems(estimateId: String) async throws -> [EstimateLineItem] {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return Self.sampleLineItems.filter { $0.estimateId == estimateId }
    }

    func createEstimate(_ estimate: Estimate) async throws -> Estimate {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return estimate
    }

    func updateEstimate(_ estimate: Estimate) async throws -> Estimate {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return estimate
    }

    func deleteEstimate(id: String) async throws {
        try await Task.sleep(nanoseconds: simulatedDelay)
    }

    func saveLineItems(_ items: [EstimateLineItem], estimateId: String) async throws -> [EstimateLineItem] {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return items
    }
}

// MARK: - Errors

enum EstimateServiceError: LocalizedError {
    case notFound
    case saveFailed
    case deleteFailed

    var errorDescription: String? {
        switch self {
        case .notFound: "Estimate not found."
        case .saveFailed: "Failed to save estimate. Please try again."
        case .deleteFailed: "Failed to delete estimate. Please try again."
        }
    }
}

// MARK: - Sample Data

extension MockEstimateService {
    static let sampleEstimates: [Estimate] = [
        Estimate(
            id: "e-001",
            projectId: "p-001",
            companyId: "c-001",
            estimateNumber: "EST-1001",
            version: 1,
            status: .draft,
            title: nil,
            pricingProfileId: nil,
            createdByUserId: nil,
            subtotalMaterials: 12500,
            subtotalLabor: 8000,
            subtotalOther: 500,
            taxAmount: 1732.50,
            discountAmount: 0,
            totalAmount: 22732.50,
            contingencyAmount: nil,
            assumptions: nil,
            exclusions: nil,
            notes: "Price valid for 30 days.",
            validUntil: Calendar.current.date(byAdding: .day, value: 30, to: Date()),
            createdAt: Calendar.current.date(byAdding: .day, value: -3, to: Date())!,
            updatedAt: Calendar.current.date(byAdding: .hour, value: -2, to: Date())!
        ),
        Estimate(
            id: "e-002",
            projectId: "p-002",
            companyId: "c-001",
            estimateNumber: "EST-1002",
            version: 1,
            status: .sent,
            title: nil,
            pricingProfileId: nil,
            createdByUserId: nil,
            subtotalMaterials: 8750,
            subtotalLabor: 5200,
            subtotalOther: 350,
            taxAmount: 1179.75,
            discountAmount: 500,
            totalAmount: 14979.75,
            contingencyAmount: nil,
            assumptions: nil,
            exclusions: nil,
            notes: "Bathroom remodel — master bath.",
            validUntil: Calendar.current.date(byAdding: .day, value: 14, to: Date()),
            createdAt: Calendar.current.date(byAdding: .day, value: -7, to: Date())!,
            updatedAt: Calendar.current.date(byAdding: .day, value: -5, to: Date())!
        ),
        Estimate(
            id: "e-003",
            projectId: "p-003",
            companyId: "c-001",
            estimateNumber: "EST-1003",
            version: 2,
            status: .approved,
            title: nil,
            pricingProfileId: nil,
            createdByUserId: nil,
            subtotalMaterials: 24000,
            subtotalLabor: 16000,
            subtotalOther: 1200,
            taxAmount: 3399,
            discountAmount: 1000,
            totalAmount: 43599,
            contingencyAmount: nil,
            assumptions: nil,
            exclusions: nil,
            notes: "Full floor replacement, approved by homeowner.",
            validUntil: Calendar.current.date(byAdding: .day, value: 60, to: Date()),
            createdAt: Calendar.current.date(byAdding: .day, value: -14, to: Date())!,
            updatedAt: Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        ),
    ]

    static let sampleLineItems: [EstimateLineItem] = [
        // Materials for e-001
        EstimateLineItem(
            id: "eli-001",
            estimateId: "e-001",
            parentLineItemId: nil,
            sourceMaterialSuggestionId: nil,
            category: .materials,
            itemType: "per_unit",
            name: "Quartz Countertop – Calacatta",
            description: "Premium quartz slab, fabrication included",
            quantity: 45,
            unit: "sq ft",
            unitCost: 75,
            markupPercent: 20,
            taxRate: 8.25,
            lineTotal: 4387.50,
            sortOrder: 0
        ),
        EstimateLineItem(
            id: "eli-002",
            estimateId: "e-001",
            parentLineItemId: nil,
            sourceMaterialSuggestionId: nil,
            category: .materials,
            itemType: "per_unit",
            name: "Shaker Cabinets – White",
            description: "Soft-close hinges, dovetail drawers",
            quantity: 14,
            unit: "each",
            unitCost: 450,
            markupPercent: 20,
            taxRate: 8.25,
            lineTotal: 8164.35,
            sortOrder: 1
        ),
        // Labor for e-001
        EstimateLineItem(
            id: "eli-003",
            estimateId: "e-001",
            parentLineItemId: nil,
            sourceMaterialSuggestionId: nil,
            category: .labor,
            itemType: "per_unit",
            name: "Demolition & Removal",
            description: "Remove existing cabinets, counters, flooring",
            quantity: 16,
            unit: "hour",
            unitCost: 65,
            markupPercent: 15,
            taxRate: 0,
            lineTotal: 1196,
            sortOrder: 0
        ),
        EstimateLineItem(
            id: "eli-004",
            estimateId: "e-001",
            parentLineItemId: nil,
            sourceMaterialSuggestionId: nil,
            category: .labor,
            itemType: "per_unit",
            name: "Cabinet Installation",
            description: "Install 14 cabinets, level and secure",
            quantity: 24,
            unit: "hour",
            unitCost: 75,
            markupPercent: 15,
            taxRate: 0,
            lineTotal: 2070,
            sortOrder: 1
        ),
        EstimateLineItem(
            id: "eli-005",
            estimateId: "e-001",
            parentLineItemId: nil,
            sourceMaterialSuggestionId: nil,
            category: .labor,
            itemType: "per_unit",
            name: "Countertop Installation",
            description: "Template, fabrication, and installation",
            quantity: 1,
            unit: "lot",
            unitCost: 1800,
            markupPercent: 15,
            taxRate: 0,
            lineTotal: 2070,
            sortOrder: 2
        ),
        // Other for e-001
        EstimateLineItem(
            id: "eli-006",
            estimateId: "e-001",
            parentLineItemId: nil,
            sourceMaterialSuggestionId: nil,
            category: .other,
            itemType: "per_unit",
            name: "Dumpster Rental",
            description: "10-yard dumpster, 7-day rental",
            quantity: 1,
            unit: "each",
            unitCost: 450,
            markupPercent: 10,
            taxRate: 8.25,
            lineTotal: 535.13,
            sortOrder: 0
        ),
        // Materials for e-002
        EstimateLineItem(
            id: "eli-007",
            estimateId: "e-002",
            parentLineItemId: nil,
            sourceMaterialSuggestionId: nil,
            category: .materials,
            itemType: "per_unit",
            name: "Porcelain Floor Tile – Marble Look",
            description: "24x24 rectified porcelain",
            quantity: 85,
            unit: "sq ft",
            unitCost: 8.50,
            markupPercent: 25,
            taxRate: 8.25,
            lineTotal: 977.32,
            sortOrder: 0
        ),
        EstimateLineItem(
            id: "eli-008",
            estimateId: "e-002",
            parentLineItemId: nil,
            sourceMaterialSuggestionId: nil,
            category: .materials,
            itemType: "per_unit",
            name: "Walk-in Shower Kit",
            description: "Glass door, pan, fixtures",
            quantity: 1,
            unit: "lot",
            unitCost: 3200,
            markupPercent: 20,
            taxRate: 8.25,
            lineTotal: 4158,
            sortOrder: 1
        ),
        EstimateLineItem(
            id: "eli-009",
            estimateId: "e-002",
            parentLineItemId: nil,
            sourceMaterialSuggestionId: nil,
            category: .labor,
            itemType: "per_unit",
            name: "Tile Installation",
            description: "Floor and shower tile, including waterproofing",
            quantity: 32,
            unit: "hour",
            unitCost: 70,
            markupPercent: 15,
            taxRate: 0,
            lineTotal: 2576,
            sortOrder: 0
        ),
    ]

    static let sampleSummaries: [EstimateSummary] = [
        EstimateSummary(
            estimate: sampleEstimates[0],
            projectTitle: "Kitchen Remodel – Mitchell Residence"
        ),
        EstimateSummary(
            estimate: sampleEstimates[1],
            projectTitle: "Master Bath – Johnson Home"
        ),
        EstimateSummary(
            estimate: sampleEstimates[2],
            projectTitle: "Full Flooring – Garcia Property"
        ),
    ]
}
