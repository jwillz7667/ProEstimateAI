import Foundation

/// Production implementation of `InvoiceServiceProtocol`. Delegates all
/// invoice operations to the backend REST API via `APIClient`. The PDF
/// export hits a binary endpoint, so it uses `requestData` rather than the
/// JSON-envelope `request`.
final class LiveInvoiceService: InvoiceServiceProtocol, Sendable {
    private let apiClient: APIClientProtocol

    init(apiClient: APIClientProtocol = APIClient.shared) {
        self.apiClient = apiClient
    }

    // MARK: - InvoiceServiceProtocol

    func listInvoices() async throws -> [Invoice] {
        try await apiClient.request(.listInvoices())
    }

    func getInvoice(id: String) async throws -> Invoice {
        try await apiClient.request(.getInvoice(id: id))
    }

    func getLineItems(invoiceId: String) async throws -> [InvoiceLineItem] {
        try await apiClient.request(.listInvoiceLineItems(invoiceId: invoiceId))
    }

    func updateInvoice(id: String, request: UpdateInvoiceRequest) async throws -> Invoice {
        try await apiClient.request(.updateInvoice(id: id, body: request))
    }

    func sendInvoice(id: String) async throws -> Invoice {
        try await apiClient.request(.sendInvoice(id: id))
    }

    func deleteInvoice(id: String) async throws {
        try await apiClient.request(.deleteInvoice(id: id)) as Void
    }

    func convertEstimate(estimateId: String, request: ConvertEstimateRequest) async throws -> Invoice {
        try await apiClient.request(.convertEstimateToInvoice(estimateId: estimateId, body: request))
    }

    func exportPDF(id: String) async throws -> Data {
        try await apiClient.requestData(.exportInvoicePDF(id: id))
    }
}
