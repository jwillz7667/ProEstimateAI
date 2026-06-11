import Foundation

// MARK: - Protocol

/// Invoice domain operations. The product loop creates invoices by
/// converting an approved estimate (`convertEstimate`) rather than building
/// them from scratch, so there is no blank-create entry point here — the
/// money and line items are always inherited from the source estimate.
protocol InvoiceServiceProtocol: Sendable {
    func listInvoices() async throws -> [Invoice]
    func getInvoice(id: String) async throws -> Invoice
    func getLineItems(invoiceId: String) async throws -> [InvoiceLineItem]
    func updateInvoice(id: String, request: UpdateInvoiceRequest) async throws -> Invoice
    func sendInvoice(id: String) async throws -> Invoice
    func deleteInvoice(id: String) async throws
    func convertEstimate(estimateId: String, request: ConvertEstimateRequest) async throws -> Invoice
    func exportPDF(id: String) async throws -> Data
}

// MARK: - Request DTOs

/// Partial update. Only set fields are sent; omitted keys are left
/// unchanged by the backend. Used to mark an invoice sent, record a
/// payment (`amountPaid` + `status`), or adjust terms.
struct UpdateInvoiceRequest: Encodable, Sendable {
    var status: Invoice.Status?
    var amountPaid: Decimal?
    var dueDate: Date?
    var notes: String?
    var paymentInstructions: String?

    enum CodingKeys: String, CodingKey {
        case status
        case amountPaid = "amount_paid"
        case dueDate = "due_date"
        case notes
        case paymentInstructions = "payment_instructions"
    }
}

/// Overrides for `POST /v1/estimates/:id/convert-to-invoice`. Every field is
/// optional — an all-nil request produces a faithful DRAFT invoice mirroring
/// the estimate. Nil fields are omitted from the wire body (the backend
/// schema is `.strict()` and accepts an empty object).
struct ConvertEstimateRequest: Encodable, Sendable {
    var dueDate: Date?
    var notes: String?
    var paymentInstructions: String?

    enum CodingKeys: String, CodingKey {
        case dueDate = "due_date"
        case notes
        case paymentInstructions = "payment_instructions"
    }

    /// An empty conversion — faithful copy of the estimate with no overrides.
    static let faithful = ConvertEstimateRequest()
}

// MARK: - Errors

enum InvoiceServiceError: LocalizedError {
    case notFound
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .notFound: "Invoice not found."
        case .exportFailed: "Couldn't prepare the invoice PDF. Please try again."
        }
    }
}

// MARK: - Mock Implementation

final class MockInvoiceService: InvoiceServiceProtocol {
    private let simulatedDelay: UInt64 = 500_000_000 // 0.5s

    func listInvoices() async throws -> [Invoice] {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return Self.sampleInvoices
    }

    func getInvoice(id: String) async throws -> Invoice {
        try await Task.sleep(nanoseconds: simulatedDelay)
        guard let invoice = Self.sampleInvoices.first(where: { $0.id == id }) else {
            throw InvoiceServiceError.notFound
        }
        return invoice
    }

    func getLineItems(invoiceId: String) async throws -> [InvoiceLineItem] {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return Self.sampleLineItems.filter { $0.invoiceId == invoiceId }
    }

    func updateInvoice(id: String, request: UpdateInvoiceRequest) async throws -> Invoice {
        try await Task.sleep(nanoseconds: simulatedDelay)
        let invoice = try await getInvoice(id: id)
        return invoice
    }

    func sendInvoice(id: String) async throws -> Invoice {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return try await getInvoice(id: id)
    }

    func deleteInvoice(id _: String) async throws {
        try await Task.sleep(nanoseconds: simulatedDelay)
    }

    func convertEstimate(estimateId _: String, request _: ConvertEstimateRequest) async throws -> Invoice {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return Invoice.sample
    }

    func exportPDF(id _: String) async throws -> Data {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return Data("%PDF-1.4\n%mock-invoice\n".utf8)
    }
}

// MARK: - Sample Data

extension MockInvoiceService {
    static let sampleInvoices: [Invoice] = [
        Invoice(
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
            issuedDate: Calendar.current.date(byAdding: .day, value: -4, to: Date()),
            dueDate: Calendar.current.date(byAdding: .day, value: 26, to: Date()),
            paidAt: nil,
            sentAt: Calendar.current.date(byAdding: .day, value: -4, to: Date()),
            notes: "Thank you for your business.",
            paymentInstructions: "Net 30. Check or ACH accepted.",
            currencyCode: "USD",
            createdAt: Calendar.current.date(byAdding: .day, value: -4, to: Date())!,
            updatedAt: Calendar.current.date(byAdding: .day, value: -4, to: Date())!
        ),
        Invoice(
            id: "inv-002",
            estimateId: "e-003",
            proposalId: nil,
            projectId: "p-003",
            companyId: "c-001",
            clientId: "cl-003",
            invoiceNumber: "INV-1002",
            status: .paid,
            subtotal: 41200,
            taxAmount: 3399,
            discountAmount: 1000,
            totalAmount: 43599,
            amountPaid: 43599,
            amountDue: 0,
            issuedDate: Calendar.current.date(byAdding: .day, value: -20, to: Date()),
            dueDate: Calendar.current.date(byAdding: .day, value: -5, to: Date()),
            paidAt: Calendar.current.date(byAdding: .day, value: -6, to: Date()),
            sentAt: Calendar.current.date(byAdding: .day, value: -20, to: Date()),
            notes: nil,
            paymentInstructions: "Net 15.",
            currencyCode: "USD",
            createdAt: Calendar.current.date(byAdding: .day, value: -20, to: Date())!,
            updatedAt: Calendar.current.date(byAdding: .day, value: -6, to: Date())!
        ),
        Invoice(
            id: "inv-003",
            estimateId: "e-002",
            proposalId: nil,
            projectId: "p-002",
            companyId: "c-001",
            clientId: "cl-002",
            invoiceNumber: "INV-1003",
            status: .draft,
            subtotal: 13800,
            taxAmount: 1179.75,
            discountAmount: 500,
            totalAmount: 14479.75,
            amountPaid: 0,
            amountDue: 14479.75,
            issuedDate: nil,
            dueDate: nil,
            paidAt: nil,
            sentAt: nil,
            notes: "Bathroom remodel — master bath.",
            paymentInstructions: nil,
            currencyCode: "USD",
            createdAt: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
            updatedAt: Calendar.current.date(byAdding: .hour, value: -3, to: Date())!
        ),
    ]

    static let sampleLineItems: [InvoiceLineItem] = [
        InvoiceLineItem(
            id: "ili-001",
            invoiceId: "inv-001",
            name: "Quartz Countertop – Calacatta",
            description: "Premium quartz slab, fabrication included",
            quantity: 45,
            unit: "sq ft",
            unitCost: 75,
            lineTotal: 3375,
            sortOrder: 0
        ),
        InvoiceLineItem(
            id: "ili-002",
            invoiceId: "inv-001",
            name: "Shaker Cabinets – White",
            description: "Soft-close hinges, dovetail drawers",
            quantity: 14,
            unit: "each",
            unitCost: 450,
            lineTotal: 6300,
            sortOrder: 1
        ),
        InvoiceLineItem(
            id: "ili-003",
            invoiceId: "inv-001",
            name: "Cabinet & Countertop Installation",
            description: "Demolition, install, and finishing labor",
            quantity: 64,
            unit: "hour",
            unitCost: 72,
            lineTotal: 4608,
            sortOrder: 2
        ),
    ]
}
