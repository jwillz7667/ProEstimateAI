import Foundation

struct PendingInvoicePayment: Codable, Sendable {
    var schemaVersion = 1
    let scope: EstimateDraftScope
    let invoiceId: String
    let request: RecordReceivedPaymentRequest
    let savedAt: Date
}

protocol InvoicePaymentJournaling: Sendable {
    func load(scope: EstimateDraftScope, invoiceId: String) async throws -> PendingInvoicePayment?
    func save(_ payment: PendingInvoicePayment) async throws
    func remove(scope: EstimateDraftScope, invoiceId: String) async throws
}

@MainActor
final class InvoicePaymentJournal: InvoicePaymentJournaling {
    private let store: EstimateDraftStore
    private var sessions: [EstimateDraftScope: UUID] = [:]

    init(store: EstimateDraftStore = .shared) { self.store = store }

    func load(scope: EstimateDraftScope, invoiceId: String) async throws -> PendingInvoicePayment? {
        _ = try await session(for: scope)
        guard let data = try await store.loadJournal(scope: scope, namespace: "invoice-payment", recordId: invoiceId) else { return nil }
        let pending = try JSONDecoder().decode(PendingInvoicePayment.self, from: data)
        guard pending.schemaVersion == 1, pending.scope == scope, pending.invoiceId == invoiceId,
              UUID(uuidString: pending.request.requestId) != nil, pending.request.amount > 0,
              (pending.request.reference?.utf16.count ?? 0) <= 255,
              (pending.request.notes?.utf16.count ?? 0) <= 2000 else { throw InvoiceFinanceError.invalidJournal }
        return pending
    }

    func save(_ payment: PendingInvoicePayment) async throws {
        let id = try await session(for: payment.scope)
        let data = try JSONEncoder().encode(payment)
        try await store.saveJournal(data, scope: payment.scope, namespace: "invoice-payment", recordId: payment.invoiceId, sessionId: id)
    }

    func remove(scope: EstimateDraftScope, invoiceId: String) async throws {
        let id = try await session(for: scope)
        try await store.removeJournal(scope: scope, namespace: "invoice-payment", recordId: invoiceId, sessionId: id)
    }

    private func session(for scope: EstimateDraftScope) async throws -> UUID {
        if let session = sessions[scope] { return session }
        let session = try await store.openSession(scope: scope)
        sessions[scope] = session
        return session
    }
}
