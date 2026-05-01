import SwiftUI

/// A selectable category tile rendered with a curated photographic hero.
///
/// The card is composed in two horizontal bands:
/// 1. A 4:3 photo hero pulled from `Assets.xcassets/CategoryTiles/`, with
///    a bottom-aligned dark gradient that anchors the floating label and
///    keeps text legible across light and dark thumbnails.
/// 2. A bottom strip carrying the category name in a high-weight rounded
///    font; selecting the tile flips that strip's tint to brand orange.
///
/// Selection state is communicated through three reinforcing channels:
/// stroke (1.5pt → 3pt orange ring), corner badge (animated check), and
/// label color. This redundancy is deliberate so the cue is unmistakable
/// regardless of the underlying photo, even for users with reduced
/// contrast or color-vision differences.
struct ProjectTypeCard: View {
    let projectType: Project.ProjectType
    let isSelected: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .caption) private var labelHeight: CGFloat = 36

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                heroImage
                labelStrip
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.card, style: .continuous))
            .overlay(selectionStroke)
            .overlay(alignment: .topTrailing) { selectionBadge }
            .background(
                ColorTokens.surface,
                in: RoundedRectangle(cornerRadius: RadiusTokens.card, style: .continuous)
            )
            .shadow(
                color: .black.opacity(isSelected ? 0.20 : 0.10),
                radius: isSelected ? 10 : 6,
                x: 0,
                y: isSelected ? 5 : 3
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isSelected)
        }
        .buttonStyle(ProjectTypeCardButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(projectType.displayName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isSelected ? "Currently selected" : "Tap to select")
    }

    // MARK: - Hero Image

    private var heroImage: some View {
        Image(projectType.thumbnailAssetName)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .aspectRatio(4 / 3, contentMode: .fill)
            .clipped()
            .overlay {
                LinearGradient(
                    colors: [
                        .black.opacity(0.0),
                        .black.opacity(0.18),
                        .black.opacity(0.55),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .accessibilityHidden(true)
    }

    // MARK: - Label Strip

    private var labelStrip: some View {
        Text(projectType.displayName)
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(isSelected ? ColorTokens.primaryOrange : ColorTokens.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, SpacingTokens.xs)
            .frame(maxWidth: .infinity)
            .frame(minHeight: labelHeight)
            .background(
                isSelected
                    ? ColorTokens.primaryOrange.opacity(0.10)
                    : Color.clear
            )
    }

    // MARK: - Selection Affordances

    @ViewBuilder
    private var selectionStroke: some View {
        RoundedRectangle(cornerRadius: RadiusTokens.card, style: .continuous)
            .strokeBorder(
                isSelected ? ColorTokens.primaryOrange : ColorTokens.subtleBorder.opacity(0.6),
                lineWidth: isSelected ? 2.5 : 1
            )
    }

    @ViewBuilder
    private var selectionBadge: some View {
        if isSelected {
            ZStack {
                Circle()
                    .fill(ColorTokens.primaryOrange)
                    .frame(width: 26, height: 26)
                    .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)

                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .padding(SpacingTokens.xs)
            .transition(.scale.combined(with: .opacity))
        }
    }
}

// MARK: - Button Style

/// Subtle press-down feedback that respects the parent's selection
/// scaling. We dim and shrink slightly on press without fighting the
/// spring animation that runs on selection toggle.
private struct ProjectTypeCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        let columns = [
            GridItem(.flexible(), spacing: SpacingTokens.sm),
            GridItem(.flexible(), spacing: SpacingTokens.sm),
            GridItem(.flexible(), spacing: SpacingTokens.sm),
        ]
        LazyVGrid(columns: columns, spacing: SpacingTokens.sm) {
            ForEach(Project.ProjectType.allCases, id: \.self) { type in
                ProjectTypeCard(
                    projectType: type,
                    isSelected: type == .kitchen
                ) {}
            }
        }
        .padding()
    }
    .background(ColorTokens.background)
}
