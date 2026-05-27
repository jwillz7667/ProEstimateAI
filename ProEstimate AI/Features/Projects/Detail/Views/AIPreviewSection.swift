import SwiftUI

/// AI preview section on the project detail screen.
/// Layout matches the overhaul "Generation Results" screenshot: pill +
/// timestamp header, project title, before/after slider, optional version
/// pager, and a "Generate Another" secondary button.
struct AIPreviewSection: View {
    let generations: [AIGeneration]
    let isGenerating: Bool
    let currentGenerationStage: Int
    let onGenerate: (String) -> Void
    /// Default prompt text shown when no previous generation exists (typically the project description).
    var defaultPrompt: String = ""
    /// Project title rendered above the comparison slider.
    var projectTitle: String = ""
    var assets: [Asset] = []

    @State private var selectedGenerationIndex: Int = 0
    @State private var activePromptEditor: PromptEditorRequest?
    @State private var fullScreenViewer: FullScreenViewerRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.md) {
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

    private struct FullScreenViewerRequest: Identifiable, Hashable {
        let id: String
        let beforeURL: URL?
        let afterURL: URL?
        let caption: String?
    }

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

    private var bestPromptSuggestion: String {
        completedGenerations.first?.prompt ?? defaultPrompt
    }

    // MARK: - State Views

    private var noGenerationView: some View {
        VStack(spacing: SpacingTokens.md) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(ColorTokens.primaryOrange)

            Text("No Vision Yet")
                .font(TypographyTokens.cardTitle)
                .foregroundStyle(ColorTokens.textPrimary)

            Text("Generate an AI-powered remodel preview based on your photos and description.")
                .font(TypographyTokens.subheadline)
                .foregroundStyle(ColorTokens.textSecondary)
                .multilineTextAlignment(.center)

            PrimaryCTAButton(
                title: "Generate Vision",
                icon: "sparkles",
                style: .dark
            ) {
                activePromptEditor = PromptEditorRequest(initialPrompt: bestPromptSuggestion)
            }
            .frame(maxWidth: 320)
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
        VStack(alignment: .leading, spacing: SpacingTokens.md) {
            if selectedGenerationIndex < completedGenerations.count {
                let gen = completedGenerations[selectedGenerationIndex]
                let beforeURL = assets.first(where: { $0.assetType == .original })?.url
                let afterURL = gen.previewURL

                resultHeader(for: gen)

                ZStack(alignment: .topTrailing) {
                    BeforeAfterSlider(
                        beforeImageURL: beforeURL,
                        afterImageURL: afterURL
                    )
                    .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.card))

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
                    }
                    .buttonStyle(.plain)
                    .padding(SpacingTokens.sm)
                    .accessibilityLabel("Enlarge before/after comparison")
                }
            }

            if completedGenerations.count > 1 {
                generationPagination
            }

            SecondaryButton(title: "Generate Another", icon: "sparkles") {
                activePromptEditor = PromptEditorRequest(initialPrompt: bestPromptSuggestion)
            }
        }
        .padding(.horizontal, SpacingTokens.md)
    }

    // MARK: - Result Header

    private func resultHeader(for gen: AIGeneration) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            HStack(spacing: SpacingTokens.xs) {
                StatusBadge(text: "VIRTUAL REMODEL", style: .info)
                Text("Generated \(gen.createdAt.formatted(as: .dateTime))")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.textSecondary)
            }

            if !projectTitle.isEmpty {
                Text(projectTitle)
                    .font(TypographyTokens.title)
                    .foregroundStyle(ColorTokens.textPrimary)
                    .lineLimit(2)
            }
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
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Rectangle()
                                    .fill(ColorTokens.background)
                                    .overlay {
                                        Image(systemName: "sparkles")
                                            .font(.caption)
                                            .foregroundStyle(ColorTokens.textTertiary)
                                    }
                            }
                            .frame(width: 64, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.small))
                            .overlay(
                                RoundedRectangle(cornerRadius: RadiusTokens.small)
                                    .strokeBorder(
                                        selectedGenerationIndex == index
                                            ? ColorTokens.primaryOrange : Color.clear,
                                        lineWidth: 2
                                    )
                            )

                            Text("v\(index + 1)")
                                .font(TypographyTokens.caption2)
                                .foregroundStyle(
                                    selectedGenerationIndex == index
                                        ? ColorTokens.primaryOrange : ColorTokens.textSecondary
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Generate Prompt Sheet

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
                    .foregroundStyle(ColorTokens.textSecondary)

                TextEditor(text: $prompt)
                    .font(TypographyTokens.body)
                    .scrollContentBackground(.hidden)
                    .padding(SpacingTokens.sm)
                    .background(ColorTokens.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: RadiusTokens.input)
                            .strokeBorder(ColorTokens.cardStroke, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.input))
                    .frame(minHeight: 140, maxHeight: 220)

                HStack {
                    Spacer()
                    Text("\(prompt.count)/2000")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(prompt.count > 2000 ? ColorTokens.error : ColorTokens.textTertiary)
                }

                Spacer(minLength: SpacingTokens.sm)

                PrimaryCTAButton(
                    title: "Generate Vision",
                    icon: "sparkles",
                    isDisabled: !isValid,
                    style: .dark
                ) {
                    onSubmit(trimmedPrompt)
                }
            }
            .padding(SpacingTokens.lg)
            .navigationTitle("Describe Your Vision")
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
        defaultPrompt: "Modern kitchen with white shaker cabinets",
        projectTitle: "Modern Coastal Kitchen"
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
        onGenerate: { _ in },
        projectTitle: "Modern Coastal Kitchen"
    )
}
