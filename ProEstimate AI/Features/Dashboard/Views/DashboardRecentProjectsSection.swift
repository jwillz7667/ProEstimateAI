import SwiftUI

/// Shows the last 5 projects as tappable cards with project type icon,
/// title, client name, status badge, and date.
struct DashboardRecentProjectsSection: View {
    let projects: [Project]
    var onProjectTap: ((Project) -> Void)?
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
        Button {
            onProjectTap?(project)
        } label: {
            GlassCard {
                HStack(spacing: SpacingTokens.sm) {
                    // Project type icon
                    Image(systemName: iconForProjectType(project.projectType))
                        .font(.system(size: 20))
                        .foregroundStyle(ColorTokens.primaryOrange)
                        .frame(width: 40, height: 40)
                        .background(
                            ColorTokens.primaryOrange.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: RadiusTokens.small)
                        )

                    // Title and details
                    VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                        Text(project.title)
                            .font(TypographyTokens.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)

                        Text(project.updatedAt.formatted(as: .relative))
                            .font(TypographyTokens.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Status badge
                    statusBadge(for: project.status)
                }
            }
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

    private func statusBadge(for status: Project.Status) -> StatusBadge {
        switch status {
        case .draft:
            StatusBadge(text: "Draft", style: .neutral)
        case .photosUploaded:
            StatusBadge(text: "Photos", style: .info)
        case .generating:
            StatusBadge(text: "Generating", style: .info)
        case .generationComplete:
            StatusBadge(text: "Generated", style: .info)
        case .estimateCreated:
            StatusBadge(text: "Estimated", style: .warning)
        case .proposalSent:
            StatusBadge(text: "Proposed", style: .warning)
        case .approved:
            StatusBadge(text: "Approved", style: .success)
        case .declined:
            StatusBadge(text: "Declined", style: .error)
        case .invoiced:
            StatusBadge(text: "Invoiced", style: .info)
        case .completed:
            StatusBadge(text: "Complete", style: .success)
        case .archived:
            StatusBadge(text: "Archived", style: .neutral)
        }
    }
}
