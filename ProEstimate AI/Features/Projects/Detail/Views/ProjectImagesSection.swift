import SwiftUI

/// Horizontal scroll of original uploaded images for a project.
/// Shows an image count badge and supports tap for full-screen preview.
struct ProjectImagesSection: View {
    let assets: [Asset]
    @State private var selectedAsset: Asset?

    /// Mock assets for preview since the backend doesn't exist yet.
    static let mockAssets: [Asset] = [
        Asset(
            id: "a-001",
            projectId: "p-001",
            url: URL(string: "https://cdn.proestimate.ai/assets/kitchen-before-1.jpg")!,
            thumbnailURL: URL(string: "https://cdn.proestimate.ai/assets/kitchen-before-1-thumb.jpg")!,
            assetType: .original,
            sortOrder: 0,
            createdAt: Date()
        ),
        Asset(
            id: "a-002",
            projectId: "p-001",
            url: URL(string: "https://cdn.proestimate.ai/assets/kitchen-before-2.jpg")!,
            thumbnailURL: URL(string: "https://cdn.proestimate.ai/assets/kitchen-before-2-thumb.jpg")!,
            assetType: .original,
            sortOrder: 1,
            createdAt: Date()
        ),
        Asset(
            id: "a-003",
            projectId: "p-001",
            url: URL(string: "https://cdn.proestimate.ai/assets/kitchen-before-3.jpg")!,
            thumbnailURL: URL(string: "https://cdn.proestimate.ai/assets/kitchen-before-3-thumb.jpg")!,
            assetType: .original,
            sortOrder: 2,
            createdAt: Date()
        ),
        Asset(
            id: "a-004",
            projectId: "p-001",
            url: URL(string: "https://cdn.proestimate.ai/assets/kitchen-before-4.jpg")!,
            thumbnailURL: URL(string: "https://cdn.proestimate.ai/assets/kitchen-before-4-thumb.jpg")!,
            assetType: .original,
            sortOrder: 3,
            createdAt: Date()
        ),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            SectionHeaderView(
                title: "Project Photos",
                actionTitle: "\(assets.count) photo\(assets.count == 1 ? "" : "s")"
            )

            if assets.isEmpty {
                noPhotosPlaceholder
            } else {
                imageScroll
            }
        }
        .fullScreenCover(item: $selectedAsset) { asset in
            fullScreenPreview(asset)
        }
    }

    // MARK: - Subviews

    private var imageScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SpacingTokens.sm) {
                ForEach(assets) { asset in
                    Button {
                        selectedAsset = asset
                    } label: {
                        imageCard(asset)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, SpacingTokens.md)
        }
    }

    private func imageCard(_ asset: Asset) -> some View {
        AsyncImage(url: asset.thumbnailURL ?? asset.url) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            Rectangle()
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
        }
        .frame(width: 160, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.small))
    }

    private var noPhotosPlaceholder: some View {
        HStack {
            Spacer()
            VStack(spacing: SpacingTokens.xs) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No photos uploaded")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, SpacingTokens.xl)
            Spacer()
        }
        .padding(.horizontal, SpacingTokens.md)
    }

    private func fullScreenPreview(_ asset: Asset) -> some View {
        NavigationStack {
            AsyncImage(url: asset.url) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                ProgressView()
                    .tint(ColorTokens.primaryOrange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        selectedAsset = nil
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ProjectImagesSection(assets: ProjectImagesSection.mockAssets)
}
