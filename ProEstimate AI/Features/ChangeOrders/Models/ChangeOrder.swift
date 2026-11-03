import Foundation

struct ChangeOrderComparison: Decodable, Sendable {
    let id: String
    let title: String
    let reason: String
    let currencyCode: String
    let baseEstimateNumber: String
    let baseVersion: Int
    let baseDocumentHash: String
    let baseTotal: Decimal
    let newTotal: Decimal
    let changeAmount: Decimal
    let subtotalDelta: Decimal
    let taxDelta: Decimal
    let discountDelta: Decimal
    let billingEffect: String
    enum CodingKeys: String, CodingKey {
        case id, title, reason
        case currencyCode = "currency_code"
        case baseEstimateNumber = "base_estimate_number"
        case baseVersion = "base_version"
        case baseDocumentHash = "base_document_hash"
        case baseTotal = "base_total"
        case newTotal = "new_total"
        case changeAmount = "change_amount"
        case subtotalDelta = "subtotal_delta"
        case taxDelta = "tax_delta"
        case discountDelta = "discount_delta"
        case billingEffect = "billing_effect"
    }
}
struct ChangeOrderCreditNote: Decodable, Identifiable, Sendable {
    let id: String
    let creditNumber: String
    let amount: Decimal
    let allocatedAmount: Decimal
    let currencyCode: String
    let reason: String
    let createdAt: Date
    var availableAmount: Decimal { max(0, amount - allocatedAmount) }
    enum CodingKeys: String, CodingKey {
        case id, amount, reason
        case creditNumber = "credit_number"
        case allocatedAmount = "allocated_amount"
        case currencyCode = "currency_code"
        case createdAt = "created_at"
    }
}
struct ChangeOrder: Decodable, Identifiable, Sendable {
    let id: String
    let projectId: String
    let baseEstimateId: String
    let estimateId: String
    let proposalId: String
    let rootInvoiceId: String?
    let status: String
    let title: String
    let reason: String
    let comparison: ChangeOrderComparison
    let estimate: Estimate
    let invoices: [Invoice]
    let creditNote: ChangeOrderCreditNote?
    let createdAt: Date
    var canApply: Bool { status == "approved" && rootInvoiceId != nil }
    enum CodingKeys: String, CodingKey {
        case id, status, title, reason, comparison, estimate, invoices
        case projectId = "project_id"
        case baseEstimateId = "base_estimate_id"
        case estimateId = "estimate_id"
        case proposalId = "proposal_id"
        case rootInvoiceId = "root_invoice_id"
        case creditNote = "credit_note"
        case createdAt = "created_at"
    }
}
struct CreateChangeOrderRequest: Codable, Equatable, Sendable {
    let requestId: String
    let baseEstimateId: String
    let title: String
    let reason: String
    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case baseEstimateId = "base_estimate_id"
        case title, reason
    }
    static func validated(baseEstimateId: String, title: String, reason: String, requestId: UUID = UUID())
        throws -> Self
    {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseEstimateId.isEmpty, !title.isEmpty, title.utf16.count <= 200, !reason.isEmpty,
            reason.utf16.count <= 10_000
        else { throw ChangeOrderError.invalidInput }
        return Self(
            requestId: requestId.uuidString.lowercased(), baseEstimateId: baseEstimateId, title: title,
            reason: reason)
    }
}
struct ApplyChangeOrderRequest: Codable, Equatable, Sendable {
    let requestId: String
    enum CodingKeys: String, CodingKey { case requestId = "request_id" }
}
enum ChangeOrderError: LocalizedError {
    case invalidInput, invalidRecovery, invalidResponse
    var errorDescription: String? {
        switch self {
        case .invalidInput: "Add a title and explain the scope or price change before continuing."
        case .invalidRecovery:
            "The saved change order request could not be safely restored. Refresh this project before trying again."
        case .invalidResponse: "The saved change order did not match this request. Refresh before continuing."
        }
    }
}

protocol ChangeOrderServing: Sendable {
    func list(projectId: String) async throws -> [ChangeOrder]
    func get(id: String) async throws -> ChangeOrder
    func create(_ request: CreateChangeOrderRequest) async throws -> ChangeOrder
    func apply(id: String, request: ApplyChangeOrderRequest) async throws -> ChangeOrder
}
