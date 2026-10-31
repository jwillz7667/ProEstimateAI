import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search"

    var body: some View {
        HStack(spacing: SpacingTokens.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, SpacingTokens.sm)
        .padding(.vertical, SpacingTokens.xs)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: RadiusTokens.button))
    }
}
