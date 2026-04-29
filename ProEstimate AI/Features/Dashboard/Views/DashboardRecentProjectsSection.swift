import SwiftUI

/// Horizontal, snap-paged carousel of recent projects. Each card is a
/// large thumbnail (or fallback gradient) with an overlaid title + status
/// pill. Tapping pushes onto the dashboard navigation stack.
struct DashboardRecentProjectsSection: View {
    let projects: [Project]
    var thumbnails: [String: URL] = [:]
    var onSeeAll: (() -> Void)?
    var onCreateProject: (() -> Void)?

    /// Width fraction of each card relative to the container. Leaves a small
    /// peek of the next card so users discover the horizontal scroll.
    private let cardWidthFraction: Double = 0.82
    private let cardHeight: CGFloat = 220
    /// Larger than the card shadow's blur radius so adjacent cards' shadows
    /// don't bleed into each other and read as visual overlap.
    private let cardSpacing: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            SectionHeaderView(
                title: "Recent Projects",
                actionTitle: projects.isEmpty ? nil : "See All",
                action: projects.isEmpty ? nil : onSeeAll
            )
            .padding(.horizontal, SpacingTokens.md)

            if projects.isEmpty {
                emptyCard
                    .padding(.horizontal, SpacingTokens.md)
            } else {
                carousel
            }
        }
    }

    // MARK: - Carousel

    private var carousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: cardSpacing) {
                ForEach(projects.prefix(10)) { project in
                    NavigationLink(value: AppDestination.projectDetail(id: project.id)) {
                        projectCard(project)
                    }
                    .buttonStyle(.plain)
                    .containerRelativeFrame(.horizontal) { length, _ in
                        length * cardWidthFraction
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(accessibilityLabel(for: project))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Opens project details")
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, SpacingTokens.md)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
    }

    // MARK: - Card

    private func projectCard(_ project: Project) -> some View {
        ZStack(alignment: .bottomLeading) {
            thumbnailLayer(for: project)

            // Bottom-anchored gradient so light photos still keep the
            // overlay text legible.
            LinearGradient(
                colors: [.black.opacity(0.0), .black.opacity(0.55), .black.opacity(0.78)],
                startPoint: .center,
                endPoint: .bottom
            )

            // Top-right status pill
            VStack {
                HStack {
                    Spacer()
                    statusBadge(for: project.status)
                }
                Spacer()
            }
            .padding(SpacingTokens.sm)

            // Title + meta block
            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                Text(project.title)
                    .font(TypographyTokens.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(project.updatedAt.formatted(as: .relative))
                    .font(TypographyTokens.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(SpacingTokens.md)
        }
        .frame(height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.card))
        .overlay(
            RoundedRectangle(cornerRadius: RadiusTokens.card)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        )
        // Tighter shadow so adjacent cards' bleed doesn't visually merge.
        .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 4)
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private func thumbnailLayer(for project: Project) -> some View {
        if let url = thumbnails[project.id] {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    fallbackArt(for: project)
                default:
                    placeholder(for: project)
                }
            }
            // Pin AsyncImage to the card's full frame and clip — without
            // these, .fill lets the image spill past the card edges into
            // adjacent slots in the carousel (the parent .clipShape
            // alone isn't enough; the image's geometry still affects
            // sibling layout before the outer clip is applied).
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        } else {
            fallbackArt(for: project)
        }
    }

    private func placeholder(for project: Project) -> some View {
        ZStack {
            ColorTokens.primaryOrange.opacity(0.08)
            Image(systemName: project.projectType.iconName)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(ColorTokens.primaryOrange.opacity(0.4))
        }
    }

    private func fallbackArt(for project: Project) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    ColorTokens.primaryOrange.opacity(0.85),
                    ColorTokens.primaryOrange.opacity(0.55),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: project.projectType.iconName)
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    // MARK: - Empty State

    private var emptyCard: some View {
        Button {
            onCreateProject?()
        } label: {
            VStack(spacing: SpacingTokens.sm) {
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(ColorTokens.primaryOrange)

                Text("Create your first project")
                    .font(TypographyTokens.headline)
                    .foregroundStyle(ColorTokens.primaryText)

                Text("Upload photos, generate an AI remodel preview, and turn it into an estimate.")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SpacingTokens.lg)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SpacingTokens.xl)
            .glassCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create your first project")
        .accessibilityHint("Starts the new project flow")
    }

    // MARK: - Status Pill

    private func statusBadge(for status: Project.Status) -> some View {
        let (text, badgeColor): (String, Color) = {
            switch status {
            case .draft: ("Draft", ColorTokens.secondaryText)
            case .photosUploaded: ("Photos", ColorTokens.primaryOrange)
            case .generating: ("Generating", ColorTokens.warning)
            case .generationComplete: ("Generated", ColorTokens.success)
            case .estimateCreated: ("Estimated", ColorTokens.success)
            case .proposalSent: ("Proposed", ColorTokens.accentBlue)
            case .approved: ("Approved", ColorTokens.success)
            case .declined: ("Declined", ColorTokens.error)
            case .invoiced: ("Invoiced", ColorTokens.accentPurple)
            case .completed: ("Complete", ColorTokens.success)
            case .archived: ("Archived", ColorTokens.secondaryText)
            }
        }()

        return Text(text)
            .font(TypographyTokens.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, SpacingTokens.xs)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().strokeBorder(badgeColor.opacity(0.55), lineWidth: 1)
            )
            .foregroundStyle(badgeColor)
    }

    // MARK: - Accessibility

    private func accessibilityLabel(for project: Project) -> String {
        let status = statusText(for: project.status)
        let when = project.updatedAt.formatted(as: .relative)
        return "Project \(project.title), \(status), updated \(when)"
    }

    private func statusText(for status: Project.Status) -> String {
        switch status {
        case .draft: "Draft"
        case .photosUploaded: "Photos uploaded"
        case .generating: "Generating preview"
        case .generationComplete: "Preview generated"
        case .estimateCreated: "Estimate created"
        case .proposalSent: "Proposal sent"
        case .approved: "Approved"
        case .declined: "Declined"
        case .invoiced: "Invoiced"
        case .completed: "Completed"
        case .archived: "Archived"
        }
    }
}
