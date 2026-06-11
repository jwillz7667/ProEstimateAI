import Foundation
import Observation

@Observable
final class InvoiceDetailViewModel {
    // MARK: - State

    var invoice: Invoice?
    var lineItems: [InvoiceLineItem] = []
    var isLoading: Bool = false
    var errorMessage: String?

    /// Surfaced as a transient alert when a lifecycle action (send, mark
    /// paid, delete, export) fails — kept separate from `errorMessage` so a
    /// failed action doesn't replace the loaded invoice with an error state.
    var actionError: String?
    var isPerformingAction: Bool = false
    var isExporting: Bool = false

    // MARK: - Dependencies

    private let invoiceService: InvoiceServiceProtocol

    // MARK: - Init

    init(invoiceService: InvoiceServiceProtocol = LiveInvoiceService()) {
        self.invoiceService = invoiceService
    }

    // MARK: - Loading

    func load(id: String) async {
        isLoading = true
        errorMessage = nil

        // Fetch the invoice and its line items concurrently — neither
        // depends on the other and the detail screen needs both.
        async let invoiceTask = invoiceService.getInvoice(id: id)
        async let lineItemsTask = invoiceService.getLineItems(invoiceId: id)

        do {
            let fetchedInvoice = try await invoiceTask
            // Line items are non-critical chrome — a failure there shouldn't
            // blank the whole screen, so it degrades to an empty list.
            let fetchedLineItems = (try? await lineItemsTask) ?? []
            invoice = fetchedInvoice
            lineItems = fetchedLineItems.sorted { $0.sortOrder < $1.sortOrder }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Lifecycle Actions

    /// Mark a DRAFT invoice as sent. Uses the dedicated send endpoint so the
    /// backend stamps `sent_at` and transitions the status atomically.
    func markAsSent() async {
        guard let id = invoice?.id, !isPerformingAction else { return }
        isPerformingAction = true
        actionError = nil

        do {
            invoice = try await invoiceService.sendInvoice(id: id)
        } catch {
            actionError = error.localizedDescription
        }

        isPerformingAction = false
    }

    /// Record full payment — sets the balance to zero and status to paid.
    func markAsPaid() async {
        guard let current = invoice, !isPerformingAction else { return }
        isPerformingAction = true
        actionError = nil

        let request = UpdateInvoiceRequest(
            status: .paid,
            amountPaid: current.totalAmount
        )

        do {
            invoice = try await invoiceService.updateInvoice(id: current.id, request: request)
        } catch {
            actionError = error.localizedDescription
        }

        isPerformingAction = false
    }

    /// Delete the invoice. Returns `true` on success so the caller can pop /
    /// dismiss and refresh the list.
    func delete() async -> Bool {
        guard let id = invoice?.id, !isPerformingAction else { return false }
        isPerformingAction = true
        actionError = nil

        do {
            try await invoiceService.deleteInvoice(id: id)
            isPerformingAction = false
            return true
        } catch {
            actionError = error.localizedDescription
            isPerformingAction = false
            return false
        }
    }

    /// Fetch the server-rendered PDF and write it to a temp file so the
    /// share sheet has a real URL to hand to other apps. Returns the file
    /// URL, or nil on failure (with `actionError` set).
    func exportPDF() async -> URL? {
        guard let invoice, !isExporting else { return nil }
        isExporting = true
        actionError = nil

        defer { isExporting = false }

        do {
            let data = try await invoiceService.exportPDF(id: invoice.id)
            guard !data.isEmpty else {
                actionError = InvoiceServiceError.exportFailed.localizedDescription
                return nil
            }
            let fileName = "\(invoice.invoiceNumber).pdf"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            actionError = error.localizedDescription
            return nil
        }
    }
}
