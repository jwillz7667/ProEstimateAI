import Foundation

struct InvoiceFinanceService: InvoiceFinanceServing {
    private let apiClient: any APIClientProtocol
    private let sessionId: UUID
    init(apiClient: any APIClientProtocol = APIClient.shared) {
        self.apiClient = apiClient
        sessionId = TokenStore.shared.sessionIdentifier
    }

    func getFinance(invoiceId: String) async throws -> InvoiceFinanceSnapshot {
        try requireSession()
        return try await apiClient.request(.getInvoiceFinance(id: invoiceId))
    }
    func recordPayment(invoiceId: String, request: RecordReceivedPaymentRequest) async throws -> InvoiceFinanceSnapshot {
        try requireSession()
        return try await apiClient.request(.recordInvoicePayment(id: invoiceId, body: request))
    }
    func updateSchedule(invoiceId: String, request: UpdateInvoiceScheduleRequest) async throws -> InvoiceFinanceSnapshot {
        try requireSession()
        return try await apiClient.request(.updateInvoiceSchedule(id: invoiceId, body: request))
    }
    func cancelCheckout(invoiceId: String) async throws {
        try requireSession()
        try await apiClient.request(.cancelInvoiceCheckout(id: invoiceId, body: EmptyInvoiceFinanceBody())) as Void
    }
    func reviewRefund(invoiceId: String, request: ReviewInvoiceRefundRequest) async throws {
        try requireSession()
        try await apiClient.request(.reviewInvoiceRefund(id: invoiceId, body: request)) as Void
    }

    private func requireSession() throws {
        try Task.checkCancellation()
        guard TokenStore.shared.sessionIdentifier == sessionId else { throw APIError.unauthorized }
    }
}

private struct EmptyInvoiceFinanceBody: Encodable, Sendable {}
