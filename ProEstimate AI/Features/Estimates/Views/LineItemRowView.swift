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
                        if let url = extractURL(from: item.description) {
                            HStack(spacing: 4) {
                                Text(cleanDescription(item.description))
                                    .font(TypographyTokens.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                Link(destination: url) {
                                    HStack(spacing: 2) {
                                        Image(systemName: "arrow.up.right.square")
                                            .font(.caption2)
                                        Text("Source")
                                            .font(TypographyTokens.caption2)
                                    }
                                    .foregroundStyle(ColorTokens.primaryOrange)
                                }
                            }
                        } else {
                            Text(item.description)
                                .font(TypographyTokens.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
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
            .tint(ColorTokens.accentBlue)
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

    /// Extracts the first URL from a description string.
    private func extractURL(from text: String) -> URL? {
        let parts = text.components(separatedBy: " · ")
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("http"), let url = URL(string: trimmed) {
                return url
            }
        }
        return nil
    }

    /// Removes the URL component from the description for clean display.
    private func cleanDescription(_ text: String) -> String {
        text.components(separatedBy: " · ")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("http") }
            .joined(separator: " · ")
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
