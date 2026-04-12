import SwiftUI

/// Shows the last 5 projects as tappable cards with project type icon,
/// title, client name, status badge, date, and AI generation thumbnail.
struct DashboardRecentProjectsSection: View {
    let projects: [Project]
    var thumbnails: [String: URL] = [:]
    var onSeeAll: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            SectionHeaderView(
                title: "Recent Projects",
                actionTitle: "See All",
                action: onSeeAll
            )

            if projects.isEmpty {
                emptyView
            } else {
                LazyVStack(spacing: SpacingTokens.sm) {
                    ForEach(projects.prefix(5)) { project in
                        projectRow(project)
                    }
                }
                .padding(.horizontal, SpacingTokens.md)
            }
        }
    }

    // MARK: - Project Row

    private func projectRow(_ project: Project) -> some View {
        NavigationLink(value: AppDestination.projectDetail(id: project.id)) {
            HStack(spacing: SpacingTokens.sm) {
                // AI generation thumbnail or project type icon
                thumbnailView(for: project)

                // Title and details
                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text(project.title)
                        .font(TypographyTokens.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(ColorTokens.primaryText)
                        .lineLimit(1)

                    Text(project.updatedAt.formatted(as: .relative))
                        .font(TypographyTokens.caption)
                        .foregroundStyle(ColorTokens.secondaryText)
                }

                Spacer()

                // Status badge
                statusBadge(for: project.status)
            }
            .padding(SpacingTokens.md)
            .background(
                ColorTokens.elevatedSurface,
                in: RoundedRectangle(cornerRadius: RadiusTokens.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.card)
                    .strokeBorder(ColorTokens.primaryOrange.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: ColorTokens.primaryOrange.opacity(0.04), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Thumbnail

    private func thumbnailView(for project: Project) -> some View {
        Group {
            if let url = thumbnails[project.id] {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        fallbackIcon(for: project)
                    default:
                        ProgressView()
                            .frame(width: 48, height: 48)
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.small))
            } else {
                fallbackIcon(for: project)
            }
        }
    }

    private func fallbackIcon(for project: Project) -> some View {
        Image(systemName: iconForProjectType(project.projectType))
            .font(.system(size: 20))
            .foregroundStyle(ColorTokens.primaryOrange)
            .frame(width: 48, height: 48)
            .background(
                ColorTokens.primaryOrange.opacity(0.12),
                in: RoundedRectangle(cornerRadius: RadiusTokens.small)
            )
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: SpacingTokens.sm) {
            Image(systemName: "folder")
                .font(.system(size: 32))
                .foregroundStyle(ColorTokens.secondaryText)

            Text("No projects yet")
                .font(TypographyTokens.subheadline)
                .foregroundStyle(ColorTokens.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SpacingTokens.xxl)
    }

    // MARK: - Helpers

    private func iconForProjectType(_ type: Project.ProjectType) -> String {
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
            .fontWeight(.medium)
            .padding(.horizontal, SpacingTokens.xs)
            .padding(.vertical, 3)
            .background(badgeColor.opacity(0.12), in: Capsule())
            .foregroundStyle(badgeColor)
    }
}
