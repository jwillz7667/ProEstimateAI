import Foundation

/// Drives the invoice detail sheet: loads the latest invoice + line items,
/// sends the invoice to the client, and reconciles payment. Marking an invoice
/// paid emits an `AppEventBus` payment event so revenue-dependent surfaces
/// (the dashboard) refresh without a manual reload.
@MainActor
@Observable
final class InvoiceDetailViewModel {
    // MARK: - State

    var invoice: Invoice
    var lineItems: [InvoiceLineItem] = []

    var isLoading = false
    var isSending = false
    var isMarkingPaid = false
    var errorMessage: String?

    // MARK: - Dependencies

    private let service: InvoiceServiceProtocol

    // MARK: - Init

    init(invoice: Invoice, service: InvoiceServiceProtocol = LiveInvoiceService()) {
        self.invoice = invoice
        self.service = service
    }

    // MARK: - Loading

    func load() async {
        isLoading = true
        defer { isLoading = false }

        async let latest: Invoice? = try? await service.getInvoice(id: invoice.id)
        async let items: [InvoiceLineItem]? = try? await service.getLineItems(invoiceId: invoice.id)

        if let refreshed = await latest { invoice = refreshed }
        lineItems = (await items ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - Actions

    func send() async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            invoice = try await service.sendInvoice(id: invoice.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markPaid() async {
        guard !isMarkingPaid else { return }
        isMarkingPaid = true
        defer { isMarkingPaid = false }
        do {
            invoice = try await service.markPaid(id: invoice.id, amount: invoice.totalAmount)
            // Revenue just changed — let the dashboard know so its metrics
            // pick up this payment on next appearance.
            AppEventBus.shared.notePaymentChange()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
