import SwiftUI

/// Snap-paged horizontal carousel of premade prompt suggestions.
///
/// Each card is selectable; tapping toggles between selected and not
/// selected. The selected card's prompt is combined with the user's
/// custom-instruction text at submission time.
struct PromptCardCarousel: View {
    let cards: [PromptCard]
    let selectedCardId: String?
    let onSelect: (PromptCard) -> Void

    /// Width fraction of each card relative to the container. ~70% leaves
    /// a clear peek of the next card so users discover the swipe.
    private let cardWidthFraction: CGFloat = 0.7
    private let cardHeight: CGFloat = 140
    private let cardSpacing: CGFloat = 16

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: cardSpacing) {
                ForEach(cards) { card in
                    Button {
                        onSelect(card)
                    } label: {
                        cardContent(card)
                    }
                    .buttonStyle(.plain)
                    .containerRelativeFrame(.horizontal) { length, _ in
                        length * cardWidthFraction
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(card.title). \(card.subtitle)")
                    .accessibilityValue(selectedCardId == card.id ? "Selected" : "Not selected")
                    .accessibilityAddTraits(.isButton)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, SpacingTokens.md)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
    }

    // MARK: - Card

    private func cardContent(_ card: PromptCard) -> some View {
        let isSelected = selectedCardId == card.id

        return VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            HStack(spacing: SpacingTokens.xs) {
                Image(systemName: card.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ColorTokens.primaryOrange)
                    .frame(width: 32, height: 32)
                    .background(
                        ColorTokens.primaryOrange.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: RadiusTokens.small)
                    )

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(ColorTokens.primaryOrange)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .font(TypographyTokens.headline)
                    .foregroundStyle(ColorTokens.primaryText)
                    .lineLimit(1)

                Text(card.subtitle)
                    .font(TypographyTokens.caption2)
                    .foregroundStyle(ColorTokens.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SpacingTokens.md)
        .frame(height: cardHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .background(
            isSelected
                ? AnyShapeStyle(ColorTokens.primaryOrange.opacity(0.08))
                : AnyShapeStyle(ColorTokens.inputBackground),
            in: RoundedRectangle(cornerRadius: RadiusTokens.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: RadiusTokens.card)
                .strokeBorder(
                    isSelected ? ColorTokens.primaryOrange : ColorTokens.subtleBorder,
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }
}
