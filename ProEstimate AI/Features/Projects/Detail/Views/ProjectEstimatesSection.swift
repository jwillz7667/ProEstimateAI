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
    /// The estimate currently being converted into an invoice — drives the
    /// inline spinner on that row's "Convert to Invoice" button.
    var convertingEstimateId: String?
    var isGeneratingAI: Bool = false
    var onGenerateAI: (() -> Void)?
    var onCreateEstimate: (() -> Void)?
    var onExportEstimate: ((String) -> Void)?
    var onTapSavedExport: ((EstimateExport) -> Void)?
    /// Wrap an approved estimate in a client-facing proposal (the approval
    /// half of the get-paid loop). Optional so previews can omit it.
    var onCreateProposal: ((String) -> Void)?
    /// Convert an approved estimate into a Pro-only invoice. Optional so the
    /// section still renders in previews / contexts that don't wire it.
    var onConvertToInvoice: ((String) -> Void)?

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
                            if onCreateProposal != nil {
                                Button {
                                    onCreateProposal?(estimate.id)
                                } label: {
                                    Label("Create Proposal", systemImage: "doc.richtext")
                                }
                            }
                            if onConvertToInvoice != nil {
                                Button {
                                    onConvertToInvoice?(estimate.id)
                                } label: {
                                    Label("Convert to Invoice", systemImage: "doc.plaintext")
                                }
                            }
                        }

                    exportCTA(for: estimate)

                    billingActions(for: estimate)

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
                        .tint(colorScheme == .light ? Color.black : Color.white)
                } else {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.callout.weight(.semibold))
                }
                Text(exportingEstimateId == estimate.id ? "Preparing PDF…" : "Export Branded PDF")
                    .font(TypographyTokens.subheadline.weight(.semibold))
            }
            .foregroundStyle(colorScheme == .light ? Color.black : Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, SpacingTokens.sm)
            .background(ColorTokens.primaryOrange, in: RoundedRectangle(cornerRadius: RadiusTokens.button))
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.button)
                    .strokeBorder(
                        colorScheme == .light ? Color.black : Color.clear,
                        lineWidth: colorScheme == .light ? 2 : 0
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(exportingEstimateId != nil)
        .accessibilityLabel("Export branded PDF")
        .accessibilityHint("Render and save a branded PDF copy of this estimate")
    }

    /// Secondary "Proposal" + "Convert to Invoice" actions beneath the export
    /// CTA. These drive the get-paid loop: wrap the estimate in a client-facing
    /// proposal, or convert it directly into a Pro-only invoice. Only rendered
    /// when the host wires the corresponding callbacks.
    @ViewBuilder
    private func billingActions(for estimate: Estimate) -> some View {
        if onCreateProposal != nil || onConvertToInvoice != nil {
            VStack(spacing: SpacingTokens.sm) {
                if onCreateProposal != nil {
                    billingActionButton(title: "Create Proposal", icon: "doc.richtext") {
                        onCreateProposal?(estimate.id)
                    }
                }
                if onConvertToInvoice != nil {
                    convertCTA(for: estimate)
                }
            }
        }
    }

    private func billingActionButton(
        title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: SpacingTokens.xxs) {
                Image(systemName: icon)
                    .font(.callout.weight(.semibold))
                Text(title)
                    .font(TypographyTokens.subheadline.weight(.semibold))
            }
            .foregroundStyle(ColorTokens.primaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, SpacingTokens.sm)
            .background(ColorTokens.inputBackground, in: RoundedRectangle(cornerRadius: RadiusTokens.button))
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.button)
                    .strokeBorder(ColorTokens.primaryOrange.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// Secondary action to turn this estimate into a billable invoice. Pro-
    /// gated downstream — tapping while on the free tier surfaces the paywall.
    /// Disabled while any conversion is in flight to avoid double-creating.
    private func convertCTA(for estimate: Estimate) -> some View {
        SecondaryButton(
            title: convertingEstimateId == estimate.id ? "Creating Invoice…" : "Convert to Invoice",
            icon: "doc.plaintext",
            isLoading: convertingEstimateId == estimate.id,
            emphasis: .accent
        ) {
            onConvertToInvoice?(estimate.id)
        }
        .disabled(convertingEstimateId != nil)
        .accessibilityHint("Create an invoice from this estimate")
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
