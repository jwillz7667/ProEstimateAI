import Foundation

/// A billing document issued to a client for completed or in-progress work.
/// Invoices are the final step of the get-paid loop: created from an estimate
/// (optionally via a proposal), sent to the client, then reconciled against
/// payments. All monetary totals are computed and persisted server-side.
struct Invoice: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let estimateId: String?
    let proposalId: String?
    let projectId: String
    let companyId: String
    let clientId: String
    let invoiceNumber: String
    let status: Status
    let subtotal: Decimal
    let taxAmount: Decimal
    let discountAmount: Decimal
    let totalAmount: Decimal
    let amountPaid: Decimal
    let amountDue: Decimal
    let issuedDate: Date?
    let dueDate: Date?
    let paidAt: Date?
    let sentAt: Date?
    let notes: String?
    let paymentInstructions: String?
    let currencyCode: String?
    let createdAt: Date
    let updatedAt: Date

    // MARK: - Nested Enums

    /// Tracks the invoice through its payment lifecycle. Raw values match the
    /// lowercase strings the backend emits.
    enum Status: String, Codable, CaseIterable, Sendable {
        case draft
        case sent
        case viewed
        case partiallyPaid = "partially_paid"
        case paid
        case overdue
        case void
    }

    enum CodingKeys: String, CodingKey {
        case id
        case estimateId = "estimate_id"
        case proposalId = "proposal_id"
        case projectId = "project_id"
        case companyId = "company_id"
        case clientId = "client_id"
        case invoiceNumber = "invoice_number"
        case status
        case subtotal
        case taxAmount = "tax_amount"
        case discountAmount = "discount_amount"
        case totalAmount = "total_amount"
        case amountPaid = "amount_paid"
        case amountDue = "amount_due"
        case issuedDate = "issued_date"
        case dueDate = "due_date"
        case paidAt = "paid_at"
        case sentAt = "sent_at"
        case notes
        case paymentInstructions = "payment_instructions"
        case currencyCode = "currency_code"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Convenience

extension Invoice {
    /// Whether the invoice still has an outstanding balance.
    var isOutstanding: Bool {
        amountDue > 0 && status != .void
    }

    /// Whether the invoice has been fully settled.
    var isPaid: Bool {
        status == .paid
    }

    /// Whether the invoice can still be sent to the client (not already
    /// delivered, paid, or voided).
    var canSend: Bool {
        status == .draft
    }

    /// Whether a "mark as paid" action is meaningful for the current status.
    var canMarkPaid: Bool {
        status != .paid && status != .void
    }

    /// ISO-4217 currency code with a sensible default for formatting.
    var resolvedCurrencyCode: String {
        currencyCode ?? "USD"
    }
}

// MARK: - Sample Data

extension Invoice {
    static let sample = Invoice(
        id: "inv-001",
        estimateId: "e-001",
        proposalId: nil,
        projectId: "p-001",
        companyId: "c-001",
        clientId: "cl-001",
        invoiceNumber: "INV-1001",
        status: .sent,
        subtotal: 21000,
        taxAmount: 1732.50,
        discountAmount: 0,
        totalAmount: 22732.50,
        amountPaid: 0,
        amountDue: 22732.50,
        issuedDate: Date(),
        dueDate: Calendar.current.date(byAdding: .day, value: 30, to: Date()),
        paidAt: nil,
        sentAt: Date(),
        notes: "Net 30. Thank you for your business.",
        paymentInstructions: "Checks payable to ProEstimate Builders LLC.",
        currencyCode: "USD",
        createdAt: Date(),
        updatedAt: Date()
    )
}
