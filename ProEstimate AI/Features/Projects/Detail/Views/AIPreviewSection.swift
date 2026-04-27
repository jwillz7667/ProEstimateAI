import SwiftUI

/// AI preview section on the project detail screen.
/// States: no generation (CTA), generating (progress card),
/// completed (before/after slider with carousel of multiple generations).
struct AIPreviewSection: View {
    let generations: [AIGeneration]
    let isGenerating: Bool
    let currentGenerationStage: Int
    let onGenerate: (String) -> Void
    /// Default prompt text shown when no previous generation exists (typically the project description).
    var defaultPrompt: String = ""
    var assets: [Asset] = []

    @State private var selectedGenerationIndex: Int = 0
    @State private var activePromptEditor: PromptEditorRequest?
    /// When non-nil, presents the full-screen before/after viewer. Identifiable
    /// so we can rebuild the sheet content if the contractor opens, dismisses,
    /// then re-opens for a different generation in the same session.
    @State private var fullScreenViewer: FullScreenViewerRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            SectionHeaderView(
                title: "AI Preview",
                actionTitle: generations.isEmpty ? nil : "\(generations.count) generation\(generations.count == 1 ? "" : "s")"
            )

            if isGenerating {
                generatingView
            } else if completedGenerations.isEmpty {
                noGenerationView
            } else {
                completedView
            }
        }
        .sheet(item: $activePromptEditor) { request in
            GeneratePromptSheet(initialPrompt: request.initialPrompt) { submitted in
                activePromptEditor = nil
                onGenerate(submitted)
            } onCancel: {
                activePromptEditor = nil
            }
        }
        .fullScreenCover(item: $fullScreenViewer) { request in
            BeforeAfterFullScreenViewer(
                beforeImageURL: request.beforeURL,
                afterImageURL: request.afterURL,
                caption: request.caption
            )
        }
    }

    /// Identifiable trigger for the full-screen before/after viewer. Captures
    /// the URLs + caption at tap-time so the presentation is stable even if
    /// the contractor scrolls a new generation into selection while the
    /// viewer is open.
    private struct FullScreenViewerRequest: Identifiable, Hashable {
        let id: String
        let beforeURL: URL?
        let afterURL: URL?
        let caption: String?
    }

    /// Identifiable trigger used to drive the prompt editor sheet through
    /// `.sheet(item:)`. The id embeds the initial prompt so presenting with
    /// a different prefill always re-creates the sheet content.
    private struct PromptEditorRequest: Identifiable, Hashable {
        let id: String
        let initialPrompt: String

        init(initialPrompt: String) {
            self.initialPrompt = initialPrompt
            id = initialPrompt
        }
    }

    // MARK: - Computed

    private var completedGenerations: [AIGeneration] {
        generations.filter { $0.status == .completed }
    }

    /// Best available pre-fill: most recent generation's prompt, or the project-level default.
    private var bestPromptSuggestion: String {
        completedGenerations.first?.prompt ?? defaultPrompt
    }

    // MARK: - State Views

    private var noGenerationView: some View {
        VStack(spacing: SpacingTokens.md) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 40))
                .foregroundStyle(ColorTokens.primaryOrange.opacity(0.6))

            Text("No AI Preview Yet")
                .font(TypographyTokens.headline)

            Text("Generate an AI-powered remodel preview based on your photos and description.")
                .font(TypographyTokens.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            PrimaryCTAButton(
                title: "Generate Preview",
                icon: "wand.and.stars"
            ) {
                activePromptEditor = PromptEditorRequest(initialPrompt: bestPromptSuggestion)
            }
            .frame(maxWidth: 280)
        }
        .padding(SpacingTokens.xl)
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: RadiusTokens.card)
        .padding(.horizontal, SpacingTokens.md)
    }

    private var generatingView: some View {
        GenerationProgressCard(currentStage: currentGenerationStage)
            .padding(.horizontal, SpacingTokens.md)
    }

    private var completedView: some View {
        VStack(spacing: SpacingTokens.sm) {
            // Before/After slider for the selected generation
            if selectedGenerationIndex < completedGenerations.count {
                let gen = completedGenerations[selectedGenerationIndex]

                let beforeURL = assets.first(where: { $0.assetType == .original })?.url
                let afterURL = gen.previewURL
                ZStack(alignment: .topTrailing) {
                    BeforeAfterSlider(
                        beforeImageURL: beforeURL,
                        afterImageURL: afterURL
                    )
                    // Expand button — corner placement keeps it out of the
                    // slider's horizontal drag path so taps on the body of
                    // the slider still move the divider, while a tap on the
                    // chip opens the full-screen viewer.
                    Button {
                        fullScreenViewer = FullScreenViewerRequest(
                            id: "\(gen.id)-fullscreen",
                            beforeURL: beforeURL,
                            afterURL: afterURL,
                            caption: gen.prompt
                        )
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(SpacingTokens.xs)
                            .background(.black.opacity(0.55), in: Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(SpacingTokens.sm)
                    .accessibilityLabel("Enlarge before/after comparison")
                }
                .padding(.horizontal, SpacingTokens.md)

                // Generation info
                HStack(spacing: SpacingTokens.sm) {
                    if let duration = gen.durationDisplay {
                        HStack(spacing: SpacingTokens.xxs) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text(duration)
                                .font(TypographyTokens.caption)
                        }
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(gen.createdAt.formatted(as: .relative))
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, SpacingTokens.md)

                // Prompt used
                Text(gen.prompt)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, SpacingTokens.md)
            }

            // Generation carousel pagination
            if completedGenerations.count > 1 {
                generationPagination
            }

            // Generate another button
            SecondaryButton(title: "Generate Another", icon: "wand.and.stars") {
                activePromptEditor = PromptEditorRequest(initialPrompt: bestPromptSuggestion)
            }
            .padding(.horizontal, SpacingTokens.md)
        }
    }

    private var generationPagination: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SpacingTokens.xs) {
                ForEach(Array(completedGenerations.enumerated()), id: \.element.id) { index, gen in
                    Button {
                        selectedGenerationIndex = index
                    } label: {
                        VStack(spacing: SpacingTokens.xxs) {
                            AsyncImage(url: gen.thumbnailURL) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Rectangle()
                                    .fill(.quaternary)
                                    .overlay {
                                        Image(systemName: "wand.and.stars")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                            }
                            .frame(width: 64, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.small))
                            .overlay(
                                RoundedRectangle(cornerRadius: RadiusTokens.small)
                                    .strokeBorder(
                                        selectedGenerationIndex == index
                                            ? ColorTokens.primaryOrange : .clear,
                                        lineWidth: 2
                                    )
                            )

                            Text("v\(index + 1)")
                                .font(TypographyTokens.caption2)
                                .foregroundStyle(
                                    selectedGenerationIndex == index
                                        ? ColorTokens.primaryOrange : .secondary
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, SpacingTokens.md)
        }
    }
}

// MARK: - Generate Prompt Sheet

/// Sheet that lets the user confirm or edit the AI prompt before kicking off
/// a generation. The `initialPrompt` (usually the project's description or
/// the most recent generation's prompt) is wired directly into the internal
/// `@State` via an init-based initializer, so it is always present and
/// submit-ready when the sheet appears — no "tap to activate" step.
private struct GeneratePromptSheet: View {
    @State private var prompt: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    init(
        initialPrompt: String,
        onSubmit: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _prompt = State(initialValue: initialPrompt)
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !trimmedPrompt.isEmpty && prompt.count <= 2000
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: SpacingTokens.md) {
                Text("Describe how you want the remodel to look. Be specific about materials, colors, and style.")
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: $prompt)
                    .font(TypographyTokens.body)
                    .scrollContentBackground(.hidden)
                    .padding(SpacingTokens.sm)
                    .background(ColorTokens.darkSurface.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.small))
                    .frame(minHeight: 140, maxHeight: 220)

                HStack {
                    Text("Tap the text to edit")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.tertiary)

                    Spacer()

                    Text("\(prompt.count)/2000")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(prompt.count > 2000 ? ColorTokens.error : .secondary)
                }

                Spacer(minLength: SpacingTokens.sm)

                PrimaryCTAButton(
                    title: "Generate",
                    icon: "wand.and.stars",
                    isDisabled: !isValid
                ) {
                    onSubmit(trimmedPrompt)
                }
            }
            .padding(SpacingTokens.lg)
            .navigationTitle("AI Prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Preview

#Preview("No Generation") {
    AIPreviewSection(
        generations: [],
        isGenerating: false,
        currentGenerationStage: 0,
        onGenerate: { _ in },
        defaultPrompt: "Modern kitchen with white shaker cabinets"
    )
}

#Preview("Generating") {
    AIPreviewSection(
        generations: [],
        isGenerating: true,
        currentGenerationStage: 2,
        onGenerate: { _ in }
    )
}

#Preview("Completed") {
    AIPreviewSection(
        generations: MockGenerationService.sampleGenerations,
        isGenerating: false,
        currentGenerationStage: 0,
        onGenerate: { _ in }
    )
}
