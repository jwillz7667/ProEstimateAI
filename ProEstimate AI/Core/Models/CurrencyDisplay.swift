import Foundation

enum CurrencyDisplay {
    static func code(_ value: String?) -> String {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        return normalized.isEmpty ? "USD" : normalized
    }

    static func string(_ amount: Decimal, currencyCode: String, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = code(currencyCode)
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount) \(code(currencyCode))"
    }
}
