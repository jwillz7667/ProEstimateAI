import SwiftUI

struct EstimateSectionView: View {
    let category: EstimateLineItem.Category
    let items: [LineItemDraft]
    let subtotal: Decimal
    @Binding var isExpanded: Bool
    let onAddItem: () -> Void
    let onEditItem: (LineItemDraft) -> Void
    let onDuplicateItem: (String) -> Void
    let onDeleteItem: (String) -> Void
    let onMoveItem: (IndexSet, Int) -> Void

    var body: some View {
        Section {
            if isExpanded {
                if items.isEmpty {
                    emptyCategoryView
                } else {
                    ForEach(items) { item in
                        LineItemRowView(
                            item: item,
                            onEdit: { onEditItem(item) },
                            onDuplicate: { onDuplicateItem(item.id) },
                            onDelete: { onDeleteItem(item.id) }
                        )
                    }
                    .onMove { from, to in
                        onMoveItem(from, to)
                    }
                }

                Button {
                    onAddItem()
                } label: {
                    Label("Add \(category.rawValue.capitalized) Item", systemImage: "plus.circle")
                        .font(TypographyTokens.subheadline)
                        .foregroundStyle(ColorTokens.primaryOrange)
                }
                .padding(.vertical, SpacingTokens.xxs)
            }
        } header: {
            sectionHeader
        }
    }

    // MARK: - Subviews

    private var sectionHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                isExpanded.toggle()
            }
        } label: {
            HStack {
                Image(systemName: categoryIcon)
                    .font(.body)
                    .foregroundStyle(categoryColor)
                    .frame(width: 24)

                Text(category.rawValue.capitalized)
                    .font(TypographyTokens.headline)
                    .foregroundStyle(.primary)

                Text("(\(items.count))")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                CurrencyText(amount: subtotal, font: TypographyTokens.moneySmall)
                    .foregroundStyle(.secondary)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var emptyCategoryView: some View {
        HStack {
            Spacer()
            VStack(spacing: SpacingTokens.xxs) {
                Text("No \(category.rawValue) items")
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(.secondary)
                Text("Tap + to add items")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, SpacingTokens.md)
            Spacer()
        }
    }

    // MARK: - Helpers

    private var categoryIcon: String {
        switch category {
        case .materials: "shippingbox"
        case .labor: "hammer"
        case .other: "ellipsis.circle"
        }
    }

    private var categoryColor: Color {
        switch category {
        case .materials: ColorTokens.primaryOrange
        case .labor: ColorTokens.accentBlue
        case .other: ColorTokens.accentPurple
        }
    }
}

// MARK: - Preview

#Preview {
    List {
        EstimateSectionView(
            category: .materials,
            items: [LineItemDraft(from: .sample)],
            subtotal: 4387.50,
            isExpanded: .constant(true),
            onAddItem: {},
            onEditItem: { _ in },
            onDuplicateItem: { _ in },
            onDeleteItem: { _ in },
            onMoveItem: { _, _ in }
        )
    }
    .listStyle(.insetGrouped)
}
