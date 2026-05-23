import SwiftUI

/// Horizontal "Recent Visions" carousel for the Projects home tab.
/// Each card surfaces the AI-generated preview thumbnail with the project
/// title and a relative-time stamp overlaid below; tapping pushes the
/// project detail screen via the parent NavigationStack.
struct DashboardRecentProjectsSection: View {
    let projects: [Project]
    var thumbnails: [String: URL] = [:]
    var onSeeAll: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.md) {
            sectionHeader
                .padding(.horizontal, SpacingTokens.md)

            if projects.isEmpty {
                emptyView
                    .padding(.horizontal, SpacingTokens.md)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SpacingTokens.md) {
                        ForEach(projects.prefix(8)) { project in
                            visionCard(for: project)
                        }
                    }
                    .padding(.horizontal, SpacingTokens.md)
                    .padding(.vertical, SpacingTokens.xxs)
                }
                .scrollClipDisabled()
            }
        }
    }

    // MARK: - Section Header

    private var sectionHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Recent Visions")
                .font(TypographyTokens.title2)
                .foregroundStyle(ColorTokens.textPrimary)

            Spacer()

            if let onSeeAll {
                Button(action: onSeeAll) {
                    Text("VIEW ALL")
                        .font(.caption.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(ColorTokens.primaryOrange)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View all projects")
            }
        }
    }

    // MARK: - Vision Card

    private func visionCard(for project: Project) -> some View {
        NavigationLink(value: AppDestination.projectDetail(id: project.id)) {
            VStack(alignment: .leading, spacing: SpacingTokens.sm) {
                ZStack(alignment: .bottomTrailing) {
                    cardImage(for: project)
                        .frame(width: 260, height: 170)
                        .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.card))

                    StatusBadge(text: project.projectType.displayName, style: .info)
                        .padding(SpacingTokens.sm)
                }

                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text(project.title)
                        .font(TypographyTokens.cardTitle)
                        .foregroundStyle(ColorTokens.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text("Updated \(project.updatedAt.formatted(as: .relative))")
                            .font(TypographyTokens.caption)
                    }
                    .foregroundStyle(ColorTokens.textSecondary)
                }
                .padding(.horizontal, 2)
            }
            .frame(width: 260, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(project.title), \(project.projectType.displayName)")
    }

    @ViewBuilder
    private func cardImage(for project: Project) -> some View {
        if let url = thumbnails[project.id] {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    placeholderTile(for: project)
                default:
                    placeholderTile(for: project)
                        .overlay(ProgressView().tint(.white))
                }
            }
        } else {
            placeholderTile(for: project)
        }
    }

    private func placeholderTile(for project: Project) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    ColorTokens.primaryOrange.opacity(0.55),
                    ColorTokens.heroBackground,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: project.projectType.iconName)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(ColorTokens.heroForeground)
        }
    }

    // MARK: - Empty State

    private var emptyView: some View {
        HStack(spacing: SpacingTokens.md) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 28))
                .foregroundStyle(ColorTokens.textTertiary)

            VStack(alignment: .leading, spacing: 2) {
                Text("No visions yet")
                    .font(TypographyTokens.cardTitle)
                    .foregroundStyle(ColorTokens.textPrimary)
                Text("Start a new project to see your AI remodel previews here.")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.textSecondary)
            }
            Spacer()
        }
        .padding(SpacingTokens.lg)
        .glassCard()
    }
}
