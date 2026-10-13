import Foundation
import Observation

@MainActor
@Observable
final class InvoiceDetailViewModel {
    // MARK: - State

    var invoice: Invoice?
    var lineItems: [InvoiceLineItem] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var lineItemsError: String?

    /// Surfaced as a transient alert when a lifecycle action (send, mark
    /// paid, delete, export) fails — kept separate from `errorMessage` so a
    /// failed action doesn't replace the loaded invoice with an error state.
    var actionError: String?
    var isPerformingAction: Bool = false
    var isExporting: Bool = false
    var paymentNeedsRefresh: Bool = false

    // MARK: - Dependencies

    private let invoiceService: InvoiceServiceProtocol

    // MARK: - Init

    init(invoiceService: InvoiceServiceProtocol = LiveInvoiceService()) {
        self.invoiceService = invoiceService
    }

    // MARK: - Loading

    func load(id: String) async {
        guard !isLoading, !isPerformingAction else { return }
        isLoading = true
        errorMessage = nil
        lineItemsError = nil
        defer { isLoading = false }

        // Fetch the invoice and its line items concurrently — neither
        // depends on the other and the detail screen needs both.
        async let invoiceTask = invoiceService.getInvoice(id: id)
        async let lineItemsTask = invoiceService.getLineItems(invoiceId: id)

        do {
            let fetchedInvoice = try await invoiceTask
            invoice = fetchedInvoice
            paymentNeedsRefresh = false
            do {
                let fetchedLineItems = try await lineItemsTask
                lineItems = fetchedLineItems.sorted { $0.sortOrder < $1.sortOrder }
            } catch {
                lineItemsError = "Couldn't refresh invoice items. \(error.localizedDescription)"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

    }

    // MARK: - Lifecycle Actions

    /// Mark a DRAFT invoice as sent. Uses the dedicated send endpoint so the
    /// backend stamps `sent_at` and transitions the status atomically.
    func markAsSent() async {
        guard let current = invoice, current.status == .draft, !isPerformingAction, !isLoading else { return }
        isPerformingAction = true
        actionError = nil

        do {
            invoice = try await invoiceService.sendInvoice(id: current.id)
        } catch {
            actionError = error.localizedDescription
        }

        isPerformingAction = false
    }

    /// Record full payment — sets the balance to zero and status to paid.
    func markAsPaid() async {
        guard let current = invoice else { return }
        _ = await recordPayment(amount: current.amountDue)
    }

    /// Compare the last viewed balance on the server before replacing the
    /// cumulative total, so another device's payment cannot be overwritten.
    func recordPayment(amount: Decimal) async -> Bool {
        guard !paymentNeedsRefresh else {
            actionError = "Refresh the invoice before recording another payment."
            return false
        }
        guard let current = invoice, current.status != .paid, current.status != .void,
              !isPerformingAction, !isLoading else { return false }
        guard amount > 0, amount <= current.amountDue, !amount.isNaN else {
            actionError = "Enter a payment greater than zero and no more than the outstanding balance."
            return false
        }
        isPerformingAction = true
        actionError = nil
        defer { isPerformingAction = false }

        let amountPaid = current.amountPaid + amount
        let request = UpdateInvoiceRequest(
            status: amountPaid >= current.totalAmount ? .paid : .partiallyPaid,
            amountPaid: amountPaid,
            expectedAmountPaid: current.amountPaid
        )

        do {
            invoice = try await invoiceService.updateInvoice(id: current.id, request: request)
            return true
        } catch {
            switch error {
            case APIError.server(code: "CONFLICT", message: _):
                paymentNeedsRefresh = true
                actionError = error.localizedDescription
            case APIError.network, APIError.decoding, APIError.unknown,
                 APIError.server(code: "INTERNAL_ERROR", message: _):
                paymentNeedsRefresh = true
                actionError = "Couldn't confirm whether the payment was saved. Refresh and review the invoice before recording it again."
            default:
                actionError = error.localizedDescription
            }
            return false
        }
    }

    /// Keep a stale-payment sheet open while reloading the canonical balance,
    /// allowing the user to review a payment recorded on another device.
    func refreshPaymentState() async {
        guard let id = invoice?.id else { return }
        await load(id: id)
        actionError = errorMessage
    }

    /// Delete the invoice. Returns `true` on success so the caller can pop /
    /// dismiss and refresh the list.
    func delete() async -> Bool {
        guard let id = invoice?.id, !isPerformingAction, !isLoading else { return false }
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
            // Keep user-configurable numbering prefixes from creating nested
            // paths in the shared temporary directory.
            let safeNumber = invoice.invoiceNumber.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }.joined(separator: "-")
            let fileName = "\(safeNumber.isEmpty ? "Invoice" : safeNumber)-\(UUID().uuidString).pdf"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            actionError = error.localizedDescription
            return nil
        }
    }
}
