import PhotosUI
import SwiftUI

/// Step 1 of the simplified creation flow. Combines what used to be the
/// dedicated photos step and the prompt step into one coherent screen:
/// upload "before" photos, pick a stylistic suggestion from the
/// category-aware carousel, and (optionally) layer custom instructions
/// on top.
struct PhotosAndPromptStep: View {
    @Bindable var viewModel: ProjectCreationViewModel

    @FocusState private var isInstructionsFocused: Bool
    @State private var isCameraPresented = false

    private let isCameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)

    private let imageColumns = [
        GridItem(.flexible(), spacing: SpacingTokens.sm),
        GridItem(.flexible(), spacing: SpacingTokens.sm),
        GridItem(.flexible(), spacing: SpacingTokens.sm),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingTokens.lg) {
                photosSection
                promptSuggestionsSection
                customInstructionsSection
            }
            .padding(.vertical, SpacingTokens.sm)
        }
        .scrollDismissesKeyboard(.interactively)
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraView { image in
                viewModel.addCameraImage(image)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Photos

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                Text("Upload a before photo")
                    .font(TypographyTokens.title3)
                Text("More photos produce better AI previews. At least one is required.")
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, SpacingTokens.md)

            VStack(spacing: SpacingTokens.sm) {
                if isCameraAvailable {
                    photoSourceButton(
                        icon: "camera.fill",
                        title: "Take Photo",
                        subtitle: "Use your camera to capture the space"
                    ) {
                        isCameraPresented = true
                    }
                }

                photoLibraryButton
            }
            .padding(.horizontal, SpacingTokens.md)

            if viewModel.selectedImageData.isEmpty {
                photoStatusRow(
                    icon: "exclamationmark.circle",
                    text: "At least 1 photo required",
                    tint: ColorTokens.warning
                )
                .padding(.horizontal, SpacingTokens.md)
            } else {
                photoStatusRow(
                    icon: "checkmark.circle.fill",
                    text: photoCountLabel,
                    tint: ColorTokens.success
                )
                .padding(.horizontal, SpacingTokens.md)

                imageGrid
                    .padding(.horizontal, SpacingTokens.md)
            }

            if viewModel.isLoadingImages {
                HStack {
                    Spacer()
                    ProgressView("Loading photos...")
                        .tint(ColorTokens.primaryOrange)
                    Spacer()
                }
                .padding(.vertical, SpacingTokens.sm)
            }

            if let error = viewModel.imageLoadError {
                imageErrorBanner(error)
                    .padding(.horizontal, SpacingTokens.md)
            }
        }
    }

    private var photoCountLabel: String {
        let count = viewModel.selectedImageData.count
        return "\(count) photo\(count == 1 ? "" : "s") selected"
    }

    private func photoSourceButton(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: SpacingTokens.sm) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(ColorTokens.primaryOrange)

                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text(title)
                        .font(TypographyTokens.headline)
                    Text(subtitle)
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(SpacingTokens.md)
            .glassCard(cornerRadius: RadiusTokens.card)
        }
        .buttonStyle(.plain)
    }

    private var photoLibraryButton: some View {
        PhotosPicker(
            selection: $viewModel.selectedPhotosItems,
            maxSelectionCount: 10,
            matching: .images,
            photoLibrary: .shared()
        ) {
            HStack(spacing: SpacingTokens.sm) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title2)
                    .foregroundStyle(ColorTokens.primaryOrange)

                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text("Choose from Library")
                        .font(TypographyTokens.headline)
                    Text("Select up to 10 photos")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(SpacingTokens.md)
            .glassCard(cornerRadius: RadiusTokens.card)
        }
        .buttonStyle(.plain)
        .onChange(of: viewModel.selectedPhotosItems) { _, _ in
            Task { await viewModel.loadImages() }
        }
    }

    private func photoStatusRow(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: SpacingTokens.xxs) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
            Text(text)
                .font(TypographyTokens.caption)
                .foregroundStyle(tint)
        }
    }

    private var imageGrid: some View {
        LazyVGrid(columns: imageColumns, spacing: SpacingTokens.sm) {
            ForEach(Array(viewModel.selectedImageData.enumerated()), id: \.offset) { index, data in
                imageCell(data: data, index: index)
            }
        }
    }

    private func imageCell(data: Data, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 110)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.small))
            } else {
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .fill(.quaternary)
                    .frame(height: 110)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }

            Button {
                viewModel.removeImage(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
            .offset(x: 6, y: -6)
            .accessibilityLabel("Remove photo \(index + 1)")
        }
    }

    private func imageErrorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: SpacingTokens.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(ColorTokens.warning)
                .accessibilityHidden(true)

            Text(message)
                .font(TypographyTokens.caption)
                .foregroundStyle(ColorTokens.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: SpacingTokens.xxs) {
                Button("Retry") {
                    Task { await viewModel.loadImages() }
                }
                .font(TypographyTokens.caption.weight(.semibold))
                .foregroundStyle(ColorTokens.primaryOrange)
                .disabled(viewModel.isLoadingImages)

                Button("Dismiss") {
                    viewModel.clearImageLoadError()
                }
                .font(TypographyTokens.caption2)
                .foregroundStyle(ColorTokens.secondaryText)
            }
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
    }

    // MARK: - Prompt Suggestions

    private var promptSuggestionsSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                Text("Pick a style direction")
                    .font(TypographyTokens.title3)
                Text("Tap a suggestion to set the design vibe — or skip and write your own below.")
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, SpacingTokens.md)

            if let projectType = viewModel.selectedProjectType {
                PromptCardCarousel(
                    cards: PromptCard.suggestions(for: projectType),
                    selectedCardId: viewModel.selectedPromptCard?.id,
                    onSelect: { card in
                        if viewModel.selectedPromptCard?.id == card.id {
                            viewModel.clearPromptCard()
                        } else {
                            viewModel.selectPromptCard(card)
                        }
                    }
                )
            } else {
                // Defensive fallback — shouldn't be reachable since the
                // user can't advance from step 0 without picking a type.
                Text("Pick a category first to see style suggestions.")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, SpacingTokens.md)
            }
        }
    }

    // MARK: - Custom Instructions

    private var customInstructionsSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                Text("Custom instructions")
                    .font(TypographyTokens.title3)
                HStack(spacing: SpacingTokens.xxs) {
                    Text("Optional")
                        .font(TypographyTokens.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, SpacingTokens.xs)
                        .padding(.vertical, 1)
                        .background(ColorTokens.inputBackground, in: Capsule())
                    Text("Layer specifics on top of your selection above.")
                        .font(TypographyTokens.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.customInstructions)
                    .font(TypographyTokens.body)
                    .focused($isInstructionsFocused)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(SpacingTokens.xs)
                    .background(
                        ColorTokens.inputBackground,
                        in: RoundedRectangle(cornerRadius: RadiusTokens.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: RadiusTokens.card)
                            .strokeBorder(ColorTokens.subtleBorder, lineWidth: 1)
                    )

                if viewModel.customInstructions.isEmpty {
                    Text("e.g. keep the existing window, swap brass hardware for matte black, add a pot filler over the range")
                        .font(TypographyTokens.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, SpacingTokens.sm)
                        .padding(.vertical, SpacingTokens.sm)
                        .allowsHitTesting(false)
                }
            }

            HStack {
                Text("\(viewModel.customInstructionsCharacterCount) / \(viewModel.maxCustomInstructionsLength)")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(
                        viewModel.customInstructionsCharacterCount > viewModel.maxCustomInstructionsLength
                            ? ColorTokens.error
                            : .secondary
                    )

                Spacer()

                if isInstructionsFocused {
                    Button("Done") { isInstructionsFocused = false }
                        .font(TypographyTokens.caption.weight(.semibold))
                        .foregroundStyle(ColorTokens.primaryOrange)
                }
            }
        }
        .padding(.horizontal, SpacingTokens.md)
    }
}

// MARK: - Preview

#Preview {
    let vm = ProjectCreationViewModel()
    vm.selectedProjectType = .kitchen
    return PhotosAndPromptStep(viewModel: vm)
}
