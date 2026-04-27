import SwiftUI

/// A card-style row for the project list. Shows the project type icon,
/// title, client name, status badge, date, and an optional thumbnail.
struct ProjectRowView: View {
    let project: Project
    var clientName: String?
    var thumbnailURL: URL?

    var body: some View {
        GlassCard {
            HStack(spacing: SpacingTokens.sm) {
                // Project type icon
                projectTypeIcon

                // Text content
                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text(project.title)
                        .font(TypographyTokens.headline)
                        .lineLimit(1)

                    if let clientName {
                        HStack(spacing: SpacingTokens.xxs) {
                            Image(systemName: "person")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(clientName)
                                .font(TypographyTokens.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    HStack(spacing: SpacingTokens.xs) {
                        statusBadge
                        Spacer()
                        Text(project.updatedAt.formatted(as: .relative))
                            .font(TypographyTokens.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                // Optional thumbnail
                if let thumbnailURL {
                    AsyncImage(url: thumbnailURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Rectangle()
                            .fill(.quaternary)
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.small))
                }
            }
        }
    }

    // MARK: - Subviews

    private var projectTypeIcon: some View {
        Image(systemName: iconName(for: project.projectType))
            .font(.title2)
            .foregroundStyle(ColorTokens.primaryOrange)
            .frame(width: 44, height: 44)
            .background(ColorTokens.primaryOrange.opacity(0.12), in: RoundedRectangle(cornerRadius: RadiusTokens.small))
    }

    private var statusBadge: some View {
        StatusBadge(
            text: statusText(for: project.status),
            style: statusStyle(for: project.status)
        )
    }

    // MARK: - Helpers

    private func iconName(for type: Project.ProjectType) -> String {
        type.iconName
    }

    private func statusText(for status: Project.Status) -> String {
        switch status {
        case .draft: "Draft"
        case .photosUploaded: "Photos Uploaded"
        case .generating: "Generating"
        case .generationComplete: "Preview Ready"
        case .estimateCreated: "Estimate Ready"
        case .proposalSent: "Proposal Sent"
        case .approved: "Approved"
        case .declined: "Declined"
        case .invoiced: "Invoiced"
        case .completed: "Completed"
        case .archived: "Archived"
        }
    }

    private func statusStyle(for status: Project.Status) -> StatusBadge.Style {
        switch status {
        case .draft, .photosUploaded:
            return .neutral
        case .generating:
            return .info
        case .generationComplete, .estimateCreated:
            return .info
        case .proposalSent:
            return .warning
        case .approved, .completed:
            return .success
        case .declined:
            return .error
        case .invoiced:
            return .success
        case .archived:
            return .neutral
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: SpacingTokens.sm) {
        ProjectRowView(
            project: .sample,
            clientName: "Sarah Mitchell",
            thumbnailURL: nil
        )

        ProjectRowView(
            project: Project(
                id: "p-002",
                companyId: "c-001",
                clientId: "cl-002",
                title: "Master Bathroom Renovation",
                description: nil,
                projectType: .bathroom,
                status: .estimateCreated,
                budgetMin: 8000,
                budgetMax: 18000,
                qualityTier: .luxury,
                squareFootage: 120,
                dimensions: nil,
                language: "en",
                createdAt: Date(),
                updatedAt: Date()
            ),
            clientName: "James Rodriguez"
        )
    }
    .padding()
}
