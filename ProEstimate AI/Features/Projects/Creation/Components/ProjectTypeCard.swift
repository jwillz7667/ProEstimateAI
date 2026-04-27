import SwiftUI

/// A selectable card representing a single project type.
/// Shows an SF Symbol icon and the type label. Selected state
/// is indicated by an orange border and checkmark overlay.
struct ProjectTypeCard: View {
    let projectType: Project.ProjectType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: SpacingTokens.xs) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: iconName)
                        .font(.system(size: 28))
                        .foregroundStyle(isSelected ? ColorTokens.primaryOrange : .secondary)
                        .frame(width: 52, height: 52)
                        .background(
                            (isSelected ? ColorTokens.primaryOrange : Color.gray)
                                .opacity(0.12),
                            in: RoundedRectangle(cornerRadius: RadiusTokens.small)
                        )

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(ColorTokens.primaryOrange)
                            .offset(x: 4, y: -4)
                    }
                }

                Text(displayName)
                    .font(TypographyTokens.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? ColorTokens.primaryOrange : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SpacingTokens.sm)
            .padding(.horizontal, SpacingTokens.xs)
            .glassCard(cornerRadius: RadiusTokens.card)
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.card)
                    .strokeBorder(
                        isSelected ? ColorTokens.primaryOrange : .clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    /// Delegate to the enum's own iconName / displayName so the picker
    /// automatically tracks any new project types added to the model.
    private var iconName: String {
        projectType.iconName
    }

    private var displayName: String {
        projectType.displayName
    }
}

// MARK: - Preview

#Preview {
    HStack {
        ProjectTypeCard(projectType: .kitchen, isSelected: true) {}
        ProjectTypeCard(projectType: .bathroom, isSelected: false) {}
        ProjectTypeCard(projectType: .flooring, isSelected: false) {}
    }
    .padding()
}
