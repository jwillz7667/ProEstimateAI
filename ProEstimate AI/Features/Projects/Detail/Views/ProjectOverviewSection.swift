import SwiftUI

/// Overview section at the top of the project detail view.
/// Displays the project type badge, status, client, dates,
/// budget range, quality tier, and square footage.
struct ProjectOverviewSection: View {
    let project: Project
    var clientName: String?
    var onClientTapped: (() -> Void)?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: SpacingTokens.sm) {
                // Type + status row
                HStack(spacing: SpacingTokens.sm) {
                    projectTypeBadge
                    Spacer()
                    statusBadge
                }

                // Title
                Text(project.title)
                    .font(TypographyTokens.title3)

                // Description
                if let description = project.description {
                    Text(description)
                        .font(TypographyTokens.body)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Client
                if let clientName {
                    Button {
                        onClientTapped?()
                    } label: {
                        HStack(spacing: SpacingTokens.xs) {
                            AvatarView(name: clientName, size: 28)
                            Text(clientName)
                                .font(TypographyTokens.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                // Details grid
                detailsGrid
            }
        }
    }

    // MARK: - Subviews

    private var projectTypeBadge: some View {
        HStack(spacing: SpacingTokens.xxs) {
            Image(systemName: projectTypeIcon)
                .font(.caption)
            Text(projectTypeLabel)
                .font(TypographyTokens.caption)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, SpacingTokens.xs)
        .padding(.vertical, SpacingTokens.xxs)
        .background(ColorTokens.primaryOrange.opacity(0.12), in: Capsule())
        .foregroundStyle(ColorTokens.primaryOrange)
    }

    private var statusBadge: some View {
        StatusBadge(
            text: statusText,
            style: statusStyle
        )
    }

    private var detailsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ],
            spacing: SpacingTokens.xs
        ) {
            detailItem(label: "Created", value: project.createdAt.formatted(as: .medium))
            detailItem(label: "Updated", value: project.updatedAt.formatted(as: .relative))

            if let budget = project.budgetRangeDisplay {
                detailItem(label: "Budget", value: budget)
            }

            detailItem(label: "Quality", value: qualityLabel)

            if let sqft = project.squareFootage {
                detailItem(label: "Area", value: "\(sqft) sq ft")
            }

            if let dimensions = project.dimensions {
                detailItem(label: "Dimensions", value: dimensions)
            }
        }
    }

    private func detailItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
            Text(label)
                .font(TypographyTokens.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(TypographyTokens.subheadline)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private var projectTypeIcon: String {
        switch project.projectType {
        case .kitchen: "fork.knife"
        case .bathroom: "shower"
        case .flooring: "square.grid.3x3.fill"
        case .roofing: "house"
        case .painting: "paintbrush"
        case .siding: "building.2"
        case .roomRemodel: "bed.double"
        case .exterior: "tree"
        case .custom: "wrench.and.screwdriver"
        }
    }

    private var projectTypeLabel: String {
        switch project.projectType {
        case .kitchen: "Kitchen"
        case .bathroom: "Bathroom"
        case .flooring: "Flooring"
        case .roofing: "Roofing"
        case .painting: "Painting"
        case .siding: "Siding"
        case .roomRemodel: "Room Remodel"
        case .exterior: "Exterior"
        case .custom: "Custom"
        }
    }

    private var statusText: String {
        switch project.status {
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

    private var statusStyle: StatusBadge.Style {
        switch project.status {
        case .draft, .photosUploaded: .neutral
        case .generating, .generationComplete, .estimateCreated: .info
        case .proposalSent: .warning
        case .approved, .completed, .invoiced: .success
        case .declined: .error
        case .archived: .neutral
        }
    }

    private var qualityLabel: String {
        switch project.qualityTier {
        case .standard: "Standard"
        case .premium: "Premium"
        case .luxury: "Luxury"
        }
    }
}

// MARK: - Preview

#Preview {
    ProjectOverviewSection(
        project: .sample,
        clientName: "Sarah Mitchell"
    )
    .padding()
}
