import Foundation
import Observation

@Observable
final class InvoiceListViewModel {
    // MARK: - Dependencies

    private let service: InvoiceServiceProtocol

    // MARK: - State

    var invoices: [Invoice] = []
    var searchText: String = ""
    var selectedFilter: InvoiceStatusFilter = .all
    var isLoading: Bool = false
    var errorMessage: String?

    // MARK: - Computed

    /// Filtered and searched invoices for display.
    var filteredInvoices: [Invoice] {
        var result = invoices

        // Apply status filter
        if selectedFilter != .all {
            let matchingStatuses = selectedFilter.matchingStatuses
            result = result.filter { matchingStatuses.contains($0.status) }
        }

        // Apply search text
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { invoice in
                invoice.invoiceNumber.lowercased().contains(query)
            }
        }

        return result
    }

    /// Total amount due across all unpaid invoices.
    var totalOutstanding: Decimal {
        invoices
            .filter { $0.status != .paid && $0.status != .void }
            .reduce(Decimal.zero) { $0 + $1.amountDue }
    }

    /// Count of overdue invoices.
    var overdueCount: Int {
        invoices.filter { $0.status == .overdue || $0.isPastDue }.count
    }

    // MARK: - Init

    init(service: InvoiceServiceProtocol = MockInvoiceService()) {
        self.service = service
    }

    // MARK: - Actions

    func loadInvoices() async {
        isLoading = true
        errorMessage = nil
        do {
            invoices = try await service.listInvoices()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func deleteInvoice(id: String) async {
        do {
            try await service.deleteInvoice(id: id)
            invoices.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
