import Foundation
import Observation

@Observable
final class InvoiceViewModel {
    // MARK: - Dependencies

    private let service: InvoiceServiceProtocol

    // MARK: - State

    var invoice: Invoice?
    var lineItems: [InvoiceLineItem] = []
    var project: Project?
    var client: Client?
    var company: Company?

    var isLoading: Bool = false
    var isSending: Bool = false
    var isMarkingPaid: Bool = false
    var errorMessage: String?
    var successMessage: String?

    // MARK: - Computed

    /// Amount still due on the invoice.
    var computedAmountDue: Decimal {
        guard let invoice else { return 0 }
        return invoice.totalAmount - invoice.amountPaid
    }

    /// Payment progress as percentage string.
    var paymentProgressText: String {
        guard let invoice, invoice.totalAmount > 0 else { return "0%" }
        let progress = NSDecimalNumber(decimal: invoice.amountPaid / invoice.totalAmount * 100)
        return "\(progress.intValue)%"
    }

    /// Whether the invoice can be sent.
    var canSend: Bool {
        invoice?.status == .draft
    }

    /// Whether the invoice can be marked as paid.
    var canMarkPaid: Bool {
        guard let status = invoice?.status else { return false }
        return status == .sent || status == .viewed || status == .partiallyPaid || status == .overdue
    }

    /// Formatted due date.
    var formattedDueDate: String? {
        guard let dueDate = invoice?.dueDate else { return nil }
        return dueDate.formatted(as: .invoiceDate)
    }

    /// Formatted sent date.
    var formattedSentDate: String? {
        guard let sentAt = invoice?.sentAt else { return nil }
        return sentAt.formatted(as: .invoiceDate)
    }

    /// Formatted paid date.
    var formattedPaidDate: String? {
        guard let paidAt = invoice?.paidAt else { return nil }
        return paidAt.formatted(as: .invoiceDate)
    }

    /// Formatted invoice date.
    var formattedInvoiceDate: String {
        let date = invoice?.createdAt ?? Date()
        return date.formatted(as: .invoiceDate)
    }

    /// Company full address.
    var companyAddress: String? {
        guard let company else { return nil }
        let parts = [company.address, company.city, company.state, company.zip].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ", ")
    }

    /// Client full address.
    var clientAddress: String? {
        client?.formattedAddress
    }

    /// Status badge style for the invoice.
    var statusBadgeStyle: StatusBadge.Style {
        guard let status = invoice?.status else { return .neutral }
        switch status {
        case .draft: return .neutral
        case .sent, .viewed: return .info
        case .partiallyPaid: return .warning
        case .paid: return .success
        case .overdue: return .error
        case .void: return .neutral
        }
    }

    // MARK: - Init

    init(service: InvoiceServiceProtocol = MockInvoiceService()) {
        self.service = service
    }

    // MARK: - Actions

    func loadInvoice(id: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let loadedInvoice = try await service.getInvoice(id: id)
            invoice = loadedInvoice

            // Load related data in parallel
            async let lineItemsTask = service.getInvoiceLineItems(invoiceId: loadedInvoice.id)
            async let projectTask = service.getInvoiceProject(projectId: loadedInvoice.projectId)
            async let clientTask = service.getInvoiceClient(clientId: loadedInvoice.clientId)
            async let companyTask = service.getInvoiceCompany(companyId: loadedInvoice.companyId)

            let (loadedItems, loadedProject, loadedClient, loadedCompany) = try await (
                lineItemsTask, projectTask, clientTask, companyTask
            )

            lineItems = loadedItems.sorted { $0.sortOrder < $1.sortOrder }
            project = loadedProject
            client = loadedClient
            company = loadedCompany
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func createFromEstimate(estimateId: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let created = try await service.createFromEstimate(estimateId: estimateId)
            await loadInvoice(id: created.id)
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func sendInvoice() async {
        guard let invoiceId = invoice?.id else { return }
        isSending = true
        errorMessage = nil
        do {
            invoice = try await service.sendInvoice(id: invoiceId)
            successMessage = "Invoice sent successfully."
        } catch {
            errorMessage = error.localizedDescription
        }
        isSending = false
    }

    func markAsPaid() async {
        guard let invoiceId = invoice?.id else { return }
        isMarkingPaid = true
        errorMessage = nil
        do {
            invoice = try await service.markAsPaid(id: invoiceId)
            successMessage = "Invoice marked as paid."
        } catch {
            errorMessage = error.localizedDescription
        }
        isMarkingPaid = false
    }
}
