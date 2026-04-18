import SwiftUI

struct EstimateEditorView: View {
    let estimateId: String
    var initialDIY: Bool = false
    @State private var viewModel = EstimateEditorViewModel()
    @State private var exportedPDF: ExportedPDF?
    @State private var isExportingPDF = false
    @State private var isCreatingProposal = false
    @State private var showDiscardConfirmation = false

    /// Identifiable wrapper so `.sheet(item:)` can drive the share sheet
    /// without the race that kills `.sheet(isPresented:) + if let url`.
    private struct ExportedPDF: Identifiable, Hashable {
        let url: URL
        var id: URL { url }
    }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresentedBySheet
    @Environment(FeatureGateCoordinator.self) private var featureGateCoordinator
    @Environment(PaywallPresenter.self) private var paywallPresenter
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if viewModel.isLoading {
                    LoadingStateView(message: "Loading estimate...")
                } else if viewModel.estimate != nil {
                    editorContent
                } else if let errorMessage = viewModel.errorMessage {
                    RetryStateView(message: errorMessage) {
                        Task { await viewModel.loadEstimate(id: estimateId) }
                    }
                } else {
                    EmptyStateView(
                        icon: "doc.text",
                        title: "Estimate Not Found",
                        subtitle: "This estimate could not be loaded."
                    )
                }
            }
        }
        .navigationTitle(viewModel.estimate?.estimateNumber ?? "New Estimate")
        .navigationBarTitleDisplayMode(.inline)
        // Prevent swipe-to-dismiss losing unsaved work; the explicit Close
        // button below shows a confirmation dialog when changes are pending.
        .interactiveDismissDisabled(viewModel.hasUnsavedChanges)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { handleCloseTap() }
            }

            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: SpacingTokens.sm) {
                    if viewModel.hasUnsavedChanges {
                        Text("Unsaved")
                            .font(TypographyTokens.caption)
                            .foregroundStyle(ColorTokens.warning)
                    }

                    Text(viewModel.versionDisplay)
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, SpacingTokens.xs)
                        .padding(.vertical, SpacingTokens.xxs)
                        .background(ColorTokens.inputBackground, in: Capsule())

                    Button {
                        Task { await viewModel.save() }
                    } label: {
                        if viewModel.isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(viewModel.isSaving || !viewModel.hasUnsavedChanges)

                    Menu {
                        Button {
                            handleExportPDF()
                        } label: {
                            Label("Export PDF", systemImage: "arrow.down.doc")
                        }
                        .disabled(isExportingPDF)

                        Button {
                            handleCreateProposal()
                        } label: {
                            Label("Create Proposal", systemImage: "doc.richtext")
                        }
                        .disabled(isCreatingProposal)
                    } label: {
                        if isCreatingProposal || isExportingPDF {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .accessibilityLabel("Share and export")
                    .accessibilityHint("Export PDF or create proposal")
                }
            }
        }
        .task {
            viewModel.isDIY = initialDIY
            await viewModel.loadEstimate(id: estimateId)
        }
        .sheet(isPresented: $viewModel.isLineItemSheetPresented) {
            if let draft = viewModel.editingLineItem {
                LineItemEditSheet(
                    draft: draft,
                    onSave: { updatedDraft in
                        viewModel.saveEditingLineItem(updatedDraft)
                    },
                    onCancel: {
                        viewModel.isLineItemSheetPresented = false
                        viewModel.editingLineItem = nil
                    }
                )
                .presentationDetents([.large])
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
        .alert("Success", isPresented: .init(
            get: { viewModel.successMessage != nil },
            set: { if !$0 { viewModel.successMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.successMessage = nil }
        } message: {
            Text(viewModel.successMessage ?? "")
        }
        .sheet(item: $exportedPDF) { pdf in
            ActivityViewRepresentable(activityItems: [pdf.url])
        }
        .confirmationDialog(
            "Discard changes?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("You have unsaved edits that will be lost if you close now.")
        }
    }

    // MARK: - Close Handling

    /// Close tap handler that shows a confirmation if there are unsaved changes.
    private func handleCloseTap() {
        if viewModel.hasUnsavedChanges {
            showDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    // MARK: - Feature-Gated Actions

    private func handleExportPDF() {
        let result = featureGateCoordinator.guardExportQuote()
        switch result {
        case .allowed:
            guard !isExportingPDF else { return }
            isExportingPDF = true
            Task {
                // Save any pending edits first so the PDF reflects what the
                // user actually sees on screen. If the server-side save
                // fails, still attempt to export the local snapshot —
                // better than nothing.
                if viewModel.hasUnsavedChanges {
                    await viewModel.save()
                }

                // Re-hop to MainActor for the PDF render (UIKit graphics) +
                // state mutation.
                await MainActor.run {
                    let branding = brandingFromAppState()
                    if let url = viewModel.generatePDF(branding: branding, client: nil) {
                        exportedPDF = ExportedPDF(url: url)
                    } else {
                        viewModel.errorMessage = "Couldn't build the PDF. Make sure the estimate has at least one line item and try again."
                    }
                    isExportingPDF = false
                }
            }
        case .blocked(let decision):
            paywallPresenter.present(decision)
        }
    }

    /// Build a `PDFGenerator.CompanyBranding` from the signed-in user's
    /// company snapshot. AppState only carries a lightweight snapshot
    /// (id, name, logoURL) — full branding (phone, email, address,
    /// accent color) would require loading the full `Company` record.
    /// Uses sensible defaults when those fields aren't available.
    private func brandingFromAppState() -> PDFGenerator.CompanyBranding {
        let companyName = appState.currentCompany?.name ?? "ProEstimate AI"
        // Logo image is deferred — loading via URLSession here would block
        // the render. If set, future work can preload it into AppState.
        return PDFGenerator.CompanyBranding(
            name: companyName,
            phone: nil,
            email: nil,
            addressLines: [],
            websiteUrl: nil,
            logoImage: nil,
            accentHex: "#FF9230"
        )
    }

    private func handleCreateProposal() {
        guard let estimate = viewModel.estimate, !isCreatingProposal else { return }

        // Save unsaved changes first, then create proposal
        isCreatingProposal = true
        Task {
            if viewModel.hasUnsavedChanges {
                await viewModel.save()
            }

            do {
                let service = LiveProposalService()
                let proposal = try await service.generateFromEstimate(estimateId: estimate.id)
                isCreatingProposal = false
                dismiss()
                // Navigate to proposal preview after a brief delay to let dismiss complete
                try? await Task.sleep(nanoseconds: 300_000_000)
                router.navigate(to: .proposalPreview(id: proposal.id))
            } catch {
                isCreatingProposal = false
                viewModel.errorMessage = "Failed to create proposal: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Editor Content

    private var editorContent: some View {
        VStack(spacing: 0) {
            List {
                // Header summary
                headerSection

                // DIY / Professional toggle
                diyToggleSection

                // Materials section
                EstimateSectionView(
                    category: .materials,
                    items: viewModel.materialItems,
                    subtotal: viewModel.subtotalMaterials,
                    isExpanded: $viewModel.isMaterialsSectionExpanded,
                    onAddItem: { viewModel.addLineItem(category: .materials) },
                    onEditItem: { viewModel.editLineItem($0) },
                    onDuplicateItem: { viewModel.duplicateLineItem(id: $0) },
                    onDeleteItem: { viewModel.deleteLineItem(id: $0) },
                    onMoveItem: { from, to in
                        viewModel.moveLineItem(from: from, to: to, category: .materials)
                    }
                )

                // Labor section — hidden in DIY mode
                if !viewModel.isDIY {
                    EstimateSectionView(
                        category: .labor,
                        items: viewModel.laborItems,
                        subtotal: viewModel.subtotalLabor,
                        isExpanded: $viewModel.isLaborSectionExpanded,
                        onAddItem: { viewModel.addLineItem(category: .labor) },
                        onEditItem: { viewModel.editLineItem($0) },
                        onDuplicateItem: { viewModel.duplicateLineItem(id: $0) },
                        onDeleteItem: { viewModel.deleteLineItem(id: $0) },
                        onMoveItem: { from, to in
                            viewModel.moveLineItem(from: from, to: to, category: .labor)
                        }
                    )
                }

                // Other section
                EstimateSectionView(
                    category: .other,
                    items: viewModel.otherItems,
                    subtotal: viewModel.subtotalOther,
                    isExpanded: $viewModel.isOtherSectionExpanded,
                    onAddItem: { viewModel.addLineItem(category: .other) },
                    onEditItem: { viewModel.editLineItem($0) },
                    onDuplicateItem: { viewModel.duplicateLineItem(id: $0) },
                    onDeleteItem: { viewModel.deleteLineItem(id: $0) },
                    onMoveItem: { from, to in
                        viewModel.moveLineItem(from: from, to: to, category: .other)
                    }
                )

                // Notes section
                notesSection

                // Bottom spacer for totals bar
                Section {
                    Color.clear
                        .frame(height: 80)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)

            // Sticky bottom totals bar
            EstimateTotalsView(
                subtotalMaterials: viewModel.subtotalMaterials,
                subtotalLabor: viewModel.isDIY ? 0 : viewModel.subtotalLabor,
                subtotalOther: viewModel.subtotalOther,
                taxAmount: viewModel.isDIY ? viewModel.materialsTaxOnly : viewModel.taxAmount,
                discountAmount: $viewModel.discountAmount,
                grandTotal: viewModel.isDIY ? viewModel.diyGrandTotal : viewModel.grandTotal
            )
        }
    }

    private var diyToggleSection: some View {
        Section {
            HStack(spacing: SpacingTokens.sm) {
                Image(systemName: viewModel.isDIY ? "wrench.and.screwdriver" : "person.badge.shield.checkmark")
                    .font(.title3)
                    .foregroundStyle(viewModel.isDIY ? ColorTokens.primaryOrange : ColorTokens.accentBlue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.isDIY ? "DIY Estimate" : "Professional Estimate")
                        .font(TypographyTokens.headline)
                    Text(viewModel.isDIY
                        ? "Materials & supplies only — no labor costs"
                        : "Includes professional installation labor")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { !viewModel.isDIY },
                    set: { newValue in
                        viewModel.isDIY = !newValue
                        viewModel.hasUnsavedChanges = true
                    }
                ))
                .labelsHidden()
                .tint(ColorTokens.accentBlue)
            }
        }
    }

    private var headerSection: some View {
        Section {
            HStack(spacing: SpacingTokens.md) {
                MetricCard(label: "Items", value: "\(viewModel.totalItemCount)")
                    .frame(maxWidth: .infinity)

                if let estimate = viewModel.estimate {
                    MetricCard(
                        label: "Status",
                        value: estimate.status.rawValue.capitalized
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextEditor(text: $viewModel.notes)
                .frame(minHeight: 60)
                .font(TypographyTokens.body)
                .onChange(of: viewModel.notes) { _, _ in
                    viewModel.hasUnsavedChanges = true
                }
        }
    }

}

// MARK: - Preview

#Preview {
    NavigationStack {
        EstimateEditorView(estimateId: "e-001")
    }
    .environment(FeatureGateCoordinator.preview())
    .environment(PaywallPresenter())
    .environment(AppRouter())
}
