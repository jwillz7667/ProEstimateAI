import Foundation

/// Represents an invoice sent to a client for payment.
/// Invoices are Pro-only and are typically created from an approved estimate.
/// They track partial payments and due dates.
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

    /// Tracks the invoice through the payment lifecycle.
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
    /// Whether the invoice has been fully paid.
    var isFullyPaid: Bool {
        status == .paid
    }

    /// Whether the invoice is past its due date and unpaid.
    var isPastDue: Bool {
        guard let dueDate, status != .paid, status != .void else { return false }
        return dueDate < Date()
    }

    /// Payment progress as a value between 0.0 and 1.0.
    var paymentProgress: Double {
        guard totalAmount > 0 else { return 0 }
        return NSDecimalNumber(decimal: amountPaid / totalAmount).doubleValue
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
        invoiceNumber: "INV-2001",
        status: .sent,
        subtotal: 21000,
        taxAmount: 1732.50,
        discountAmount: 0,
        totalAmount: 22732.50,
        amountPaid: 11366.25,
        amountDue: 11366.25,
        issuedDate: Date(),
        dueDate: Calendar.current.date(byAdding: .day, value: 14, to: Date()),
        paidAt: nil,
        sentAt: Date(),
        notes: "50% deposit received. Balance due upon completion.",
        paymentInstructions: "Zelle or check payable to Apex Remodeling Co.",
        currencyCode: "USD",
        createdAt: Date(),
        updatedAt: Date()
    )
}
