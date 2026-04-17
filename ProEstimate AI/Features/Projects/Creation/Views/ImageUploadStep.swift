import PhotosUI
import SwiftUI

/// Step 2: Upload project photos via the system PhotosPicker or camera.
/// Displays a grid of selected image thumbnails with delete buttons
/// and camera/library entry points.
struct ImageUploadStep: View {
    @Bindable var viewModel: ProjectCreationViewModel
    @State private var isCameraPresented = false

    private let isCameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)

    private let columns = [
        GridItem(.flexible(), spacing: SpacingTokens.sm),
        GridItem(.flexible(), spacing: SpacingTokens.sm),
        GridItem(.flexible(), spacing: SpacingTokens.sm),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingTokens.md) {
                Text("Add Project Photos")
                    .font(TypographyTokens.title3)

                Text("Upload at least one photo of the current space. More photos produce better AI previews.")
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(.secondary)

                // Photo source buttons
                VStack(spacing: SpacingTokens.sm) {
                    if isCameraAvailable {
                        takePhotoButton
                    }
                    photoPickerButton
                }

                // Minimum indicator
                if viewModel.selectedImageData.isEmpty {
                    HStack(spacing: SpacingTokens.xxs) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(ColorTokens.warning)
                        Text("At least 1 photo required")
                            .font(TypographyTokens.caption)
                            .foregroundStyle(ColorTokens.warning)
                    }
                    .padding(.top, SpacingTokens.xxs)
                } else {
                    HStack(spacing: SpacingTokens.xxs) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(ColorTokens.success)
                        Text("\(viewModel.selectedImageData.count) photo\(viewModel.selectedImageData.count == 1 ? "" : "s") selected")
                            .font(TypographyTokens.caption)
                            .foregroundStyle(ColorTokens.success)
                    }
                    .padding(.top, SpacingTokens.xxs)
                }

                // Image grid
                if !viewModel.selectedImageData.isEmpty {
                    imageGrid
                }

                if viewModel.isLoadingImages {
                    HStack {
                        Spacer()
                        ProgressView("Loading photos...")
                            .tint(ColorTokens.primaryOrange)
                        Spacer()
                    }
                    .padding(.vertical, SpacingTokens.md)
                }

                if let error = viewModel.imageLoadError {
                    imageErrorBanner(error)
                }
            }
            .padding(.horizontal, SpacingTokens.md)
            .padding(.vertical, SpacingTokens.sm)
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraView { image in
                viewModel.addCameraImage(image)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Subviews

    private var takePhotoButton: some View {
        Button {
            isCameraPresented = true
        } label: {
            HStack(spacing: SpacingTokens.sm) {
                Image(systemName: "camera.fill")
                    .font(.title2)
                    .foregroundStyle(ColorTokens.primaryOrange)

                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text("Take Photo")
                        .font(TypographyTokens.headline)
                    Text("Use your camera to capture the space")
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

    private var photoPickerButton: some View {
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

    private var imageGrid: some View {
        LazyVGrid(columns: columns, spacing: SpacingTokens.sm) {
            ForEach(Array(viewModel.selectedImageData.enumerated()), id: \.offset) { index, data in
                imageCell(data: data, index: index)
            }
        }
    }

    // MARK: - Error Banner

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

    private func imageCell(data: Data, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 110)
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

            // Delete button
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
}

// MARK: - Preview

#Preview {
    ImageUploadStep(viewModel: ProjectCreationViewModel())
}
