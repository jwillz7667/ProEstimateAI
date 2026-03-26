import SwiftUI

/// Shows the last 5 projects as tappable cards with project type icon,
/// title, client name, status badge, and date.
struct DashboardRecentProjectsSection: View {
    let projects: [Project]
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
                // Project type icon
                Image(systemName: iconForProjectType(project.projectType))
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        Color.white.opacity(0.2),
                        in: RoundedRectangle(cornerRadius: RadiusTokens.small)
                    )

                // Title and details
                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text(project.title)
                        .font(TypographyTokens.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(project.updatedAt.formatted(as: .relative))
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }

                Spacer()

                // Status badge
                statusBadge(for: project.status)
            }
            .padding(SpacingTokens.md)
            .background(
                LinearGradient(
                    colors: [ColorTokens.primaryOrange, ColorTokens.primaryOrange.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: RadiusTokens.card)
            )
            .shadow(color: ColorTokens.primaryOrange.opacity(0.2), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: SpacingTokens.sm) {
            Image(systemName: "folder")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("No projects yet")
                .font(TypographyTokens.subheadline)
                .foregroundStyle(.secondary)
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
        let text: String = {
            switch status {
            case .draft: "Draft"
            case .photosUploaded: "Photos"
            case .generating: "Generating"
            case .generationComplete: "Generated"
            case .estimateCreated: "Estimated"
            case .proposalSent: "Proposed"
            case .approved: "Approved"
            case .declined: "Declined"
            case .invoiced: "Invoiced"
            case .completed: "Complete"
            case .archived: "Archived"
            }
        }()

        return Text(text)
            .font(TypographyTokens.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, SpacingTokens.xs)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.25), in: Capsule())
            .foregroundStyle(.white)
    }
}
