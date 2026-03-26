import Foundation

/// Represents a cost estimate for a project.
/// Estimates are versioned — each revision creates a new version while
/// preserving the original. The estimate is the core financial document
/// that feeds into proposals and invoices.
struct Estimate: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let projectId: String
    let companyId: String
    let estimateNumber: String
    let version: Int
    let status: Status
    let subtotalMaterials: Decimal
    let subtotalLabor: Decimal
    let subtotalOther: Decimal
    let taxAmount: Decimal
    let discountAmount: Decimal
    let totalAmount: Decimal
    let notes: String?
    let validUntil: Date?
    let createdAt: Date
    let updatedAt: Date

    // MARK: - Nested Enums

    /// Tracks the estimate through its approval lifecycle.
    enum Status: String, Codable, CaseIterable, Sendable {
        case draft
        case sent
        case approved
        case declined
        case expired
    }

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case companyId = "company_id"
        case estimateNumber = "estimate_number"
        case version
        case status
        case subtotalMaterials = "subtotal_materials"
        case subtotalLabor = "subtotal_labor"
        case subtotalOther = "subtotal_other"
        case taxAmount = "tax_amount"
        case discountAmount = "discount_amount"
        case totalAmount = "total_amount"
        case notes
        case validUntil = "valid_until"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Convenience

extension Estimate {
    /// Pre-tax subtotal across all categories.
    var subtotal: Decimal {
        subtotalMaterials + subtotalLabor + subtotalOther
    }

    /// Whether the estimate is still editable.
    var isEditable: Bool {
        status == .draft
    }

    /// Whether the estimate has expired past its valid-until date.
    var isExpired: Bool {
        guard let validUntil else { return false }
        return validUntil < Date()
    }
}

// MARK: - Sample Data

extension Estimate {
    static let sample = Estimate(
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
        createdAt: Date(),
        updatedAt: Date()
    )
}
