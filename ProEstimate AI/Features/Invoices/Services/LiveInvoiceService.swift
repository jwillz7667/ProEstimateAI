import Foundation

/// Production implementation of `InvoiceServiceProtocol` that delegates
/// all invoice operations to the backend REST API via `APIClient`.
final class LiveInvoiceService: InvoiceServiceProtocol, Sendable {
    private let apiClient: APIClientProtocol

    init(apiClient: APIClientProtocol = APIClient.shared) {
        self.apiClient = apiClient
    }

    // MARK: - InvoiceServiceProtocol

    func listInvoices() async throws -> [Invoice] {
        try await apiClient.request(.listInvoices(projectId: nil))
    }

    func getInvoice(id: String) async throws -> Invoice {
        try await apiClient.request(.getInvoice(id: id))
    }

    func getInvoiceLineItems(invoiceId: String) async throws -> [InvoiceLineItem] {
        try await apiClient.request(.listInvoiceLineItems(invoiceId: invoiceId))
    }

    func getInvoiceProject(projectId: String) async throws -> Project {
        try await apiClient.request(.getProject(id: projectId))
    }

    func getInvoiceClient(clientId: String) async throws -> Client {
        try await apiClient.request(.getClient(id: clientId))
    }

    func getInvoiceCompany(companyId: String) async throws -> Company {
        // The API returns the company for the authenticated user via /companies/me.
        // The companyId parameter is accepted for protocol conformance but not used
        // in the request path — the backend resolves the company from the auth token.
        try await apiClient.request(.getCompany)
    }

    func createInvoice(_ invoice: Invoice) async throws -> Invoice {
        try await apiClient.request(.createInvoice(body: invoice))
    }

    func createFromEstimate(estimateId: String) async throws -> Invoice {
        let body = CreateFromEstimateBody(estimateId: estimateId)
        return try await apiClient.request(.createInvoice(body: body))
    }

    func updateInvoice(_ invoice: Invoice) async throws -> Invoice {
        try await apiClient.request(.updateInvoice(id: invoice.id, body: invoice))
    }

    func deleteInvoice(id: String) async throws {
        try await apiClient.request(.deleteInvoice(id: id)) as Void
    }

    func sendInvoice(id: String) async throws -> Invoice {
        try await apiClient.request(.sendInvoice(id: id))
    }

    func markAsPaid(id: String) async throws -> Invoice {
        // Fetch the current invoice so we can carry forward totals when we update.
        // The backend expects status, paidAt, and amountPaid = totalAmount for a full-payment mark.
        let current: Invoice = try await apiClient.request(.getInvoice(id: id))
        let body = MarkPaidBody(
            status: "paid",
            paidAt: Date(),
            amountPaid: current.totalAmount,
            amountDue: 0
        )
        return try await apiClient.request(.updateInvoice(id: id, body: body))
    }
}

// MARK: - Request Bodies

/// Body for creating an invoice from an existing estimate.
/// The encoder uses `.convertToSnakeCase`, so `estimateId` becomes `"estimate_id"`.
private struct CreateFromEstimateBody: Encodable, Sendable {
    let estimateId: String
}

/// Body sent when marking an invoice as fully paid.
/// Records the payment timestamp and zeros the amount due so downstream
/// dashboards and revenue metrics pick up the payment immediately.
private struct MarkPaidBody: Encodable, Sendable {
    let status: String
    let paidAt: Date
    let amountPaid: Decimal
    let amountDue: Decimal
}
