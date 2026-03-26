import SwiftUI

struct InvoiceTotalsSection: View {
    let subtotal: Decimal
    let taxAmount: Decimal
    let totalAmount: Decimal
    let amountPaid: Decimal
    let amountDue: Decimal
    let isPaid: Bool

    var body: some View {
        ZStack {
            VStack(spacing: SpacingTokens.xs) {
                totalsRow(label: "Subtotal", amount: subtotal)
                totalsRow(label: "Tax", amount: taxAmount)

                Divider()

                totalsRow(label: "Total", amount: totalAmount, isEmphasized: true)

                if amountPaid > 0 {
                    Divider()

                    HStack {
                        Text("Amount Paid")
                            .font(TypographyTokens.subheadline)
                            .foregroundStyle(ColorTokens.success)
                        Spacer()
                        CurrencyText(amount: amountPaid, font: TypographyTokens.moneySmall)
                            .foregroundStyle(ColorTokens.success)
                    }
                }

                Divider()

                // Amount Due - emphasized
                HStack {
                    Text("Amount Due")
                        .font(TypographyTokens.headline)
                        .fontWeight(.bold)
                    Spacer()
                    CurrencyText(
                        amount: amountDue,
                        font: TypographyTokens.moneyLarge
                    )
                    .foregroundStyle(isPaid ? ColorTokens.success : ColorTokens.primaryOrange)
                }
            }
            .padding(SpacingTokens.lg)
            .glassCard()

            // PAID stamp overlay
            if isPaid {
                paidStamp
            }
        }
    }

    // MARK: - Subviews

    private func totalsRow(label: String, amount: Decimal, isEmphasized: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(isEmphasized ? TypographyTokens.headline : TypographyTokens.subheadline)
                .foregroundStyle(isEmphasized ? .primary : .secondary)
            Spacer()
            CurrencyText(
                amount: amount,
                font: isEmphasized ? TypographyTokens.moneyMedium : TypographyTokens.moneySmall
            )
            .foregroundStyle(isEmphasized ? .primary : .secondary)
        }
    }

    private var paidStamp: some View {
        Text("PAID")
            .font(.system(size: 48, weight: .black, design: .rounded))
            .foregroundStyle(ColorTokens.success.opacity(0.2))
            .rotationEffect(.degrees(-20))
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .strokeBorder(ColorTokens.success.opacity(0.2), lineWidth: 4)
                    .frame(width: 180, height: 70)
                    .rotationEffect(.degrees(-20))
            )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: SpacingTokens.lg) {
        InvoiceTotalsSection(
            subtotal: 21000,
            taxAmount: 1732.50,
            totalAmount: 22732.50,
            amountPaid: 11366.25,
            amountDue: 11366.25,
            isPaid: false
        )

        InvoiceTotalsSection(
            subtotal: 14300,
            taxAmount: 1179.75,
            totalAmount: 15479.75,
            amountPaid: 15479.75,
            amountDue: 0,
            isPaid: true
        )
    }
    .padding()
}
