import Foundation

struct InvoiceCurrencyBalance: Identifiable, Equatable, Sendable {
    let currencyCode: String
    let amount: Decimal
    var id: String { currencyCode }

    /// Unsent drafts are proposed bills; they are not money currently owed.
    static func outstanding(in invoices: [Invoice]) -> [InvoiceCurrencyBalance] {
        var balances: [String: Decimal] = [:]
        for invoice in invoices where invoice.status != .draft && invoice.status != .paid && invoice.status != .void && invoice.amountDue > 0 {
            balances[CurrencyDisplay.code(invoice.currencyCode), default: 0] += invoice.amountDue
        }
        return balances.keys.sorted().map { InvoiceCurrencyBalance(currencyCode: $0, amount: balances[$0] ?? 0) }
    }
}
