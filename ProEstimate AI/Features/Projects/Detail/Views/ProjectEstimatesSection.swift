import SwiftUI

/// Lists estimates linked to this project. Each row shows the estimate
/// number, version, total amount, status badge, and a prominent "Export PDF"
/// action button. Below each row, any previously-exported PDFs surface as
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
    var onExportEstimate: ((String) -> Void)?
    var onTapSavedExport: ((EstimateExport) -> Void)?

    @Environment(\.colorScheme) private var colorScheme

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
                    estimateRow(estimate)
                        .contextMenu {
                            Button {
                                onExportEstimate?(estimate.id)
                            } label: {
                                Label("Export Branded PDF", systemImage: "arrow.down.doc")
                            }
                        }

                    exportCTA(for: estimate)

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

                    Text(estimate.createdAt.formatted(as: .relative))
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                CurrencyText(amount: estimate.totalAmount, font: TypographyTokens.moneySmall)
            }
        }
    }

    /// Prominent full-width "Export PDF" CTA underneath the row. Replaces
    /// the old trailing icon button so the export action reads as the row's
    /// primary action — that's what the contractor actually does next once
    /// an estimate exists.
    private func exportCTA(for estimate: Estimate) -> some View {
        Button {
            onExportEstimate?(estimate.id)
        } label: {
            HStack(spacing: SpacingTokens.xs) {
                if exportingEstimateId == estimate.id {
                    ProgressView()
                        .controlSize(.small)
                        .tint(ColorTokens.primaryText)
                } else {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.callout.weight(.semibold))
                }
                Text(exportingEstimateId == estimate.id ? "Preparing PDF…" : "Export Branded PDF")
                    .font(TypographyTokens.subheadline.weight(.semibold))
            }
            .foregroundStyle(ColorTokens.primaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, SpacingTokens.sm)
            .background(ColorTokens.primaryOrange, in: RoundedRectangle(cornerRadius: RadiusTokens.button))
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.button)
                    .strokeBorder(
                        colorScheme == .light ? ColorTokens.primaryText : Color.clear,
                        lineWidth: colorScheme == .light ? 2 : 0
                    )
            )
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
