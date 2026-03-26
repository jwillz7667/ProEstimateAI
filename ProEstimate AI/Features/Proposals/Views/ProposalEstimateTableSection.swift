import SwiftUI

struct ProposalEstimateTableSection: View {
    let materialItems: [EstimateLineItem]
    let laborItems: [EstimateLineItem]
    let otherItems: [EstimateLineItem]
    let estimate: Estimate?

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.md) {
            Text("Estimate Breakdown")
                .font(TypographyTokens.title3)
                .padding(.horizontal, SpacingTokens.lg)

            // Table header
            tableHeader
                .padding(.horizontal, SpacingTokens.lg)

            Divider()
                .padding(.horizontal, SpacingTokens.lg)

            // Materials section
            if !materialItems.isEmpty {
                categorySection(
                    title: "Materials",
                    icon: "shippingbox",
                    color: ColorTokens.primaryOrange,
                    items: materialItems,
                    subtotal: estimate?.subtotalMaterials ?? 0
                )
            }

            // Labor section
            if !laborItems.isEmpty {
                categorySection(
                    title: "Labor",
                    icon: "hammer",
                    color: .blue,
                    items: laborItems,
                    subtotal: estimate?.subtotalLabor ?? 0
                )
            }

            // Other section
            if !otherItems.isEmpty {
                categorySection(
                    title: "Other",
                    icon: "ellipsis.circle",
                    color: .purple,
                    items: otherItems,
                    subtotal: estimate?.subtotalOther ?? 0
                )
            }

            // Grand total
            if let estimate {
                Divider()
                    .padding(.horizontal, SpacingTokens.lg)

                grandTotalSection(estimate: estimate)
                    .padding(.horizontal, SpacingTokens.lg)
            }
        }
        .padding(.vertical, SpacingTokens.md)
    }

    // MARK: - Subviews

    private var tableHeader: some View {
        HStack {
            Text("Item")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Qty")
                .frame(width: 40, alignment: .trailing)
            Text("Unit")
                .frame(width: 50, alignment: .center)
            Text("Price")
                .frame(width: 70, alignment: .trailing)
            Text("Total")
                .frame(width: 80, alignment: .trailing)
        }
        .font(TypographyTokens.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
    }

    private func categorySection(
        title: String,
        icon: String,
        color: Color,
        items: [EstimateLineItem],
        subtotal: Decimal
    ) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
            // Category header
            HStack(spacing: SpacingTokens.xs) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(title)
                    .font(TypographyTokens.subheadline)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, SpacingTokens.lg)
            .padding(.top, SpacingTokens.xs)

            // Line items
            ForEach(items) { item in
                lineItemRow(item)
                    .padding(.horizontal, SpacingTokens.lg)
            }

            // Subtotal
            HStack {
                Spacer()
                Text("\(title) Subtotal")
                    .font(TypographyTokens.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                CurrencyText(amount: subtotal, font: TypographyTokens.moneySmall)
                    .frame(width: 80, alignment: .trailing)
            }
            .padding(.horizontal, SpacingTokens.lg)
            .padding(.top, SpacingTokens.xxs)

            Divider()
                .padding(.horizontal, SpacingTokens.lg)
        }
    }

    private func lineItemRow(_ item: EstimateLineItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(TypographyTokens.caption)
                    .lineLimit(1)
                if let description = item.description {
                    Text(description)
                        .font(TypographyTokens.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(formattedQuantity(item.quantity))
                .font(TypographyTokens.caption)
                .frame(width: 40, alignment: .trailing)

            Text(item.unit)
                .font(TypographyTokens.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .center)

            CurrencyText(amount: item.unitCost, font: TypographyTokens.moneyCaption)
                .frame(width: 70, alignment: .trailing)

            CurrencyText(amount: item.lineTotal, font: TypographyTokens.moneyCaption)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private func grandTotalSection(estimate: Estimate) -> some View {
        VStack(spacing: SpacingTokens.xs) {
            if estimate.taxAmount > 0 {
                HStack {
                    Spacer()
                    Text("Tax")
                        .font(TypographyTokens.subheadline)
                        .foregroundStyle(.secondary)
                    CurrencyText(amount: estimate.taxAmount, font: TypographyTokens.moneySmall)
                        .foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .trailing)
                }
            }

            if estimate.discountAmount > 0 {
                HStack {
                    Spacer()
                    Text("Discount")
                        .font(TypographyTokens.subheadline)
                        .foregroundStyle(ColorTokens.success)
                    Text("-")
                        .foregroundStyle(ColorTokens.success)
                    CurrencyText(amount: estimate.discountAmount, font: TypographyTokens.moneySmall)
                        .foregroundStyle(ColorTokens.success)
                        .frame(width: 80, alignment: .trailing)
                }
            }

            Divider()

            HStack {
                Spacer()
                Text("Grand Total")
                    .font(TypographyTokens.headline)
                CurrencyText(amount: estimate.totalAmount, font: TypographyTokens.moneyLarge)
                    .foregroundStyle(ColorTokens.primaryOrange)
                    .frame(width: 120, alignment: .trailing)
            }
        }
        .padding(.vertical, SpacingTokens.xs)
    }

    // MARK: - Helpers

    private func formattedQuantity(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        if value == Decimal(number.intValue) {
            return "\(number.intValue)"
        }
        return String(format: "%.1f", number.doubleValue)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        ProposalEstimateTableSection(
            materialItems: [.sample],
            laborItems: MockEstimateService.sampleLineItems.filter { $0.category == .labor },
            otherItems: MockEstimateService.sampleLineItems.filter { $0.category == .other },
            estimate: .sample
        )
    }
}
