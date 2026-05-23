import PhotosUI
import SwiftUI

/// AI Remodel Studio — the Studio tab's primary screen.
/// Pick a photo → choose a Style Vision and optional Material Focus →
/// generate. Creates a project under the hood and kicks off AI generation
/// against the same backend pipeline used by the full project wizard.
struct QuickGenerateView: View {
    var onProjectCreated: ((String) -> Void)?

    @State private var viewModel = QuickGenerateViewModel()
    @State private var isCameraPresented = false
    @State private var fullScreenViewer: QuickFullScreenViewerRequest?
    @Environment(\.dismiss) private var dismiss
    @Environment(FeatureGateCoordinator.self) private var featureGateCoordinator
    @Environment(PaywallPresenter.self) private var paywallPresenter

    private let isCameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .input: inputPhase
                case .generating: generatingPhase
                case .result: resultPhase
                case .error: errorPhase
                }
            }
            .background(ColorTokens.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("ProEstimate AI")
                .font(TypographyTokens.cardTitle)
                .foregroundStyle(ColorTokens.textPrimary)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                appearedDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ColorTokens.textSecondary)
            }
            .accessibilityLabel(viewModel.phase == .result ? "Done" : "Close")
        }
    }

    // MARK: - Input Phase

    private var inputPhase: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingTokens.xl) {
                headerSection
                photoCard
                styleVisionSection
                materialFocusSection
                roomTypeFooter

                PrimaryCTAButton(
                    title: "Generate Vision",
                    icon: "sparkles",
                    isLoading: viewModel.isSubmitting,
                    isDisabled: !viewModel.canGenerate,
                    style: .dark
                ) {
                    handleGenerate()
                }
                .padding(.top, SpacingTokens.xs)
            }
            .padding(.horizontal, SpacingTokens.md)
            .padding(.vertical, SpacingTokens.md)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            Text("AI Remodel Studio")
                .font(TypographyTokens.title)
                .foregroundStyle(ColorTokens.textPrimary)

            Text("Upload a photo to generate a high-fidelity vision of your finished space.")
                .font(TypographyTokens.subheadline)
                .foregroundStyle(ColorTokens.textSecondary)
        }
    }

    // MARK: - Photo Card

    private var photoCard: some View {
        Group {
            if let imageData = viewModel.selectedImageData,
               let uiImage = UIImage(data: imageData)
            {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.card))

                    Menu {
                        Button("Replace Photo", systemImage: "photo.on.rectangle") {}
                            .disabled(true)
                        if isCameraAvailable {
                            Button("Take New Photo", systemImage: "camera") {
                                isCameraPresented = true
                            }
                        }
                        Button("Remove", systemImage: "trash", role: .destructive) {
                            viewModel.clearPhoto()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(.black.opacity(0.55), in: Circle())
                    }
                    .padding(SpacingTokens.sm)
                    .accessibilityLabel("Photo options")
                }
            } else {
                photoUploadPlaceholder
            }
        }
        .onChange(of: viewModel.photosPickerItem) { _, _ in
            Task { await viewModel.loadSelectedPhoto() }
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraView { image in
                viewModel.setCameraImage(image)
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $fullScreenViewer) { request in
            BeforeAfterFullScreenViewer(
                beforeImageURL: nil,
                afterImageURL: request.afterURL,
                beforeImageData: request.beforeData,
                caption: request.caption
            )
        }
    }

    private var photoUploadPlaceholder: some View {
        PhotosPicker(selection: $viewModel.photosPickerItem, matching: .images) {
            VStack(spacing: SpacingTokens.sm) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(ColorTokens.primaryOrange)

                Text("Tap to upload a photo")
                    .font(TypographyTokens.cardTitle)
                    .foregroundStyle(ColorTokens.textPrimary)

                Text("Use a well-lit photo of the room you want to remodel.")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SpacingTokens.md)

                if isCameraAvailable {
                    Button {
                        isCameraPresented = true
                    } label: {
                        Label("Take Photo", systemImage: "camera")
                            .font(TypographyTokens.buttonSecondary)
                            .padding(.horizontal, SpacingTokens.lg)
                            .padding(.vertical, 10)
                            .background(ColorTokens.primaryOrange.opacity(0.12), in: Capsule())
                            .foregroundStyle(ColorTokens.primaryOrange)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, SpacingTokens.xs)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SpacingTokens.xxl)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.card)
                    .fill(ColorTokens.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: RadiusTokens.card)
                            .strokeBorder(
                                ColorTokens.primaryOrange.opacity(0.55),
                                style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [6, 6])
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    /// Identifiable trigger for the QuickGenerate full-screen viewer. The
    /// "before" is local UIImage data (the photo the contractor just picked
    /// or shot) so we capture it as `Data` rather than a URL.
    struct QuickFullScreenViewerRequest: Identifiable, Hashable {
        let id: String
        let beforeData: Data
        let afterURL: URL?
        let caption: String?
    }

    // MARK: - Style Vision

    private var styleVisionSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            sectionLabel("STYLE VISION")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SpacingTokens.sm) {
                    ForEach(VisionStyle.allCases) { style in
                        styleCard(style)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private func styleCard(_ style: VisionStyle) -> some View {
        let isSelected = viewModel.selectedStyle == style
        return Button {
            viewModel.selectedStyle = style
        } label: {
            VStack(spacing: SpacingTokens.xs) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: RadiusTokens.card)
                        .fill(ColorTokens.background)
                        .overlay(
                            Image(systemName: style.iconName)
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(ColorTokens.textSecondary)
                        )
                        .frame(width: 96, height: 70)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(ColorTokens.primaryOrange)
                            .padding(6)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: RadiusTokens.card)
                        .strokeBorder(
                            isSelected ? ColorTokens.primaryOrange : ColorTokens.cardStroke,
                            lineWidth: isSelected ? 2 : 1
                        )
                )

                Text(style.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? ColorTokens.textPrimary : ColorTokens.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(style.label) style")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Material Focus

    private var materialFocusSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            sectionLabel("MATERIAL FOCUS")

            FlowingChips(items: MaterialFocus.allCases) { focus in
                materialChip(focus)
            }
        }
    }

    private func materialChip(_ focus: MaterialFocus) -> some View {
        let isSelected = viewModel.selectedMaterials.contains(focus)
        return Button {
            viewModel.toggleMaterial(focus)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: focus.iconName)
                    .font(.caption)
                Text(focus.label)
                    .font(TypographyTokens.buttonSecondary)
            }
            .padding(.horizontal, SpacingTokens.md)
            .padding(.vertical, 10)
            .background(
                isSelected ? ColorTokens.primaryOrange : ColorTokens.surface,
                in: Capsule()
            )
            .foregroundStyle(isSelected ? .white : ColorTokens.textPrimary)
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.clear : ColorTokens.cardStroke,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Room Type Footer (compact picker)

    private var roomTypeFooter: some View {
        HStack(spacing: SpacingTokens.xs) {
            Text("Room")
                .font(TypographyTokens.caption)
                .foregroundStyle(ColorTokens.textSecondary)

            Menu {
                ForEach(Project.ProjectType.allCases, id: \.rawValue) { type in
                    Button(type.displayName) {
                        viewModel.selectedProjectType = type
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(viewModel.selectedProjectType?.displayName ?? "Select")
                        .font(TypographyTokens.caption.weight(.semibold))
                        .foregroundStyle(ColorTokens.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(ColorTokens.textSecondary)
                }
                .padding(.horizontal, SpacingTokens.sm)
                .padding(.vertical, 6)
                .background(ColorTokens.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(ColorTokens.cardStroke, lineWidth: 1))
            }
            Spacer()
        }
    }

    // MARK: - Section Label

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .tracking(1.0)
            .foregroundStyle(ColorTokens.textSecondary)
    }

    // MARK: - Generating Phase

    private var generatingPhase: some View {
        VStack(spacing: SpacingTokens.xl) {
            Spacer()

            GenerationProgressCard(currentStage: viewModel.currentStage)
                .padding(.horizontal, SpacingTokens.md)

            Text("This usually takes 15–35 seconds")
                .font(TypographyTokens.caption)
                .foregroundStyle(ColorTokens.textSecondary)

            Spacer()
        }
    }

    // MARK: - Result Phase

    private var resultPhase: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingTokens.lg) {
                resultHeader

                if let beforeData = viewModel.selectedImageData,
                   let _ = UIImage(data: beforeData),
                   let gen = viewModel.completedGeneration
                {
                    ZStack(alignment: .topTrailing) {
                        BeforeAfterSlider(
                            beforeImageURL: nil,
                            afterImageURL: gen.previewURL,
                            beforeImageData: beforeData
                        )
                        .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.card))

                        Button {
                            fullScreenViewer = QuickFullScreenViewerRequest(
                                id: "\(gen.id)-quick-fullscreen",
                                beforeData: beforeData,
                                afterURL: gen.previewURL,
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
                    }
                }

                VStack(spacing: SpacingTokens.sm) {
                    SecondaryButton(title: "Save to Project", icon: "bookmark.fill") {
                        if let projectId = viewModel.createdProjectId {
                            onProjectCreated?(projectId)
                        }
                        dismiss()
                    }

                    PrimaryCTAButton(
                        title: "Generate Quote",
                        icon: "doc.text.fill",
                        style: .dark
                    ) {
                        if let projectId = viewModel.createdProjectId {
                            onProjectCreated?(projectId)
                        }
                        dismiss()
                    }

                    Button("Generate Another") {
                        viewModel.reset()
                    }
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(ColorTokens.textSecondary)
                    .padding(.top, SpacingTokens.xs)
                }
                .padding(.top, SpacingTokens.sm)
            }
            .padding(.horizontal, SpacingTokens.md)
            .padding(.vertical, SpacingTokens.md)
        }
    }

    private var resultHeader: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            HStack(spacing: SpacingTokens.xs) {
                StatusBadge(text: "VIRTUAL REMODEL", style: .info)
                if let gen = viewModel.completedGeneration {
                    Text("Generated \(gen.createdAt.formatted(as: .dateTime))")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(ColorTokens.textSecondary)
                }
            }
            Text(viewModel.selectedStyle.label + " " + (viewModel.selectedProjectType?.displayName ?? "Vision"))
                .font(TypographyTokens.title)
                .foregroundStyle(ColorTokens.textPrimary)
        }
    }

    // MARK: - Error Phase

    private var errorPhase: some View {
        VStack(spacing: SpacingTokens.lg) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(ColorTokens.warning)

            Text("Generation Failed")
                .font(TypographyTokens.title3)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(TypographyTokens.body)
                    .foregroundStyle(ColorTokens.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SpacingTokens.xl)
            }

            PrimaryCTAButton(title: "Try Again", icon: "arrow.clockwise") {
                viewModel.phase = .input
            }
            .frame(maxWidth: 220)

            Spacer()
        }
        .padding(SpacingTokens.md)
    }

    // MARK: - Actions

    private func appearedDismiss() {
        if let projectId = viewModel.createdProjectId {
            onProjectCreated?(projectId)
        }
        dismiss()
    }

    private func handleGenerate() {
        let result = featureGateCoordinator.guardGeneratePreview()
        switch result {
        case .allowed:
            Task {
                await viewModel.generate()
                if viewModel.phase == .result,
                   let softGate = featureGateCoordinator.shouldShowSoftUpgradeAfterGeneration()
                {
                    paywallPresenter.present(softGate)
                }
            }
        case let .blocked(decision):
            paywallPresenter.present(decision)
        }
    }
}

// MARK: - FlowingChips

/// Wrap-around chip layout. Wraps onto multiple rows as space requires —
/// avoids the awkward horizontal-scroll-only behaviour for tappable chips.
struct FlowingChips<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let spacing: CGFloat
    let runSpacing: CGFloat
    @ViewBuilder let content: (Item) -> Content

    init(
        items: [Item],
        spacing: CGFloat = SpacingTokens.xs,
        runSpacing: CGFloat = SpacingTokens.xs,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.items = items
        self.spacing = spacing
        self.runSpacing = runSpacing
        self.content = content
    }

    var body: some View {
        FlowLayout(spacing: spacing, runSpacing: runSpacing) {
            ForEach(items) { item in
                content(item)
            }
        }
    }
}

/// Custom Layout that arranges children in horizontal runs and wraps to
/// the next line when the available width is exhausted. Used by
/// `FlowingChips` for the Material Focus pill cluster.
private struct FlowLayout: Layout {
    var spacing: CGFloat
    var runSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + runSpacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + runSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    QuickGenerateView()
        .environment(FeatureGateCoordinator.preview())
        .environment(PaywallPresenter())
}
