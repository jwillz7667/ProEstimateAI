import SwiftUI

struct EstimateTotalsView: View {
    let subtotalMaterials: Decimal
    let subtotalLabor: Decimal
    let subtotalOther: Decimal
    let taxAmount: Decimal
    @Binding var discountAmount: Decimal
    let grandTotal: Decimal

    @State private var discountText: String = ""
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            VStack(spacing: SpacingTokens.xs) {
                // Collapsed: just grand total row
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        Text("Total")
                            .font(TypographyTokens.headline)
                            .foregroundStyle(.primary)

                        Spacer()

                        CurrencyText(amount: grandTotal, font: TypographyTokens.moneyLarge)
                            .foregroundStyle(ColorTokens.primaryOrange)
                    }
                }

                if isExpanded {
                    VStack(spacing: SpacingTokens.xs) {
                        Divider()

                        totalsRow(label: "Materials", amount: subtotalMaterials, icon: "shippingbox")
                        totalsRow(label: "Labor", amount: subtotalLabor, icon: "hammer")
                        totalsRow(label: "Other", amount: subtotalOther, icon: "ellipsis.circle")

                        Divider()

                        totalsRow(label: "Tax", amount: taxAmount, icon: "building.columns")

                        discountRow

                        Divider()
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, SpacingTokens.md)
            .padding(.vertical, SpacingTokens.sm)
            .background(.ultraThinMaterial)
        }
        .onAppear {
            discountText = discountAmount > 0
                ? "\(NSDecimalNumber(decimal: discountAmount).doubleValue)"
                : ""
        }
    }

    // MARK: - Subviews

    private func totalsRow(label: String, amount: Decimal, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(label)
                .font(TypographyTokens.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            CurrencyText(amount: amount, font: TypographyTokens.moneySmall)
                .foregroundStyle(.secondary)
        }
    }

    private var discountRow: some View {
        HStack {
            Image(systemName: "tag")
                .font(.caption)
                .foregroundStyle(ColorTokens.success)
                .frame(width: 20)

            Text("Discount")
                .font(TypographyTokens.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 2) {
                Text("-$")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.success)

                TextField("0.00", text: $discountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .font(TypographyTokens.moneySmall)
                    .foregroundStyle(ColorTokens.success)
                    .onChange(of: discountText) { _, newValue in
                        if let value = Decimal(string: newValue), value >= 0 {
                            discountAmount = value
                        } else if newValue.isEmpty {
                            discountAmount = 0
                        }
                    }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Spacer()
        EstimateTotalsView(
            subtotalMaterials: 12500,
            subtotalLabor: 8000,
            subtotalOther: 500,
            taxAmount: 1732.50,
            discountAmount: .constant(0),
            grandTotal: 22732.50
        )
    }
}
