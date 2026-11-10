import SwiftUI

/// Manual editing is the default path. AI creation and paid delivery actions
/// stay explicitly separate from opening and reviewing saved estimates.
struct ProjectEstimatesSection: View {
    let estimates: [Estimate]
    var exports: [String: [EstimateExport]] = [:]
    var exportingEstimateId: String?
    var convertingEstimateId: String?
    var isGeneratingAI = false
    var isCreatingEstimate = false
    var onGenerateAI: (() -> Void)?
    var onCreateEstimate: (() -> Void)?
    var onReviewEstimate: ((String) -> Void)?
    var onExportEstimate: ((String) -> Void)?
    var onTapSavedExport: ((EstimateExport) -> Void)?
    var onCreateProposal: ((String) -> Void)?
    var onConvertToInvoice: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.md) {
            SectionHeaderView(title: "Estimates")
            VStack(alignment: .leading, spacing: SpacingTokens.sm) {
                if estimates.isEmpty {
                    Text("Build an estimate with your own materials and labor costs. AI is optional.")
                        .font(TypographyTokens.subheadline)
                        .foregroundStyle(ColorTokens.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button { onCreateEstimate?() } label: {
                    HStack(spacing: SpacingTokens.xs) {
                        if isCreatingEstimate { ProgressView().tint(ColorTokens.brandDark) }
                        else { Image(systemName: "plus") }
                        Text(isCreatingEstimate ? "Creating estimate…" : "Create estimate")
                            .font(TypographyTokens.headline)
                    }
                    .foregroundStyle(ColorTokens.brandDark)
                    .padding(SpacingTokens.md)
                    .frame(maxWidth: .infinity)
                    .background(ColorTokens.primaryOrange, in: RoundedRectangle(cornerRadius: RadiusTokens.button))
                }
                .buttonStyle(.plain)
                .disabled(isCreatingEstimate || isGeneratingAI)
                .accessibilityHint("Create a draft, then add or edit its line items. No AI subscription required.")

                Button { onGenerateAI?() } label: {
                    HStack(spacing: SpacingTokens.xs) {
                        if isGeneratingAI { ProgressView() }
                        else { Image(systemName: "sparkles") }
                        Text(isGeneratingAI ? "Generating AI estimate…" : "Generate with AI · Pro")
                            .font(TypographyTokens.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(ColorTokens.primaryText)
                    .padding(.vertical, SpacingTokens.sm)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(isGeneratingAI || isCreatingEstimate)
                .accessibilityHint("Requires an active trial or subscription and uses an AI estimate allowance")

                ForEach(estimates) { estimate in
                    estimateCard(estimate)
                }
            }
            .padding(.horizontal, SpacingTokens.md)
        }
    }

    private func estimateCard(_ estimate: Estimate) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: SpacingTokens.sm) {
                Button { onReviewEstimate?(estimate.id) } label: {
                    VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                        HStack(alignment: .firstTextBaseline, spacing: SpacingTokens.sm) {
                            Text(estimate.title ?? estimate.estimateNumber)
                                .font(TypographyTokens.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .accessibilityHidden(true)
                        }
                        Text("\(estimate.estimateNumber) · Version \(estimate.version)")
                            .font(TypographyTokens.caption)
                            .foregroundStyle(ColorTokens.secondaryText)
                        CurrencyText(amount: estimate.totalAmount, font: TypographyTokens.moneyMedium)
                        Text(estimate.isEditable ? "Draft · Tap to edit line items" : "\(estimate.status.rawValue.capitalized) · Tap to review")
                            .font(TypographyTokens.caption)
                            .foregroundStyle(ColorTokens.secondaryText)
                    }
                    .foregroundStyle(ColorTokens.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint(estimate.isEditable ? "Review and edit this draft estimate" : "Review this saved estimate")

                Divider()
                Menu {
                    Button { onExportEstimate?(estimate.id) } label: {
                        Label("Export branded PDF", systemImage: "arrow.down.doc")
                    }
                    if onCreateProposal != nil && estimate.isEditable {
                        Button { onCreateProposal?(estimate.id) } label: {
                            Label("Create proposal", systemImage: "doc.richtext")
                        }
                    }
                    if onConvertToInvoice != nil {
                        Button { onConvertToInvoice?(estimate.id) } label: {
                            Label("Convert to invoice", systemImage: "doc.plaintext")
                        }
                    }
                } label: {
                    Label("Export & more", systemImage: "square.and.arrow.up")
                        .font(TypographyTokens.subheadline)
                        .foregroundStyle(ColorTokens.primaryText)
                        .frame(minHeight: 44)
                }
                .disabled(exportingEstimateId != nil || convertingEstimateId != nil)
                if exportingEstimateId == estimate.id {
                    ProgressView("Preparing PDF…")
                }
                if convertingEstimateId == estimate.id {
                    ProgressView("Creating invoice…")
                }
                if let saved = exports[estimate.id], !saved.isEmpty {
                    VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                        Text("Saved PDFs")
                            .font(TypographyTokens.caption.weight(.semibold))
                            .foregroundStyle(ColorTokens.secondaryText)
                        ForEach(saved) { export in
                            Button { onTapSavedExport?(export) } label: {
                                Label(export.fileName, systemImage: "doc")
                                    .font(TypographyTokens.subheadline)
                                    .foregroundStyle(ColorTokens.primaryText)
                                    .frame(minHeight: 44, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Open and share this saved PDF")
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ScrollView {
        ProjectEstimatesSection(estimates: [.sample])
    }
}
