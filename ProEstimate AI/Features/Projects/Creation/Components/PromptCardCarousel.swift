import SwiftUI

/// Snap-paged horizontal carousel of premade prompt suggestions.
///
/// Each card is a photographic tile pulled from
/// `Assets.xcassets/StyleCards/<Category>/` with a frosted text overlay
/// anchored to the bottom. Tapping toggles selection; the selected
/// card's prompt is combined with the user's custom-instruction text
/// at submission.
///
/// Layout: cards take ~64% of viewport width so the next card peeks
/// past the trailing edge — a hard-coded scroll affordance that signals
/// "swipe me" without paging dots. The card is intentionally compact so
/// the carousel doesn't dominate the step's vertical real estate; the
/// photo carries the visual weight, the text is a quiet caption beneath
/// the bottom gradient.
struct PromptCardCarousel: View {
    let cards: [PromptCard]
    let selectedCardId: String?
    let onSelect: (PromptCard) -> Void

    private let cardWidthFraction: CGFloat = 0.62
    private let cardHeight: CGFloat = 180
    /// Selected card shadow is radius 12 / y 6 → ~12pt horizontal
    /// visible reach per side; unselected adds another ~6pt from its
    /// own shadow. 36pt clears the combined ~18pt with margin so the
    /// gutter reads as deliberate negative space rather than two
    /// touching cards.
    private let cardSpacing: CGFloat = 36
    private let edgeMargin: CGFloat = SpacingTokens.md

    var body: some View {
        // GeometryReader-driven layout. The previous version relied on
        // `.containerRelativeFrame(.horizontal) { length, _ in length * 0.64 }`
        // composed with `.contentMargins(...)` and `.scrollClipDisabled()`,
        // which produced visually-touching cards on iPhone-class devices —
        // the resolved `length` and the snap-aligned offset interacted in a
        // way that swallowed the LazyHStack spacing. Switching to explicit
        // `.frame(width:)` driven by the parent width is deterministic:
        // card width and gutter are exactly what we set, full stop.
        GeometryReader { proxy in
            let cardWidth = proxy.size.width * cardWidthFraction

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: cardSpacing) {
                    ForEach(cards) { card in
                        Button {
                            onSelect(card)
                        } label: {
                            cardContent(card)
                        }
                        .buttonStyle(PromptCardButtonStyle())
                        .frame(width: cardWidth)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(card.title). \(card.subtitle)")
                        .accessibilityValue(selectedCardId == card.id ? "Selected" : "Not selected")
                        .accessibilityAddTraits(.isButton)
                    }
                }
                .padding(.horizontal, edgeMargin)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
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
        VStack(alignment: .leading, spacing: 2) {
            Text(card.title)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)

            Text(card.subtitle)
                .font(TypographyTokens.caption2)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)
        }
        .padding(.horizontal, SpacingTokens.sm)
        .padding(.vertical, SpacingTokens.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
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
                        .frame(width: 26, height: 26)
                        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .heavy))
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
