import SwiftUI

struct LineItemRowView: View {
    let item: LineItemDraft
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(TypographyTokens.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)

                    if !item.description.isEmpty {
                        Text(item.description)
                            .font(TypographyTokens.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                CurrencyText(amount: item.lineTotal, font: TypographyTokens.moneySmall)
            }

            HStack(spacing: SpacingTokens.sm) {
                quantityLabel

                if item.markupPercent > 0 {
                    Label("\(NSDecimalNumber(decimal: item.markupPercent).intValue)% markup",
                          systemImage: "percent")
                        .font(TypographyTokens.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .padding(.vertical, SpacingTokens.xxs)
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                onDuplicate()
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
            .tint(ColorTokens.primaryOrange)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .onTapGesture {
            onEdit()
        }
    }

    // MARK: - Subviews

    private var quantityLabel: some View {
        HStack(spacing: 2) {
            Text(formattedQuantity)
                .font(TypographyTokens.caption)
                .foregroundStyle(.secondary)

            Text("x")
                .font(TypographyTokens.caption2)
                .foregroundStyle(.tertiary)

            CurrencyText(amount: item.unitCost, font: TypographyTokens.moneyCaption)
                .foregroundStyle(.secondary)

            Text("/\(item.unit.displayName.lowercased())")
                .font(TypographyTokens.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var formattedQuantity: String {
        let number = NSDecimalNumber(decimal: item.quantity)
        if item.quantity == item.quantity.rounded(0) {
            return "\(number.intValue)"
        }
        return "\(number.doubleValue)"
    }
}

// MARK: - Decimal rounding helper

private extension Decimal {
    func rounded(_ scale: Int) -> Decimal {
        var result = Decimal()
        var mutableSelf = self
        NSDecimalRound(&result, &mutableSelf, scale, .plain)
        return result
    }
}

// MARK: - Preview

#Preview {
    List {
        LineItemRowView(
            item: LineItemDraft(from: .sample),
            onEdit: {},
            onDuplicate: {},
            onDelete: {}
        )
    }
    .listStyle(.plain)
}
