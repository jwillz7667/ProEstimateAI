import SwiftUI

struct ProposalHeroSection: View {
    let heroImageURL: URL?
    let projectTitle: String
    let clientName: String?
    let date: String

    var body: some View {
        VStack(spacing: 0) {
            // Hero image area
            ZStack(alignment: .bottomLeading) {
                heroImageContent

                // Overlay with project info
                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text(projectTitle)
                        .font(TypographyTokens.title2)
                        .foregroundStyle(.white)
                        .shadow(radius: 4)

                    HStack(spacing: SpacingTokens.sm) {
                        if let clientName {
                            Label(clientName, systemImage: "person")
                                .font(TypographyTokens.subheadline)
                                .foregroundStyle(.white.opacity(0.9))
                        }

                        Label(date, systemImage: "calendar")
                            .font(TypographyTokens.subheadline)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                .padding(SpacingTokens.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [.black.opacity(0.7), .clear],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var heroImageContent: some View {
        if let heroImageURL {
            AsyncImage(url: heroImageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(16 / 9, contentMode: .fill)
                        .frame(height: 220)
                        .clipped()
                case .failure:
                    placeholderImage
                case .empty:
                    placeholderImage
                        .overlay {
                            ProgressView()
                                .tint(.white)
                        }
                @unknown default:
                    placeholderImage
                }
            }
        } else {
            placeholderImage
        }
    }

    private var placeholderImage: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        ColorTokens.primaryOrange.opacity(0.8),
                        ColorTokens.primaryOrange.opacity(0.4),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(height: 220)
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.3))
            }
    }
}

// MARK: - Preview

#Preview {
    ProposalHeroSection(
        heroImageURL: nil,
        projectTitle: "Kitchen Remodel – Mitchell Residence",
        clientName: "Sarah Mitchell",
        date: "Mar 24, 2026"
    )
}
