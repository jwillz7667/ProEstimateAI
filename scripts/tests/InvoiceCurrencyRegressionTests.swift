import Foundation

enum StatusBadge { enum Style { case neutral, warning, error, success, info } }

@main
struct InvoiceCurrencyRegressionTests {
    struct Failure: Error { let message: String }
    static func main() throws {
        let json = #"{"id":"invoice","project_id":"project","company_id":"company","client_id":"client","invoice_number":"INV-1","status":"sent","subtotal":100,"tax_amount":0,"discount_amount":0,"total_amount":100,"amount_paid":0,"amount_due":100,"currency_code":"USD","created_at":"2026-11-03T00:00:00Z","updated_at":"2026-11-03T00:00:00Z"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        func invoice(_ currency: String, _ status: String = "sent", _ due: String = "100") throws -> Invoice {
            let input = json.replacingOccurrences(of: #""USD""#, with: "\"\(currency)\"")
                .replacingOccurrences(of: #""sent""#, with: "\"\(status)\"")
                .replacingOccurrences(of: #""amount_due":100"#, with: "\"amount_due\":\(due)")
            return try decoder.decode(Invoice.self, from: Data(input.utf8))
        }
        var checks = 0
        func expect(_ condition: Bool, _ message: String) throws {
            checks += 1
            if !condition { throw Failure(message: message) }
        }
        let invoices = try [invoice("USD"), invoice(" usd ", "partially_paid", "25.01"), invoice("EUR"), invoice("USD", "draft"), invoice("USD", "paid"), invoice("USD", "void"), invoice("CAD", "sent", "0")]
        let balances = InvoiceCurrencyBalance.outstanding(in: invoices)
        try expect(balances.map(\.currencyCode) == ["EUR", "USD"], "Do not combine different currencies or include zero balances")
        try expect(balances.last?.amount == Decimal(string: "125.01"), "Draft, paid and void invoices must not inflate outstanding debt")
        try expect(InvoiceCurrencyBalance.outstanding(in: []).isEmpty, "An empty workspace must not invent debt")
        try expect(CurrencyDisplay.code(nil) == "USD" && CurrencyDisplay.code(" ") == "USD", "Legacy currency defaults remain USD")
        let germanUSD = CurrencyDisplay.string(100, currencyCode: "USD", locale: Locale(identifier: "de_DE"))
        try expect(!germanUSD.contains("€") && germanUSD.contains("$"), "Device region must not relabel USD as EUR")
        let americanEUR = CurrencyDisplay.string(100, currencyCode: "EUR", locale: Locale(identifier: "en_US"))
        try expect(americanEUR.contains("€") && !americanEUR.contains("$"), "Use the invoice currency with localized separators")
        print("PASS: \(checks) invoice currency checks")
    }
}
