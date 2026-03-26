import SwiftUI

/// Step 3: Enter a text description / prompt for the AI generation.
/// Provides a large text editor, character count, language detection hint,
/// and tappable example prompt suggestions.
struct ProjectPromptStep: View {
    @Bindable var viewModel: ProjectCreationViewModel
    @FocusState private var isFocused: Bool

    /// Example prompts the user can tap to populate the text editor.
    private let examplePrompts: [String] = [
        "Modern kitchen with white shaker cabinets, quartz countertops, and a large island with pendant lighting.",
        "Spa-like bathroom with walk-in shower, frameless glass door, freestanding tub, and heated marble floors.",
        "Open-concept living room with engineered hardwood flooring, built-in shelving, and recessed lighting.",
        "Full exterior refresh: new siding, updated front entry, modern landscape lighting.",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingTokens.md) {
                Text("Describe the Project")
                    .font(TypographyTokens.title3)

                Text("Tell the AI what you envision. Include materials, style, and key features.")
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(.secondary)

                // Text editor
                textEditorSection

                // Character count & language
                HStack {
                    Text("\(viewModel.promptCharacterCount) / \(viewModel.maxPromptLength)")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(
                            viewModel.promptCharacterCount > viewModel.maxPromptLength
                            ? ColorTokens.error
                            : .secondary
                        )

                    Spacer()

                    HStack(spacing: SpacingTokens.xxs) {
                        Image(systemName: "globe")
                            .font(.caption2)
                        Text(viewModel.detectedLanguage)
                            .font(TypographyTokens.caption)
                    }
                    .foregroundStyle(.secondary)
                }

                // Example prompts
                examplePromptsSection
            }
            .padding(.horizontal, SpacingTokens.md)
            .padding(.vertical, SpacingTokens.sm)
        }
        .onTapGesture {
            isFocused = false
        }
    }

    // MARK: - Subviews

    private var textEditorSection: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $viewModel.prompt)
                .font(TypographyTokens.body)
                .focused($isFocused)
                .frame(minHeight: 160)
                .scrollContentBackground(.hidden)
                .padding(SpacingTokens.xs)
                .glassCard(cornerRadius: RadiusTokens.card)

            if viewModel.prompt.isEmpty {
                Text("e.g. Modern kitchen with white shaker cabinets and quartz countertops...")
                    .font(TypographyTokens.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, SpacingTokens.sm)
                    .padding(.vertical, SpacingTokens.sm)
                    .allowsHitTesting(false)
            }
        }
    }

    private var examplePromptsSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            SectionHeaderView(title: "Example Prompts")

            ForEach(examplePrompts, id: \.self) { example in
                Button {
                    viewModel.prompt = example
                } label: {
                    HStack(alignment: .top, spacing: SpacingTokens.xs) {
                        Image(systemName: "lightbulb")
                            .font(.caption)
                            .foregroundStyle(ColorTokens.primaryOrange)
                            .padding(.top, 2)

                        Text(example)
                            .font(TypographyTokens.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                    .padding(SpacingTokens.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(cornerRadius: RadiusTokens.small)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ProjectPromptStep(viewModel: ProjectCreationViewModel())
}
