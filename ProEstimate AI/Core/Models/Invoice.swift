import Foundation

/// A billing document issued to a client, typically converted from an
/// approved estimate. The invoice tracks money owed (`amountDue`) against
/// money received (`amountPaid`) and moves through a payment lifecycle.
/// Invoice creation is a Pro-only feature; the document itself is the final
/// step of the project loop (estimate → proposal → invoice).
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

    /// Payment lifecycle. Wire values are lowercase snake_case to match the
    /// backend DTO (`status.toLowerCase()`).
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
    /// Whether the invoice can still be edited / its line items changed.
    /// Only DRAFT invoices are mutable; once sent the document is locked.
    var isEditable: Bool {
        status == .draft
    }

    /// Whether the balance has been fully settled.
    var isPaid: Bool {
        status == .paid
    }

    /// Whether the invoice is past its due date with an outstanding balance.
    /// Derives the flag locally (the backend also flips status to `.overdue`)
    /// so the UI can warn even before the server-side sweep runs.
    var isPastDue: Bool {
        guard status != .paid, status != .void, amountDue > 0,
              let dueDate else { return false }
        return dueDate < Date()
    }

    /// Whether the client has paid part — but not all — of the balance.
    var isPartiallyPaid: Bool {
        status == .partiallyPaid || (amountPaid > 0 && amountDue > 0)
    }

    /// Human-readable status label for badges and headers.
    var statusLabel: String {
        switch status {
        case .draft: return "Draft"
        case .sent: return "Sent"
        case .viewed: return "Viewed"
        case .partiallyPaid: return "Partially Paid"
        case .paid: return "Paid"
        case .overdue: return "Overdue"
        case .void: return "Void"
        }
    }

    /// Maps the payment status onto the design-system `StatusBadge.Style`.
    /// Overdue invoices show as error, paid as success, in-flight as info,
    /// and the terminal `void` as neutral.
    var statusBadgeStyle: StatusBadge.Style {
        if isPastDue { return .error }
        switch status {
        case .paid: return .success
        case .overdue: return .error
        case .partiallyPaid: return .warning
        case .sent, .viewed: return .info
        case .draft: return .neutral
        case .void: return .neutral
        }
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
        notes: "Thank you for your business.",
        paymentInstructions: "Net 30. Check or ACH accepted.",
        currencyCode: "USD",
        createdAt: Date(),
        updatedAt: Date()
    )
}
