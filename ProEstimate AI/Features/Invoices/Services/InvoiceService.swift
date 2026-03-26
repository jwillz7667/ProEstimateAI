import Foundation

// MARK: - Protocol

protocol InvoiceServiceProtocol: Sendable {
    func listInvoices() async throws -> [Invoice]
    func getInvoice(id: String) async throws -> Invoice
    func getInvoiceLineItems(invoiceId: String) async throws -> [InvoiceLineItem]
    func getInvoiceProject(projectId: String) async throws -> Project
    func getInvoiceClient(clientId: String) async throws -> Client
    func getInvoiceCompany(companyId: String) async throws -> Company
    func createInvoice(_ invoice: Invoice) async throws -> Invoice
    func createFromEstimate(estimateId: String) async throws -> Invoice
    func updateInvoice(_ invoice: Invoice) async throws -> Invoice
    func deleteInvoice(id: String) async throws
    func sendInvoice(id: String) async throws -> Invoice
    func markAsPaid(id: String) async throws -> Invoice
}

// MARK: - Mock Implementation

final class MockInvoiceService: InvoiceServiceProtocol {
    private let simulatedDelay: UInt64 = 500_000_000

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

    func getInvoiceLineItems(invoiceId: String) async throws -> [InvoiceLineItem] {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return Self.sampleLineItems.filter { $0.invoiceId == invoiceId }
    }

    func getInvoiceProject(projectId: String) async throws -> Project {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return Project.sample
    }

    func getInvoiceClient(clientId: String) async throws -> Client {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return Client.sample
    }

    func getInvoiceCompany(companyId: String) async throws -> Company {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return Company.sample
    }

    func createInvoice(_ invoice: Invoice) async throws -> Invoice {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return invoice
    }

    func createFromEstimate(estimateId: String) async throws -> Invoice {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return Self.sampleInvoices[0]
    }

    func updateInvoice(_ invoice: Invoice) async throws -> Invoice {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return invoice
    }

    func deleteInvoice(id: String) async throws {
        try await Task.sleep(nanoseconds: simulatedDelay)
    }

    func sendInvoice(id: String) async throws -> Invoice {
        try await Task.sleep(nanoseconds: simulatedDelay)
        guard let invoice = Self.sampleInvoices.first(where: { $0.id == id }) else {
            throw InvoiceServiceError.notFound
        }
        return Invoice(
            id: invoice.id,
            estimateId: invoice.estimateId,
            projectId: invoice.projectId,
            companyId: invoice.companyId,
            clientId: invoice.clientId,
            invoiceNumber: invoice.invoiceNumber,
            status: .sent,
            subtotal: invoice.subtotal,
            taxAmount: invoice.taxAmount,
            totalAmount: invoice.totalAmount,
            amountPaid: invoice.amountPaid,
            amountDue: invoice.amountDue,
            dueDate: invoice.dueDate,
            paidAt: nil,
            sentAt: Date(),
            notes: invoice.notes,
            createdAt: invoice.createdAt,
            updatedAt: Date()
        )
    }

    func markAsPaid(id: String) async throws -> Invoice {
        try await Task.sleep(nanoseconds: simulatedDelay)
        guard let invoice = Self.sampleInvoices.first(where: { $0.id == id }) else {
            throw InvoiceServiceError.notFound
        }
        return Invoice(
            id: invoice.id,
            estimateId: invoice.estimateId,
            projectId: invoice.projectId,
            companyId: invoice.companyId,
            clientId: invoice.clientId,
            invoiceNumber: invoice.invoiceNumber,
            status: .paid,
            subtotal: invoice.subtotal,
            taxAmount: invoice.taxAmount,
            totalAmount: invoice.totalAmount,
            amountPaid: invoice.totalAmount,
            amountDue: 0,
            dueDate: invoice.dueDate,
            paidAt: Date(),
            sentAt: invoice.sentAt,
            notes: invoice.notes,
            createdAt: invoice.createdAt,
            updatedAt: Date()
        )
    }
}

// MARK: - Errors

enum InvoiceServiceError: LocalizedError {
    case notFound
    case sendFailed
    case paymentFailed

    var errorDescription: String? {
        switch self {
        case .notFound: "Invoice not found."
        case .sendFailed: "Failed to send invoice. Please try again."
        case .paymentFailed: "Failed to record payment. Please try again."
        }
    }
}

// MARK: - Sample Data

extension MockInvoiceService {
    static let sampleInvoices: [Invoice] = [
        Invoice(
            id: "inv-001",
            estimateId: "e-001",
            projectId: "p-001",
            companyId: "c-001",
            clientId: "cl-001",
            invoiceNumber: "INV-2001",
            status: .sent,
            subtotal: 21000,
            taxAmount: 1732.50,
            totalAmount: 22732.50,
            amountPaid: 11366.25,
            amountDue: 11366.25,
            dueDate: Calendar.current.date(byAdding: .day, value: 14, to: Date()),
            paidAt: nil,
            sentAt: Calendar.current.date(byAdding: .day, value: -3, to: Date()),
            notes: "50% deposit received. Balance due upon completion.",
            createdAt: Calendar.current.date(byAdding: .day, value: -5, to: Date())!,
            updatedAt: Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        ),
        Invoice(
            id: "inv-002",
            estimateId: "e-002",
            projectId: "p-002",
            companyId: "c-001",
            clientId: "cl-002",
            invoiceNumber: "INV-2002",
            status: .paid,
            subtotal: 14300,
            taxAmount: 1179.75,
            totalAmount: 15479.75,
            amountPaid: 15479.75,
            amountDue: 0,
            dueDate: Calendar.current.date(byAdding: .day, value: -2, to: Date()),
            paidAt: Calendar.current.date(byAdding: .day, value: -3, to: Date()),
            sentAt: Calendar.current.date(byAdding: .day, value: -14, to: Date()),
            notes: "Payment received in full.",
            createdAt: Calendar.current.date(byAdding: .day, value: -16, to: Date())!,
            updatedAt: Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        ),
        Invoice(
            id: "inv-003",
            estimateId: "e-003",
            projectId: "p-003",
            companyId: "c-001",
            clientId: "cl-003",
            invoiceNumber: "INV-2003",
            status: .overdue,
            subtotal: 41200,
            taxAmount: 3399,
            totalAmount: 44599,
            amountPaid: 0,
            amountDue: 44599,
            dueDate: Calendar.current.date(byAdding: .day, value: -7, to: Date()),
            paidAt: nil,
            sentAt: Calendar.current.date(byAdding: .day, value: -30, to: Date()),
            notes: "Payment overdue. Follow up required.",
            createdAt: Calendar.current.date(byAdding: .day, value: -35, to: Date())!,
            updatedAt: Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        ),
        Invoice(
            id: "inv-004",
            estimateId: nil,
            projectId: "p-001",
            companyId: "c-001",
            clientId: "cl-001",
            invoiceNumber: "INV-2004",
            status: .draft,
            subtotal: 5500,
            taxAmount: 453.75,
            totalAmount: 5953.75,
            amountPaid: 0,
            amountDue: 5953.75,
            dueDate: Calendar.current.date(byAdding: .day, value: 30, to: Date()),
            paidAt: nil,
            sentAt: nil,
            notes: "Additional work — change order #1.",
            createdAt: Date(),
            updatedAt: Date()
        ),
    ]

    static let sampleLineItems: [InvoiceLineItem] = [
        InvoiceLineItem(
            id: "ili-001",
            invoiceId: "inv-001",
            name: "Quartz Countertop – Calacatta",
            description: "45 sq ft premium quartz slab, fabrication included",
            quantity: 1,
            unit: "lot",
            unitCost: 4387.50,
            lineTotal: 4387.50,
            sortOrder: 0
        ),
        InvoiceLineItem(
            id: "ili-002",
            invoiceId: "inv-001",
            name: "Shaker Cabinets – White (14)",
            description: "Soft-close hinges, dovetail drawers, installation",
            quantity: 1,
            unit: "lot",
            unitCost: 8164.35,
            lineTotal: 8164.35,
            sortOrder: 1
        ),
        InvoiceLineItem(
            id: "ili-003",
            invoiceId: "inv-001",
            name: "Demolition & Removal",
            description: "Remove existing cabinets, counters, flooring",
            quantity: 16,
            unit: "hour",
            unitCost: 65,
            lineTotal: 1040,
            sortOrder: 2
        ),
        InvoiceLineItem(
            id: "ili-004",
            invoiceId: "inv-001",
            name: "Installation Labor",
            description: "Cabinet and countertop installation",
            quantity: 1,
            unit: "lot",
            unitCost: 6908.15,
            lineTotal: 6908.15,
            sortOrder: 3
        ),
        InvoiceLineItem(
            id: "ili-005",
            invoiceId: "inv-001",
            name: "Dumpster Rental & Misc",
            description: "10-yard dumpster, cleanup, permits",
            quantity: 1,
            unit: "lot",
            unitCost: 500,
            lineTotal: 500,
            sortOrder: 4
        ),
        InvoiceLineItem(
            id: "ili-006",
            invoiceId: "inv-002",
            name: "Master Bath Remodel – Full Package",
            description: "Tile, shower kit, fixtures, labor",
            quantity: 1,
            unit: "lot",
            unitCost: 14300,
            lineTotal: 14300,
            sortOrder: 0
        ),
    ]
}

// MARK: - Invoice Summary

/// Lightweight summary combining invoice with project/client info for list display.
struct InvoiceSummary: Identifiable, Sendable {
    let id: String
    let invoice: Invoice
    let projectTitle: String
    let clientName: String

    init(invoice: Invoice, projectTitle: String, clientName: String) {
        self.id = invoice.id
        self.invoice = invoice
        self.projectTitle = projectTitle
        self.clientName = clientName
    }
}

// MARK: - Invoice Status Filter

enum InvoiceStatusFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case draft
    case sent
    case paid
    case overdue
    case void

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .draft: "Draft"
        case .sent: "Sent"
        case .paid: "Paid"
        case .overdue: "Overdue"
        case .void: "Void"
        }
    }

    var matchingStatuses: [Invoice.Status] {
        switch self {
        case .all: Invoice.Status.allCases
        case .draft: [.draft]
        case .sent: [.sent, .viewed]
        case .paid: [.paid, .partiallyPaid]
        case .overdue: [.overdue]
        case .void: [.void]
        }
    }
}
