import SwiftUI

/// A small, readable preview of saved work. Titles and status stay outside
/// photographs so every project remains legible while thumbnails load.
struct DashboardRecentProjectsSection: View {
    let projects: [Project]
    var isLoading = false
    var hasLoaded = true
    var errorMessage: String?
    var onSeeAll: (() -> Void)?
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent projects")
                    .font(TypographyTokens.title3)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: SpacingTokens.xs)
                Button("View all") { onSeeAll?() }
                    .font(TypographyTokens.subheadline.weight(.semibold))
                    .foregroundStyle(ColorTokens.primaryText)
                    .frame(minHeight: 44)
                    .accessibilityHint("Opens your full project list")
            }

            if let errorMessage {
                retryNotice(errorMessage)
            }
            if !projects.isEmpty {
                VStack(spacing: 0) {
                    ForEach(projects) { project in
                        NavigationLink(value: AppDestination.projectDetail(id: project.id)) {
                            DashboardProjectRow(project: project)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Continue working on this project")
                        if project.id != projects.last?.id {
                            Divider().padding(.leading, SpacingTokens.md)
                        }
                    }
                }
                .background(ColorTokens.surface, in: RoundedRectangle(cornerRadius: RadiusTokens.card))
                .overlay {
                    RoundedRectangle(cornerRadius: RadiusTokens.card)
                        .strokeBorder(ColorTokens.border.opacity(0.35), lineWidth: 0.5)
                }
            } else if isLoading {
                HStack(spacing: SpacingTokens.sm) {
                    ProgressView()
                    Text("Loading your projects…")
                        .font(TypographyTokens.subheadline)
                        .foregroundStyle(ColorTokens.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SpacingTokens.lg)
                .accessibilityElement(children: .combine)
            } else if hasLoaded, errorMessage == nil {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            Image(systemName: "folder")
                .font(.title2)
                .foregroundStyle(ColorTokens.secondaryText)
                .accessibilityHidden(true)
            Text("A place for every project")
                .font(TypographyTokens.headline)
            Text("Start with a name and the type of work. Add photos, build an estimate and keep client details together.")
                .font(TypographyTokens.subheadline)
                .foregroundStyle(ColorTokens.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SpacingTokens.lg)
        .background(ColorTokens.surface, in: RoundedRectangle(cornerRadius: RadiusTokens.card))
        .accessibilityElement(children: .combine)
    }

    private func retryNotice(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            Label(message, systemImage: "wifi.exclamationmark")
                .font(TypographyTokens.subheadline)
                .foregroundStyle(ColorTokens.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again") { onRetry?() }
                .font(TypographyTokens.subheadline.weight(.semibold))
                .foregroundStyle(ColorTokens.primaryText)
                .frame(minHeight: 44)
                .disabled(isLoading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SpacingTokens.md)
        .background(ColorTokens.surface, in: RoundedRectangle(cornerRadius: RadiusTokens.card))
    }
}

private struct DashboardProjectRow: View {
    let project: Project
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .center, spacing: SpacingTokens.sm) {
            if !dynamicTypeSize.isAccessibilitySize {
                thumbnail
            }
            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                Text(project.title)
                    .font(TypographyTokens.headline)
                    .foregroundStyle(ColorTokens.primaryText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                Text(project.projectType.displayName)
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(ColorTokens.secondaryText)
                Text(statusLabel)
                    .font(TypographyTokens.caption.weight(.medium))
                    .foregroundStyle(ColorTokens.primaryText)
                Text(project.updatedAt, format: .dateTime.month(.abbreviated).day())
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(ColorTokens.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(SpacingTokens.md)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.title), \(project.projectType.displayName), \(statusLabel), updated \(project.updatedAt.formatted(date: .abbreviated, time: .omitted))")
    }

    private var thumbnail: some View {
        ColorTokens.primaryOrange.opacity(0.1)
            .overlay {
                if let url = project.thumbnailURL {
                    AsyncImage(url: url.thumbnail(width: 240)) { phase in
                        if case let .success(image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: 72, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.button))
            .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Image(systemName: project.projectType.iconName)
            .font(.title2)
            .foregroundStyle(ColorTokens.primaryText)
    }

    private var statusLabel: String {
        switch project.status {
        case .draft: "Draft"
        case .photosUploaded: "Photos added"
        case .generating: "AI preview in progress"
        case .generationComplete: "Preview ready"
        case .estimateCreated: "Estimate ready"
        case .proposalSent: "Awaiting client approval"
        case .approved: "Approved"
        case .declined: "Declined"
        case .invoiced: "Invoiced"
        case .completed: "Completed"
        case .archived: "Archived"
        }
    }
}

#Preview("Recent work") {
    NavigationStack {
        DashboardRecentProjectsSection(projects: [.sample])
            .padding()
            .background(ColorTokens.background)
    }
}

#Preview("First project") {
    DashboardRecentProjectsSection(projects: [])
        .padding()
        .background(ColorTokens.background)
}

#Preview("Offline") {
    DashboardRecentProjectsSection(projects: [], hasLoaded: false, errorMessage: "Your projects couldn't be refreshed. Try again when you're connected.")
        .padding()
        .background(ColorTokens.background)
}
