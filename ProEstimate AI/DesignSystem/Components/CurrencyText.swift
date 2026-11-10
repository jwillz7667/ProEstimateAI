import SwiftUI

struct CurrencyText: View {
    let amount: Decimal
    var font: Font = TypographyTokens.moneySmall
    var locale: Locale = .current
    var currencyCode: String = "USD"

    var body: some View {
        Text(formatted)
            .font(font)
            .monospacedDigit()
    }

    private var formatted: String {
        CurrencyDisplay.string(amount, currencyCode: currencyCode, locale: locale)
    }
}
