import SwiftUI

/// Horizontal scroll of quick action buttons for common workflows.
struct DashboardQuickActionsSection: View {
    var onAction: ((QuickAction) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            SectionHeaderView(title: "Quick Actions")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SpacingTokens.sm) {
                    ForEach(QuickAction.allCases) { action in
                        quickActionButton(action)
                    }
                }
                .padding(.horizontal, SpacingTokens.md)
            }
        }
    }

    private func quickActionButton(_ action: QuickAction) -> some View {
        Button {
            onAction?(action)
        } label: {
            VStack(spacing: SpacingTokens.xs) {
                Image(systemName: action.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(ColorTokens.primaryOrange)
                    .frame(width: 48, height: 48)
                    .background(
                        ColorTokens.primaryOrange.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: RadiusTokens.button)
                    )

                Text(action.title)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.primaryText)
                    .lineLimit(1)
            }
            .frame(width: 80)
        }
        .buttonStyle(.plain)
    }
}
