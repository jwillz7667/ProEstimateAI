import Foundation

/// Production implementation of `InvoiceServiceProtocol`. Delegates all invoice
/// operations to the backend REST API via `APIClient`.
///
/// The backend does NOT auto-copy estimate line items onto a new invoice, so
/// `createFromEstimate` performs a three-step orchestration: create the invoice
/// shell, seed each line item from the estimate, then re-fetch so the returned
/// invoice carries the server-recomputed subtotal/tax/total.
final class LiveInvoiceService: InvoiceServiceProtocol, Sendable {
    private let apiClient: APIClientProtocol

    init(apiClient: APIClientProtocol = APIClient.shared) {
        self.apiClient = apiClient
    }

    func listByProject(projectId: String) async throws -> [Invoice] {
        try await apiClient.request(.listInvoices(projectId: projectId))
    }

    func getInvoice(id: String) async throws -> Invoice {
        try await apiClient.request(.getInvoice(id: id))
    }

    func getLineItems(invoiceId: String) async throws -> [InvoiceLineItem] {
        try await apiClient.request(.listInvoiceLineItems(invoiceId: invoiceId))
    }

    func createFromEstimate(estimate: Estimate, lineItems: [EstimateLineItem], clientId: String) async throws -> Invoice {
        let body = CreateInvoiceBody(
            projectId: estimate.projectId,
            clientId: clientId,
            estimateId: estimate.id
        )
        let invoice: Invoice = try await apiClient.request(.createInvoice(body: body))

        // Seed line items from the estimate, preserving display order. Done
        // sequentially so a backend failure surfaces immediately rather than
        // leaving an unbounded fan-out of half-applied writes.
        let ordered = lineItems.sorted { $0.sortOrder < $1.sortOrder }
        for (index, item) in ordered.enumerated() {
            let seed = CreateInvoiceLineItemBody(from: item, sortOrder: index)
            let _: InvoiceLineItem = try await apiClient.request(
                .createInvoiceLineItem(invoiceId: invoice.id, body: seed)
            )
        }

        // Re-fetch so totals reflect the seeded line items + company tax.
        return try await apiClient.request(.getInvoice(id: invoice.id))
    }

    func sendInvoice(id: String) async throws -> Invoice {
        try await apiClient.request(.sendInvoice(id: id))
    }

    func markPaid(id: String, amount: Decimal) async throws -> Invoice {
        let body = MarkInvoicePaidBody(status: Invoice.Status.paid.rawValue, amountPaid: amount)
        return try await apiClient.request(.updateInvoice(id: id, body: body))
    }

    func deleteInvoice(id: String) async throws {
        try await apiClient.request(.deleteInvoice(id: id)) as Void
    }
}
