import SwiftUI

/// Snap-paged horizontal carousel of premade prompt suggestions.
///
/// Each card is a photographic tile pulled from
/// `Assets.xcassets/StyleCards/<Category>/` with a frosted text overlay
/// anchored to the bottom. Tapping toggles selection; the selected
/// card's prompt is combined with the user's custom-instruction text
/// at submission.
///
/// Layout: cards take ~74% of viewport width so the next card peeks past
/// the trailing edge — a hard-coded scroll affordance that signals
/// "swipe me" without paging dots. Cards are tall (3:2 hero + label)
/// so the photo reads at-a-glance.
struct PromptCardCarousel: View {
    let cards: [PromptCard]
    let selectedCardId: String?
    let onSelect: (PromptCard) -> Void

    private let cardWidthFraction: CGFloat = 0.74
    private let cardHeight: CGFloat = 220
    private let cardSpacing: CGFloat = 14

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: cardSpacing) {
                ForEach(cards) { card in
                    Button {
                        onSelect(card)
                    } label: {
                        cardContent(card)
                    }
                    .buttonStyle(PromptCardButtonStyle())
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
        .frame(height: cardHeight)
    }

    // MARK: - Card

    @ViewBuilder
    private func cardContent(_ card: PromptCard) -> some View {
        let isSelected = selectedCardId == card.id

        ZStack(alignment: .bottomLeading) {
            heroImage(for: card)
            gradientOverlay
            textOverlay(card)
            if isSelected {
                selectionOverlay
            }
        }
        .frame(height: cardHeight)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: RadiusTokens.card, style: .continuous)
                .strokeBorder(
                    isSelected ? ColorTokens.primaryOrange : ColorTokens.subtleBorder.opacity(0.4),
                    lineWidth: isSelected ? 2.5 : 1
                )
        )
        .shadow(
            color: .black.opacity(isSelected ? 0.22 : 0.10),
            radius: isSelected ? 12 : 6,
            x: 0,
            y: isSelected ? 6 : 3
        )
        .scaleEffect(isSelected ? 1.015 : 1.0)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isSelected)
    }

    // MARK: - Layers

    private func heroImage(for card: PromptCard) -> some View {
        Image(card.imageAssetName)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: cardHeight)
            .clipped()
            .accessibilityHidden(true)
    }

    /// Top-to-bottom darkening gradient that gives the text overlay a
    /// legible contrast surface regardless of the photo's content. The
    /// stops are tuned so the upper third of the image stays cinematic
    /// while the lower third reaches near-opaque black.
    private var gradientOverlay: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.0), location: 0.0),
                .init(color: .black.opacity(0.10), location: 0.35),
                .init(color: .black.opacity(0.55), location: 0.7),
                .init(color: .black.opacity(0.78), location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func textOverlay(_ card: PromptCard) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
            iconChip(card)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)

                Text(card.subtitle)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
            }
        }
        .padding(SpacingTokens.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Floating capsule chip carrying the card's SF Symbol — sits at the
    /// top-leading corner of the photo so it reads regardless of how
    /// dark/light the underlying image is.
    private func iconChip(_ card: PromptCard) -> some View {
        Image(systemName: card.icon)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(ColorTokens.primaryOrange)
            .frame(width: 30, height: 30)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: RadiusTokens.small, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.small, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            )
    }

    /// Top-trailing checkmark badge that confirms selection without
    /// fighting the photo's compositional focus. Mirrors the selection
    /// affordance on `ProjectTypeCard` for visual continuity across the
    /// two creation steps.
    private var selectionOverlay: some View {
        VStack {
            HStack {
                Spacer()
                ZStack {
                    Circle()
                        .fill(ColorTokens.primaryOrange)
                        .frame(width: 30, height: 30)
                        .shadow(color: .black.opacity(0.25), radius: 5, x: 0, y: 2)
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .padding(SpacingTokens.xs)
                .transition(.scale.combined(with: .opacity))
            }
            Spacer()
        }
    }
}

// MARK: - Button Style

private struct PromptCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    PromptCardCarousel(
        cards: PromptCard.suggestions(for: .kitchen),
        selectedCardId: "kitchen.contemporary",
        onSelect: { _ in }
    )
    .padding(.vertical)
    .background(ColorTokens.background)
}
