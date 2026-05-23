import SwiftUI

/// Step 3 of the simplified creation flow. Non-interactive loading view
/// that runs the full create → upload → generate-image → poll-materials
/// pipeline. The hero pairs an orange medallion with a continuously
/// rotating arc spinner; below the title sits a stage-aware rotating
/// phrase row (~50 construction-themed lines, shuffled, cycling every
/// 3.5s) so the wait feels like the AI is doing meaningful work.
/// Falls back gracefully on failure with a retry + "open anyway"
/// escape hatch.
struct ProjectGeneratingStep: View {
    @Bindable var viewModel: ProjectCreationViewModel

    /// Fires when the generation pipeline completes (or the user opts to
    /// open the project anyway after a soft failure). Carries the
    /// project id so the wizard host can navigate to the detail screen.
    var onCompleted: ((_ projectId: String) -> Void)?

    @State private var ringRotation: Double = 0
    @State private var phraseIndex: Int = 0
    @State private var shuffledPhrases: [String] = []

    var body: some View {
        ScrollView {
            VStack(spacing: SpacingTokens.lg) {
                hero

                rotatingPhraseRow
                    .padding(.horizontal, SpacingTokens.md)

                progressChecklist
                    .padding(.top, SpacingTokens.xs)

                if case let .failed(message) = viewModel.pipelineStage {
                    failureSection(message: message)
                } else {
                    helperFootnote
                }
            }
            .padding(.horizontal, SpacingTokens.lg)
            .padding(.vertical, SpacingTokens.xl)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .task {
            // Pipeline runner. The view model's stage starts at `.idle`;
            // the wizard only routes us in after the user taps Create.
            if viewModel.pipelineStage == .idle {
                await viewModel.runCreationPipeline()
            }
        }
        .task {
            // Phrase ticker — independent of the pipeline task so it
            // keeps cycling whether the pipeline is running, queued, or
            // mid-poll.
            await runPhraseTicker()
        }
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
        }
        .onChange(of: viewModel.pipelineStage) { _, newValue in
            if newValue == .completed, let project = viewModel.createdProject {
                onCompleted?(project.id)
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: SpacingTokens.md) {
            heroMedallion

            VStack(spacing: SpacingTokens.xxs) {
                Text(heroTitle)
                    .font(TypographyTokens.title2)
                    .foregroundStyle(ColorTokens.primaryText)
                    .multilineTextAlignment(.center)

                Text(heroSubtitle)
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(ColorTokens.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var heroMedallion: some View {
        ZStack {
            // Continuously rotating arc — reads as a spinner without
            // looking like a generic system ProgressView.
            if !isFailed && !isComplete {
                Circle()
                    .trim(from: 0.0, to: 0.7)
                    .stroke(
                        LinearGradient(
                            colors: [
                                ColorTokens.primaryOrange,
                                ColorTokens.primaryOrange.opacity(0.0),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 122, height: 122)
                    .rotationEffect(.degrees(ringRotation))
            }

            // Filled medallion (matches the brand aesthetic of the
            // dashboard's New Project banner).
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            ColorTokens.primaryOrange,
                            ColorTokens.primaryOrange.opacity(0.75),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 96, height: 96)
                .shadow(color: ColorTokens.primaryOrange.opacity(0.4), radius: 18, x: 0, y: 8)

            heroSymbol
        }
        .accessibilityHidden(true)
        .frame(height: 130) // reserve space so the title doesn't shift
    }

    @ViewBuilder
    private var heroSymbol: some View {
        if isFailed {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.white)
        } else if isComplete {
            Image(systemName: "checkmark")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(.white)
        } else {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.white)
                .symbolEffect(.pulse, options: .repeating, isActive: true)
        }
    }

    private var heroTitle: String {
        if isFailed { return "We hit a snag" }
        if isComplete { return "All set!" }
        return "Preparing your project"
    }

    private var heroSubtitle: String {
        if isFailed { return "Your project is created — you can retry the AI preview or open it anyway." }
        if isComplete { return "Opening your project now…" }
        switch viewModel.pipelineStage {
        case .generatingMaterials:
            return "Generating your materials list and labor estimate. Almost there…"
        default:
            return "This usually takes about a minute. Stay on this screen and we'll have everything ready for you."
        }
    }

    private var isFailed: Bool {
        if case .failed = viewModel.pipelineStage { return true }
        return false
    }

    private var isComplete: Bool {
        viewModel.pipelineStage == .completed
    }

    // MARK: - Rotating Phrase Row

    private var rotatingPhraseRow: some View {
        let phrase = currentPhrase
        return Text(phrase)
            .font(TypographyTokens.callout)
            .fontWeight(.medium)
            .foregroundStyle(ColorTokens.primaryOrange)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
            .id(phrase) // forces transition on phrase change
            .transition(
                .asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity.combined(with: .move(edge: .top))
                )
            )
            .accessibilityLabel("Status: \(phrase)")
    }

    private var currentPhrase: String {
        guard !shuffledPhrases.isEmpty else { return Self.constructionPhrases.first ?? "" }
        return shuffledPhrases[phraseIndex % shuffledPhrases.count]
    }

    private func runPhraseTicker() async {
        // Initialize with a shuffled deck so the first phrase the user
        // sees varies between sessions.
        if shuffledPhrases.isEmpty {
            shuffledPhrases = Self.constructionPhrases.shuffled()
        }

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3.5))
            if Task.isCancelled { return }
            // Once the pipeline is fully done or has hard-failed, stop
            // cycling — the hero and footer carry the final message.
            if isComplete { return }
            if isFailed { return }

            withAnimation(.easeInOut(duration: 0.45)) {
                phraseIndex += 1
                // After cycling through the full deck, reshuffle so we
                // don't show the same order twice in long sessions.
                if phraseIndex >= shuffledPhrases.count {
                    var reshuffled = Self.constructionPhrases.shuffled()
                    // Avoid showing the same phrase twice in a row by
                    // ensuring the new deck starts with a different line
                    // than the one currently on screen.
                    if let last = shuffledPhrases.last, reshuffled.first == last {
                        reshuffled = reshuffled.shuffled()
                    }
                    shuffledPhrases = reshuffled
                    phraseIndex = 0
                }
            }
        }
    }

    // MARK: - Progress Checklist

    private var progressChecklist: some View {
        VStack(spacing: SpacingTokens.sm) {
            ForEach(checklistItems, id: \.id) { item in
                progressRow(item)
            }
        }
        .padding(SpacingTokens.md)
        .glassCard(cornerRadius: RadiusTokens.card)
    }

    private struct ChecklistItem: Identifiable {
        let id: Int
        let title: String
        let subtitle: String
        let stageRank: Int
    }

    private var checklistItems: [ChecklistItem] {
        [
            ChecklistItem(id: 0, title: "Creating project", subtitle: "Saving project details", stageRank: 1),
            ChecklistItem(id: 1, title: "Uploading photos", subtitle: "Securing your before-photos", stageRank: 2),
            ChecklistItem(id: 2, title: "Generating preview", subtitle: "AI render of the finished space", stageRank: 4),
            ChecklistItem(id: 3, title: "Calculating materials", subtitle: "Suggested finishes and quantities", stageRank: 5),
        ]
    }

    private func progressRow(_ item: ChecklistItem) -> some View {
        let state = state(for: item.stageRank)

        return HStack(spacing: SpacingTokens.sm) {
            stateIndicator(state)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(TypographyTokens.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(state == .pending ? ColorTokens.tertiaryText : ColorTokens.primaryText)

                Text(item.subtitle)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.secondaryText)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, SpacingTokens.xxs)
    }

    @ViewBuilder
    private func stateIndicator(_ state: RowState) -> some View {
        switch state {
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(ColorTokens.success)
                .transition(.scale.combined(with: .opacity))
        case .active:
            ProgressView()
                .controlSize(.small)
                .tint(ColorTokens.primaryOrange)
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 22))
                .foregroundStyle(ColorTokens.tertiaryText)
        }
    }

    private enum RowState: Equatable {
        case pending, active, complete
    }

    private func state(for stageRank: Int) -> RowState {
        let current = viewModel.pipelineStage.rank
        if isFailed {
            // Treat steps that completed before the failure as done; the
            // current/next as pending so the failure isn't ambiguous.
            return current >= stageRank ? .complete : .pending
        }
        if current > stageRank { return .complete }
        if current == stageRank { return .active }
        return .pending
    }

    // MARK: - Failure Section

    private func failureSection(message: String) -> some View {
        VStack(spacing: SpacingTokens.sm) {
            HStack(alignment: .top, spacing: SpacingTokens.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(ColorTokens.warning)
                Text(message)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(SpacingTokens.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .fill(ColorTokens.warning.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: RadiusTokens.small)
                            .stroke(ColorTokens.warning.opacity(0.35), lineWidth: 1)
                    )
            )

            VStack(spacing: SpacingTokens.xs) {
                Button {
                    Task { await viewModel.retryGeneration() }
                } label: {
                    Text("Retry preview")
                        .font(TypographyTokens.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SpacingTokens.md)
                        .background(
                            ColorTokens.primaryOrange,
                            in: RoundedRectangle(cornerRadius: RadiusTokens.button)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    if let project = viewModel.createdProject {
                        onCompleted?(project.id)
                    }
                } label: {
                    Text("Open project anyway")
                        .font(TypographyTokens.callout)
                        .foregroundStyle(ColorTokens.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SpacingTokens.sm)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.createdProject == nil)
            }
        }
    }

    // MARK: - Helper Footnote

    private var helperFootnote: some View {
        Text("You can leave this screen at any time — your project keeps generating in the background.")
            .font(TypographyTokens.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, SpacingTokens.md)
    }

    // MARK: - Construction Phrase Library

    /// A long, intentionally-varied list of contractor-flavored status
    /// lines. The set is deliberately broad so a single 60–90s wait
    /// rarely repeats. The phrases describe credible mid-flight work
    /// the AI could be doing — measuring, sourcing, pricing — rather
    /// than generic "loading…" copy.
    private static let constructionPhrases: [String] = [
        "Measuring the space…",
        "Sketching the room layout…",
        "Sourcing stonework options…",
        "Pulling lumber dimensions…",
        "Calculating tile coverage…",
        "Selecting paint finishes…",
        "Cross-referencing supplier pricing…",
        "Drafting labor estimates…",
        "Pricing fixtures…",
        "Tallying drywall sheets…",
        "Reviewing flooring choices…",
        "Mapping electrical runs…",
        "Estimating plumbing rough-in…",
        "Planning cabinet placement…",
        "Configuring lighting layout…",
        "Sizing HVAC requirements…",
        "Spec'ing window details…",
        "Choosing hardware finishes…",
        "Comparing countertop materials…",
        "Calibrating budget targets…",
        "Aligning with quality tier…",
        "Cataloging trim profiles…",
        "Inventorying fasteners…",
        "Selecting grout colors…",
        "Reviewing roofing options…",
        "Sketching siding patterns…",
        "Marking out plumbing fixtures…",
        "Estimating insulation depth…",
        "Looking up code requirements…",
        "Tagging structural touchpoints…",
        "Scoping demolition needs…",
        "Calculating waste factor…",
        "Detailing baseboard runs…",
        "Spec'ing cabinet hardware…",
        "Reviewing tile patterns…",
        "Drafting accent treatments…",
        "Cross-checking measurements…",
        "Counting outlet boxes…",
        "Mapping ductwork paths…",
        "Sizing the breaker panel…",
        "Locating valve shutoffs…",
        "Checking joist spans…",
        "Confirming bearing walls…",
        "Pricing trim packages…",
        "Comparing brand options…",
        "Reviewing concrete work…",
        "Sourcing fixture options…",
        "Tabulating square footage…",
        "Pricing premium upgrades…",
        "Sequencing trade work…",
    ]
}

// MARK: - Preview

#Preview {
    ProjectGeneratingStep(viewModel: ProjectCreationViewModel())
}
