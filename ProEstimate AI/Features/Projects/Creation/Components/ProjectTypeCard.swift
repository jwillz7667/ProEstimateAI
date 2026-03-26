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

    private var iconName: String {
        switch projectType {
        case .kitchen: "fork.knife"
        case .bathroom: "shower"
        case .flooring: "square.grid.3x3.fill"
        case .roofing: "house"
        case .painting: "paintbrush"
        case .siding: "building.2"
        case .roomRemodel: "bed.double"
        case .exterior: "tree"
        case .custom: "wrench.and.screwdriver"
        }
    }

    private var displayName: String {
        switch projectType {
        case .kitchen: "Kitchen"
        case .bathroom: "Bathroom"
        case .flooring: "Flooring"
        case .roofing: "Roofing"
        case .painting: "Painting"
        case .siding: "Siding"
        case .roomRemodel: "Room Remodel"
        case .exterior: "Exterior"
        case .custom: "Custom"
        }
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
