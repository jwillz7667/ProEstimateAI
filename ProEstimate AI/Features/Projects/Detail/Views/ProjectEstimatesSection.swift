import SwiftUI

/// Lists estimates linked to this project. Each row shows the estimate
/// number, version, total amount, status badge, and a per-estimate "Export
/// PDF" action. Below each row, any previously-exported PDFs surface as
/// tappable "Saved" rows so the contractor can re-share without
/// regenerating. A single primary "Generate Estimate" CTA at the bottom
/// uses AI with any selected materials as context.
struct ProjectEstimatesSection: View {
    let estimates: [Estimate]
    var exports: [String: [EstimateExport]] = [:]
    var exportingEstimateId: String?
    var isGeneratingAI: Bool = false
    var onGenerateAI: (() -> Void)?
    var onCreateEstimate: (() -> Void)?
    var onEstimateTap: ((String) -> Void)?
    var onExportEstimate: ((String) -> Void)?
    var onTapSavedExport: ((EstimateExport) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            SectionHeaderView(
                title: "Estimates",
                actionTitle: estimates.isEmpty ? nil : "\(estimates.count) version\(estimates.count == 1 ? "" : "s")"
            )

            if estimates.isEmpty {
                emptyView
            } else {
                estimatesList
            }

            // One primary action. Users who explicitly want an empty
            // estimate can reach it via the overflow menu.
            VStack(spacing: SpacingTokens.xs) {
                PrimaryCTAButton(
                    title: estimates.isEmpty ? "Generate Estimate" : "Generate New Estimate",
                    icon: "wand.and.stars",
                    isLoading: isGeneratingAI,
                    isDisabled: isGeneratingAI
                ) {
                    onGenerateAI?()
                }

                Menu {
                    Button {
                        onCreateEstimate?()
                    } label: {
                        Label("Start from blank estimate", systemImage: "doc.badge.plus")
                    }
                } label: {
                    Text("More options")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, SpacingTokens.xxs)
                }
                .disabled(isGeneratingAI)
            }
            .padding(.horizontal, SpacingTokens.md)
        }
    }

    // MARK: - Subviews

    private var estimatesList: some View {
        VStack(spacing: SpacingTokens.sm) {
            ForEach(estimates) { estimate in
                VStack(spacing: SpacingTokens.xs) {
                    Button {
                        onEstimateTap?(estimate.id)
                    } label: {
                        estimateRow(estimate)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            onEstimateTap?(estimate.id)
                        } label: {
                            Label("Edit Estimate", systemImage: "pencil")
                        }
                        Button {
                            onExportEstimate?(estimate.id)
                        } label: {
                            Label("Export Branded PDF", systemImage: "arrow.down.doc")
                        }
                    }

                    if let saved = exports[estimate.id], !saved.isEmpty {
                        savedExportsList(saved)
                    }
                }
            }
        }
        .padding(.horizontal, SpacingTokens.md)
    }

    private func estimateRow(_ estimate: Estimate) -> some View {
        GlassCard {
            HStack(spacing: SpacingTokens.sm) {
                // Estimate icon
                Image(systemName: "doc.text")
                    .font(.title3)
                    .foregroundStyle(ColorTokens.primaryOrange)
                    .frame(width: 36, height: 36)
                    .background(ColorTokens.primaryOrange.opacity(0.12), in: RoundedRectangle(cornerRadius: RadiusTokens.small))

                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    HStack(spacing: SpacingTokens.xs) {
                        Text(estimate.estimateNumber)
                            .font(TypographyTokens.headline)

                        Text("v\(estimate.version)")
                            .font(TypographyTokens.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, SpacingTokens.xxs)
                            .padding(.vertical, 1)
                            .background(ColorTokens.inputBackground, in: Capsule())
                    }

                    HStack(spacing: SpacingTokens.xs) {
                        estimateStatusBadge(estimate.status)

                        Spacer()

                        Text(estimate.createdAt.formatted(as: .relative))
                            .font(TypographyTokens.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                CurrencyText(amount: estimate.totalAmount, font: TypographyTokens.moneySmall)

                exportButton(for: estimate)
            }
        }
    }

    /// Trailing icon button that triggers the branded export pipeline. Sits
    /// inside the row's button so it gets ignored by the parent tap (the
    /// row's `Button` wraps the row label, but a nested Button intercepts
    /// the touch first when used inside `.buttonStyle(.plain)`).
    private func exportButton(for estimate: Estimate) -> some View {
        Button {
            onExportEstimate?(estimate.id)
        } label: {
            ZStack {
                Circle()
                    .fill(ColorTokens.inputBackground)
                    .frame(width: 32, height: 32)
                if exportingEstimateId == estimate.id {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.down.doc")
                        .font(.callout)
                        .foregroundStyle(ColorTokens.primaryOrange)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(exportingEstimateId != nil)
        .accessibilityLabel("Export branded PDF")
        .accessibilityHint("Render and save a branded PDF copy of this estimate")
    }

    private func savedExportsList(_ savedExports: [EstimateExport]) -> some View {
        VStack(spacing: SpacingTokens.xxs) {
            ForEach(savedExports) { export in
                Button {
                    onTapSavedExport?(export)
                } label: {
                    savedExportRow(export)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, SpacingTokens.lg)
    }

    private func savedExportRow(_ export: EstimateExport) -> some View {
        HStack(spacing: SpacingTokens.sm) {
            Image(systemName: "doc.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(ColorTokens.inputBackground, in: RoundedRectangle(cornerRadius: RadiusTokens.small))

            VStack(alignment: .leading, spacing: 1) {
                Text(export.fileName)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: SpacingTokens.xxs) {
                    Text(export.createdAt.formatted(as: .relative))
                    Text("·")
                    Text(formatBytes(export.fileSize))
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: "square.and.arrow.up")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, SpacingTokens.sm)
        .padding(.vertical, SpacingTokens.xs)
        .background(ColorTokens.inputBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: RadiusTokens.small))
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func estimateStatusBadge(_ status: Estimate.Status) -> some View {
        let (text, style): (String, StatusBadge.Style) = {
            switch status {
            case .draft: ("Draft", .neutral)
            case .sent: ("Sent", .info)
            case .approved: ("Approved", .success)
            case .declined: ("Declined", .error)
            case .expired: ("Expired", .warning)
            }
        }()

        return StatusBadge(text: text, style: style)
    }

    private var emptyView: some View {
        VStack(spacing: SpacingTokens.sm) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No estimates yet")
                .font(TypographyTokens.subheadline)
                .foregroundStyle(.secondary)
            Text("Create an estimate from AI-suggested materials or start from scratch.")
                .font(TypographyTokens.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(SpacingTokens.xl)
        .padding(.horizontal, SpacingTokens.md)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        ProjectEstimatesSection(estimates: MockGenerationService.sampleEstimates)
    }
}
