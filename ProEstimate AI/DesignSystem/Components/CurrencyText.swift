import SwiftUI

struct CurrencyText: View {
    let amount: Decimal
    var font: Font = TypographyTokens.moneySmall
    var locale: Locale = .current

    var body: some View {
        Text(formatted)
            .font(font)
            .monospacedDigit()
    }

    private var formatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "$0.00"
    }
}
