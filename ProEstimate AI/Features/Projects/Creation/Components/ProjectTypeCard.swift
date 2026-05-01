import SwiftUI

/// A selectable category tile rendered with a curated photographic hero.
///
/// The card is composed in two horizontal bands:
/// 1. A 4:3 photo hero pulled from `Assets.xcassets/CategoryTiles/`,
///    rendered inside a `Color.clear` aspect-ratio container so the
///    underlying portrait source image (4:5) gets center-cropped to
///    landscape proportions instead of inflating the tile to its
///    intrinsic dimensions.
/// 2. A compact bottom strip carrying the category name in a rounded
///    font; selecting the tile flips that strip's tint to brand orange.
///
/// Selection state is communicated through three reinforcing channels:
/// stroke (1pt → 2.5pt orange ring), corner badge (animated check), and
/// label color. This redundancy is deliberate so the cue is unmistakable
/// regardless of the underlying photo, even for users with reduced
/// contrast or color-vision differences.
struct ProjectTypeCard: View {
    let projectType: Project.ProjectType
    let isSelected: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .caption2) private var labelHeight: CGFloat = 26

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
                color: .black.opacity(isSelected ? 0.18 : 0.08),
                radius: isSelected ? 7 : 4,
                x: 0,
                y: isSelected ? 4 : 2
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

    /// Hero is laid out by a `Color.clear` 4:3 frame; the photo overlays
    /// it with `.scaledToFill()` and `.clipped()`. This pattern is the
    /// only way to get a stable aspect-ratio container in SwiftUI when
    /// the source asset's intrinsic size doesn't match the desired
    /// frame — using `.aspectRatio(_:contentMode:.fill)` directly on the
    /// image lets it inflate to its natural pixel size.
    private var heroImage: some View {
        Color.clear
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay {
                Image(projectType.thumbnailAssetName)
                    .resizable()
                    .scaledToFill()
            }
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
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .foregroundStyle(isSelected ? ColorTokens.primaryOrange : .white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, SpacingTokens.xxs)
            .frame(maxWidth: .infinity)
            .frame(minHeight: labelHeight)
            .background(
                isSelected
                    ? ColorTokens.primaryOrange.opacity(0.22)
                    : Color.black.opacity(0.78)
            )
    }

    // MARK: - Selection Affordances

    @ViewBuilder
    private var selectionStroke: some View {
        RoundedRectangle(cornerRadius: RadiusTokens.card, style: .continuous)
            .strokeBorder(
                isSelected ? ColorTokens.primaryOrange : ColorTokens.subtleBorder.opacity(0.6),
                lineWidth: isSelected ? 2 : 0.75
            )
    }

    @ViewBuilder
    private var selectionBadge: some View {
        if isSelected {
            ZStack {
                Circle()
                    .fill(ColorTokens.primaryOrange)
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 2)

                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .padding(SpacingTokens.xxs)
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
