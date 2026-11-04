import Foundation
import Observation

@MainActor
@Observable
final class InvoiceListViewModel {
    // MARK: - State

    var invoices: [Invoice] = []
    var searchText: String = ""
    var isLoading: Bool = false
    var errorMessage: String?

    // MARK: - Computed

    var filteredInvoices: [Invoice] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return invoices
        }
        return invoices.filter { invoice in
            invoice.invoiceNumber.localizedCaseInsensitiveContains(query)
                || invoice.statusLabel.localizedCaseInsensitiveContains(query)
        }
    }

    var hasInvoices: Bool {
        !invoices.isEmpty
    }

    /// Keep currencies separate; no exchange rate is inferred from a device locale.
    var outstandingByCurrency: [InvoiceCurrencyBalance] {
        InvoiceCurrencyBalance.outstanding(in: invoices)
    }

    // MARK: - Dependencies

    private let invoiceService: InvoiceServiceProtocol

    // MARK: - Init

    init(invoiceService: InvoiceServiceProtocol = LiveInvoiceService()) {
        self.invoiceService = invoiceService
    }

    // MARK: - Actions

    func loadInvoices() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            invoices = try await invoiceService.listInvoices()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func refresh() async {
        await loadInvoices()
    }

    /// Reflect a newly created / converted invoice without a full reload.
    func upsert(_ invoice: Invoice) {
        if let index = invoices.firstIndex(where: { $0.id == invoice.id }) {
            invoices[index] = invoice
        } else {
            invoices.insert(invoice, at: 0)
        }
    }

    /// Drop an invoice from the in-memory list when the deletion has already
    /// been performed upstream (e.g. from `InvoiceDetailView`).
    func removeInvoice(id: String) {
        invoices.removeAll { $0.id == id }
    }
}
