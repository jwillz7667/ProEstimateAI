import SwiftUI

/// AI preview section on the project detail screen.
/// States: no generation (CTA), generating (progress card),
/// completed (before/after slider with carousel of multiple generations).
struct AIPreviewSection: View {
    let generations: [AIGeneration]
    let isGenerating: Bool
    let currentGenerationStage: Int
    let onGenerate: () -> Void
    var assets: [Asset] = []

    @State private var selectedGenerationIndex: Int = 0

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
    }

    // MARK: - Computed

    private var completedGenerations: [AIGeneration] {
        generations.filter { $0.status == .completed }
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
                icon: "wand.and.stars",
                action: onGenerate
            )
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

                BeforeAfterSlider(
                    beforeImageURL: assets.first(where: { $0.assetType == .original })?.url,
                    afterImageURL: gen.previewURL
                )
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
                onGenerate()
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

// MARK: - Preview

#Preview("No Generation") {
    AIPreviewSection(
        generations: [],
        isGenerating: false,
        currentGenerationStage: 0,
        onGenerate: {}
    )
}

#Preview("Generating") {
    AIPreviewSection(
        generations: [],
        isGenerating: true,
        currentGenerationStage: 2,
        onGenerate: {}
    )
}

#Preview("Completed") {
    AIPreviewSection(
        generations: MockGenerationService.sampleGenerations,
        isGenerating: false,
        currentGenerationStage: 0,
        onGenerate: {}
    )
}
