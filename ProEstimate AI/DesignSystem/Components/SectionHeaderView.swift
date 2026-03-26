import SwiftUI

struct SectionHeaderView: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(TypographyTokens.headline)

            Spacer()

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(ColorTokens.primaryOrange)
            }
        }
        .padding(.horizontal, SpacingTokens.md)
        .padding(.vertical, SpacingTokens.xs)
    }
}
