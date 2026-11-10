import SwiftUI

struct DashboardAttentionSection: View {
    let attention: DashboardAttention?
    let isLoading: Bool
    let errorMessage: String?
    let onSelect: (DashboardAttentionGroup) -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.md) {
            Text("Needs attention")
                .font(TypographyTokens.headline)
                .accessibilityAddTraits(.isHeader)

            if let attention {
                if attention.groups.isEmpty {
                    Label("You're up to date. Start an estimate or continue your recent work.", systemImage: "checkmark.circle")
                        .font(TypographyTokens.subheadline)
                        .foregroundStyle(ColorTokens.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(SpacingTokens.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ColorTokens.surface, in: RoundedRectangle(cornerRadius: RadiusTokens.card))
                } else {
                    VStack(spacing: SpacingTokens.sm) {
                        ForEach(attention.groups.prefix(5)) { group in
                            attentionRow(group)
                        }
                    }
                }
            } else if isLoading {
                HStack(spacing: SpacingTokens.sm) {
                    ProgressView()
                    Text("Checking your next actions…")
                        .font(TypographyTokens.subheadline)
                        .foregroundStyle(ColorTokens.secondaryText)
                }
                .padding(.vertical, SpacingTokens.md)
            }

            if let errorMessage {
                VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                    Text(errorMessage)
                        .font(TypographyTokens.caption)
                        .foregroundStyle(ColorTokens.secondaryText)
                    Button("Refresh next actions", action: onRetry)
                        .font(TypographyTokens.subheadline.weight(.semibold))
                        .foregroundStyle(ColorTokens.primaryText)
                        .frame(minHeight: 44)
                        .disabled(isLoading)
                }
            }
        }
    }

    private func attentionRow(_ group: DashboardAttentionGroup) -> some View {
        Button { onSelect(group) } label: {
            HStack(alignment: .top, spacing: SpacingTokens.md) {
                Image(systemName: group.kind.icon)
                    .font(.title3)
                    .foregroundStyle(ColorTokens.primaryOrange)
                    .frame(width: 26)
                    .padding(.top, SpacingTokens.xxs)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                    Text(group.kind.title)
                        .font(TypographyTokens.headline)
                        .foregroundStyle(ColorTokens.primaryText)
                    Text(group.summary)
                        .font(TypographyTokens.subheadline)
                        .foregroundStyle(ColorTokens.secondaryText)
                    Text("\(group.target.documentNumber) · \(group.target.projectTitle)")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(ColorTokens.secondaryText)
                    Text(group.count > 1 ? "Review oldest item" : "Review item")
                        .font(TypographyTokens.caption.weight(.semibold))
                        .foregroundStyle(ColorTokens.primaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ColorTokens.secondaryText)
                    .padding(.top, SpacingTokens.xxs)
                    .accessibilityHidden(true)
            }
            .padding(SpacingTokens.lg)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(ColorTokens.surface, in: RoundedRectangle(cornerRadius: RadiusTokens.card))
            .contentShape(RoundedRectangle(cornerRadius: RadiusTokens.card))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Open \(group.target.documentNumber) to take the next step")
        .accessibilityIdentifier("home.attention.\(group.kind.rawValue)")
        .disabled(errorMessage != nil)
    }
}
