import Foundation

// MARK: - Protocol

/// Abstracts invoice CRUD + line-item seeding + send + payment reconciliation —
/// the final step of the get-paid loop.
protocol InvoiceServiceProtocol: Sendable {
    func listByProject(projectId: String) async throws -> [Invoice]
    func getInvoice(id: String) async throws -> Invoice
    func getLineItems(invoiceId: String) async throws -> [InvoiceLineItem]
    /// Create an invoice from an approved estimate, seeding its line items from
    /// the estimate's line items, then re-fetching so the returned invoice
    /// carries server-recomputed totals.
    func createFromEstimate(estimate: Estimate, lineItems: [EstimateLineItem], clientId: String) async throws -> Invoice
    /// Send the invoice to the client (status → sent, emails the client).
    func sendInvoice(id: String) async throws -> Invoice
    /// Mark the invoice fully paid for the given amount (typically the total).
    func markPaid(id: String, amount: Decimal) async throws -> Invoice
    func deleteInvoice(id: String) async throws
}

// MARK: - Request Bodies

/// Create-invoice body. `project_id` + `client_id` are required; `estimate_id`
/// links the source estimate. Optional fields are omitted on create.
struct CreateInvoiceBody: Encodable, Sendable {
    let projectId: String
    let clientId: String
    let estimateId: String?

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case clientId = "client_id"
        case estimateId = "estimate_id"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(projectId, forKey: .projectId)
        try c.encode(clientId, forKey: .clientId)
        try c.encodeIfPresent(estimateId, forKey: .estimateId)
    }
}

/// Create-invoice-line-item body. Maps a single estimate line item onto an
/// invoice line. Each estimate line is billed as a single rolled-up unit
/// (`quantity = 1`, `unit_cost = estimate lineTotal`) so the backend's
/// `line_total = quantity * unit_cost` reproduces the approved amount to the
/// cent with zero division/rounding drift. The original quantity/unit detail
/// is preserved in the description for readability.
struct CreateInvoiceLineItemBody: Encodable, Sendable {
    let name: String
    let description: String?
    let quantity: Decimal
    let unit: String
    let unitCost: Decimal
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case quantity
        case unit
        case unitCost = "unit_cost"
        case sortOrder = "sort_order"
    }

    init(from line: EstimateLineItem, sortOrder: Int) {
        self.name = line.name

        // Preserve the estimate's quantity × unit context so the rolled-up
        // invoice line stays human-readable.
        let trimmedUnit = line.unit.trimmingCharacters(in: .whitespaces)
        let qtyNote: String?
        if line.quantity != 1, !trimmedUnit.isEmpty {
            let qtyString = NSDecimalNumber(decimal: line.quantity).stringValue
            qtyNote = "\(qtyString) \(trimmedUnit)"
        } else {
            qtyNote = nil
        }

        switch (qtyNote, line.description?.isEmpty == false ? line.description : nil) {
        case let (.some(note), .some(desc)): self.description = "\(note) — \(desc)"
        case let (.some(note), .none): self.description = note
        case let (.none, .some(desc)): self.description = desc
        case (.none, .none): self.description = nil
        }

        self.quantity = 1
        self.unit = trimmedUnit.isEmpty ? "lot" : trimmedUnit
        self.unitCost = line.lineTotal
        self.sortOrder = sortOrder
    }
}

/// Mark-paid body. Settles the invoice in full; the backend stamps `paid_at`
/// and recomputes `amount_due = total_amount - amount_paid`.
struct MarkInvoicePaidBody: Encodable, Sendable {
    let status: String
    let amountPaid: Decimal

    enum CodingKeys: String, CodingKey {
        case status
        case amountPaid = "amount_paid"
    }
}

// MARK: - Errors

enum InvoiceServiceError: LocalizedError {
    case notFound
    case createFailed
    case sendFailed
    case missingClient

    var errorDescription: String? {
        switch self {
        case .notFound: "Invoice not found."
        case .createFailed: "Failed to create invoice. Please try again."
        case .sendFailed: "Failed to send invoice. Please try again."
        case .missingClient: "Add a client to this project before creating an invoice."
        }
    }
}

// MARK: - Mock Implementation

final class MockInvoiceService: InvoiceServiceProtocol {
    private let simulatedDelay: UInt64 = 400_000_000 // 0.4s

    func listByProject(projectId: String) async throws -> [Invoice] {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return [Invoice.sample].filter { $0.projectId == projectId }
    }

    func getInvoice(id: String) async throws -> Invoice {
        try await Task.sleep(nanoseconds: simulatedDelay)
        guard Invoice.sample.id == id else { throw InvoiceServiceError.notFound }
        return .sample
    }

    func getLineItems(invoiceId: String) async throws -> [InvoiceLineItem] {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return [InvoiceLineItem.sample].filter { $0.invoiceId == invoiceId }
    }

    func createFromEstimate(estimate _: Estimate, lineItems _: [EstimateLineItem], clientId _: String) async throws -> Invoice {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return .sample
    }

    func sendInvoice(id _: String) async throws -> Invoice {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return .sample
    }

    func markPaid(id _: String, amount _: Decimal) async throws -> Invoice {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return .sample
    }

    func deleteInvoice(id _: String) async throws {
        try await Task.sleep(nanoseconds: simulatedDelay)
    }
}
