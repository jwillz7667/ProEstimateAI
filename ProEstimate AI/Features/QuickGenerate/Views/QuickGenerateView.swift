import SwiftUI
import PhotosUI

/// Streamlined AI remodel preview flow accessible from the dashboard.
/// Pick a photo → describe the remodel → select room type → generate.
/// Creates a project behind the scenes and kicks off AI generation.
struct QuickGenerateView: View {
    var onProjectCreated: ((String) -> Void)?

    @State private var viewModel = QuickGenerateViewModel()
    @State private var isCameraPresented = false
    @Environment(\.dismiss) private var dismiss
    @Environment(FeatureGateCoordinator.self) private var featureGateCoordinator
    @Environment(PaywallPresenter.self) private var paywallPresenter

    private let isCameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .input:
                    inputPhase
                case .generating:
                    generatingPhase
                case .result:
                    resultPhase
                case .error:
                    errorPhase
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(viewModel.phase == .result ? "Done" : "Cancel") {
                        if let projectId = viewModel.createdProjectId {
                            onProjectCreated?(projectId)
                        }
                        dismiss()
                    }
                }
            }
        }
    }

    private var navigationTitle: String {
        switch viewModel.phase {
        case .input: "AI Remodel Preview"
        case .generating: "Generating..."
        case .result: "Preview Ready"
        case .error: "Generation Failed"
        }
    }

    // MARK: - Input Phase

    private var inputPhase: some View {
        ScrollView {
            VStack(spacing: SpacingTokens.lg) {
                // Photo section
                photoSection

                // Room type selection
                roomTypeSection

                // Prompt
                promptSection

                // Generate button
                PrimaryCTAButton(
                    title: "Generate AI Preview",
                    icon: "wand.and.stars",
                    isLoading: viewModel.isSubmitting,
                    isDisabled: !viewModel.canGenerate
                ) {
                    handleGenerate()
                }
                .padding(.horizontal, SpacingTokens.md)
            }
            .padding(.vertical, SpacingTokens.md)
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            Text("Photo of Your Space")
                .font(TypographyTokens.headline)
                .padding(.horizontal, SpacingTokens.md)

            if let imageData = viewModel.selectedImageData,
               let uiImage = UIImage(data: imageData) {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.card))
                        .padding(.horizontal, SpacingTokens.md)

                    Button {
                        viewModel.clearPhoto()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }
                    .padding(.trailing, SpacingTokens.lg)
                    .padding(.top, SpacingTokens.sm)
                    .accessibilityLabel("Remove photo")
                }
            } else {
                VStack(spacing: SpacingTokens.sm) {
                    if isCameraAvailable {
                        Button {
                            isCameraPresented = true
                        } label: {
                            HStack(spacing: SpacingTokens.sm) {
                                Image(systemName: "camera.fill")
                                    .font(.title3)
                                    .foregroundStyle(ColorTokens.primaryOrange)
                                Text("Take Photo")
                                    .font(TypographyTokens.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(SpacingTokens.md)
                            .glassCard()
                        }
                        .buttonStyle(.plain)
                    }

                    PhotosPicker(
                        selection: $viewModel.photosPickerItem,
                        matching: .images
                    ) {
                        HStack(spacing: SpacingTokens.sm) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.title3)
                                .foregroundStyle(ColorTokens.primaryOrange)
                            Text("Choose from Library")
                                .font(TypographyTokens.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(SpacingTokens.md)
                        .glassCard()
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, SpacingTokens.md)
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
    }

    private var roomTypeSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            Text("Room Type")
                .font(TypographyTokens.headline)
                .padding(.horizontal, SpacingTokens.md)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SpacingTokens.sm) {
                    ForEach(Project.ProjectType.allCases, id: \.rawValue) { type in
                        roomTypeChip(type)
                    }
                }
                .padding(.horizontal, SpacingTokens.md)
            }
        }
    }

    private func roomTypeChip(_ type: Project.ProjectType) -> some View {
        let isSelected = viewModel.selectedProjectType == type
        return Button {
            viewModel.selectedProjectType = type
        } label: {
            HStack(spacing: SpacingTokens.xxs) {
                Image(systemName: iconForType(type))
                    .font(.caption)
                Text(labelForType(type))
                    .font(TypographyTokens.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, SpacingTokens.sm)
            .padding(.vertical, SpacingTokens.xs)
            .background(
                isSelected
                    ? ColorTokens.primaryOrange
                    : ColorTokens.surface,
                in: Capsule()
            )
            .foregroundStyle(isSelected ? .white : ColorTokens.primaryText)
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.clear : Color(.separator).opacity(0.3),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            Text("Describe Your Remodel")
                .font(TypographyTokens.headline)
                .padding(.horizontal, SpacingTokens.md)

            ZStack(alignment: .topLeading) {
                if viewModel.prompt.isEmpty {
                    Text("e.g., Modern kitchen with white shaker cabinets, quartz countertops, and a large island...")
                        .font(TypographyTokens.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, SpacingTokens.md + 4)
                        .padding(.top, SpacingTokens.sm + 8)
                }

                TextEditor(text: $viewModel.prompt)
                    .font(TypographyTokens.body)
                    .frame(minHeight: 100)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, SpacingTokens.xs)
                    .padding(.vertical, SpacingTokens.xs)
            }
            .glassCard()
            .padding(.horizontal, SpacingTokens.md)

            Text("\(viewModel.prompt.count)/500")
                .font(TypographyTokens.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, SpacingTokens.md)
        }
    }

    // MARK: - Generating Phase

    private var generatingPhase: some View {
        VStack(spacing: SpacingTokens.xl) {
            Spacer()

            GenerationProgressCard(currentStage: viewModel.currentStage)
                .padding(.horizontal, SpacingTokens.md)

            Text("This usually takes 15–35 seconds")
                .font(TypographyTokens.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    // MARK: - Result Phase

    private var resultPhase: some View {
        ScrollView {
            VStack(spacing: SpacingTokens.lg) {
                // Before/After
                if let beforeData = viewModel.selectedImageData,
                   let _ = UIImage(data: beforeData),
                   let gen = viewModel.completedGeneration {
                    BeforeAfterSlider(
                        beforeImageURL: nil,
                        afterImageURL: gen.previewURL,
                        beforeImageData: beforeData
                    )
                    .padding(.horizontal, SpacingTokens.md)
                }

                // Generation info
                if let gen = viewModel.completedGeneration {
                    HStack {
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
                    }
                    .padding(.horizontal, SpacingTokens.md)
                }

                // Actions
                VStack(spacing: SpacingTokens.sm) {
                    PrimaryCTAButton(
                        title: "View Full Project",
                        icon: "folder.fill"
                    ) {
                        if let projectId = viewModel.createdProjectId {
                            onProjectCreated?(projectId)
                        }
                        dismiss()
                    }
                    .padding(.horizontal, SpacingTokens.md)

                    SecondaryButton(title: "Generate Another", icon: "wand.and.stars") {
                        viewModel.reset()
                    }
                    .padding(.horizontal, SpacingTokens.md)
                }
            }
            .padding(.vertical, SpacingTokens.md)
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
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SpacingTokens.xl)
            }

            PrimaryCTAButton(title: "Try Again", icon: "arrow.clockwise") {
                viewModel.phase = .input
            }
            .frame(maxWidth: 200)

            Spacer()
        }
    }

    // MARK: - Feature Gate

    private func handleGenerate() {
        let result = featureGateCoordinator.guardGeneratePreview()
        switch result {
        case .allowed:
            Task {
                await viewModel.generate()
                // After successful generation, check for soft upgrade prompt
                if viewModel.phase == .result,
                   let softGate = featureGateCoordinator.shouldShowSoftUpgradeAfterGeneration() {
                    paywallPresenter.present(softGate)
                }
            }
        case .blocked(let decision):
            paywallPresenter.present(decision)
        }
    }

    // MARK: - Helpers

    private func iconForType(_ type: Project.ProjectType) -> String {
        switch type {
        case .kitchen: "fork.knife"
        case .bathroom: "shower"
        case .flooring: "square.grid.3x3.topleft.filled"
        case .roofing: "house"
        case .painting: "paintbrush"
        case .siding: "building.2"
        case .roomRemodel: "bed.double"
        case .exterior: "tree"
        case .custom: "wrench.and.screwdriver"
        }
    }

    private func labelForType(_ type: Project.ProjectType) -> String {
        switch type {
        case .kitchen: "Kitchen"
        case .bathroom: "Bathroom"
        case .flooring: "Flooring"
        case .roofing: "Roofing"
        case .painting: "Painting"
        case .siding: "Siding"
        case .roomRemodel: "Room"
        case .exterior: "Exterior"
        case .custom: "Custom"
        }
    }
}

#Preview {
    QuickGenerateView()
        .environment(FeatureGateCoordinator.preview())
        .environment(PaywallPresenter())
}
