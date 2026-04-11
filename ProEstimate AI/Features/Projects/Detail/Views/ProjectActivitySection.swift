import SwiftUI

/// Timeline / activity feed for a project. Shows chronological entries
/// for significant project events (creation, uploads, generations,
/// estimates, client assignments, etc.).
struct ProjectActivitySection: View {
    let entries: [ActivityLogEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            SectionHeaderView(title: "Activity")

            if entries.isEmpty {
                emptyView
            } else {
                activityTimeline
            }
        }
    }

    // MARK: - Subviews

    private var activityTimeline: some View {
        VStack(spacing: 0) {
            ForEach(Array(sortedEntries.enumerated()), id: \.element.id) { index, entry in
                timelineRow(entry: entry, isLast: index == sortedEntries.count - 1)
            }
        }
        .padding(.horizontal, SpacingTokens.md)
    }

    private func timelineRow(entry: ActivityLogEntry, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: SpacingTokens.sm) {
            // Timeline indicator
            VStack(spacing: 0) {
                Image(systemName: entry.systemImage)
                    .font(.caption)
                    .foregroundStyle(iconColor(for: entry.action))
                    .frame(width: 20, height: 20)
                    .padding(.top, 2)

                if !isLast {
                    Rectangle()
                        .fill(ColorTokens.subtleBorder)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 20)

            // Content
            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                Text(actionTitle(for: entry.action))
                    .font(TypographyTokens.subheadline)
                    .fontWeight(.medium)

                Text(entry.description)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(.secondary)

                Text(entry.createdAt.formatted(as: .relative))
                    .font(TypographyTokens.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, SpacingTokens.md)

            Spacer()
        }
    }

    private var emptyView: some View {
        VStack(spacing: SpacingTokens.sm) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No activity yet")
                .font(TypographyTokens.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(SpacingTokens.xl)
        .padding(.horizontal, SpacingTokens.md)
    }

    // MARK: - Helpers

    private var sortedEntries: [ActivityLogEntry] {
        entries.sorted { $0.createdAt > $1.createdAt }
    }

    private func actionTitle(for action: ActivityLogEntry.Action) -> String {
        switch action {
        case .created: "Project Created"
        case .updated: "Project Updated"
        case .statusChanged: "Status Changed"
        case .imageUploaded: "Photos Uploaded"
        case .generationStarted: "Generation Started"
        case .generationCompleted: "AI Preview Generated"
        case .estimateCreated: "Estimate Created"
        case .estimateUpdated: "Estimate Updated"
        case .proposalSent: "Proposal Sent"
        case .proposalViewed: "Proposal Viewed"
        case .proposalApproved: "Proposal Approved"
        case .proposalDeclined: "Proposal Declined"
        case .invoiceCreated: "Invoice Created"
        case .invoiceSent: "Invoice Sent"
        case .invoicePaid: "Invoice Paid"
        }
    }

    private func iconColor(for action: ActivityLogEntry.Action) -> Color {
        switch action {
        case .created, .imageUploaded, .estimateCreated, .estimateUpdated:
            ColorTokens.primaryOrange
        case .updated, .statusChanged:
            .secondary
        case .generationStarted:
            ColorTokens.primaryOrange
        case .generationCompleted, .proposalApproved, .invoicePaid:
            ColorTokens.success
        case .proposalSent, .invoiceSent, .proposalViewed, .invoiceCreated:
            .blue
        case .proposalDeclined:
            ColorTokens.error
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        ProjectActivitySection(entries: ActivityLogEntry.samples)
    }
}
