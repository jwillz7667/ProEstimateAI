import SwiftUI

struct EstimateEditorView: View {
    let estimateId: String
    var initialDIY: Bool = false
    @State private var viewModel = EstimateEditorViewModel()
    @State private var exportPDFURL: URL?
    @State private var showShareSheet = false
    @State private var isCreatingProposal = false
    @Environment(\.dismiss) private var dismiss
    @Environment(FeatureGateCoordinator.self) private var featureGateCoordinator
    @Environment(PaywallPresenter.self) private var paywallPresenter
    @Environment(AppRouter.self) private var router

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if viewModel.isLoading {
                    LoadingStateView(message: "Loading estimate...")
                } else if viewModel.estimate != nil {
                    editorContent
                } else if let errorMessage = viewModel.errorMessage {
                    errorState(message: errorMessage)
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: SpacingTokens.sm) {
                    if viewModel.hasUnsavedChanges {
                        Text("Unsaved")
                            .font(TypographyTokens.caption)
                            .foregroundStyle(.orange)
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
                        ShareLink(item: "Estimate \(viewModel.estimate?.estimateNumber ?? "")")

                        Button {
                            handleExportPDF()
                        } label: {
                            Label("Export PDF", systemImage: "arrow.down.doc")
                        }

                        Button {
                            handleCreateProposal()
                        } label: {
                            Label("Create Proposal", systemImage: "doc.richtext")
                        }
                    } label: {
                        if isCreatingProposal {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
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
        .sheet(isPresented: $showShareSheet) {
            if let url = exportPDFURL {
                ActivityViewRepresentable(activityItems: [url])
            }
        }
    }

    // MARK: - Feature-Gated Actions

    private func handleExportPDF() {
        let result = featureGateCoordinator.guardExportQuote()
        switch result {
        case .allowed:
            if let url = viewModel.generatePDF() {
                exportPDFURL = url
                showShareSheet = true
            }
        case .blocked(let decision):
            paywallPresenter.present(decision)
        }
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
                    .foregroundStyle(viewModel.isDIY ? ColorTokens.primaryOrange : .blue)

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
                .tint(.blue)
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

    private func errorState(message: String) -> some View {
        VStack(spacing: SpacingTokens.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(ColorTokens.warning)

            Text("Failed to Load")
                .font(TypographyTokens.title3)

            Text(message)
                .font(TypographyTokens.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            PrimaryCTAButton(title: "Try Again") {
                Task { await viewModel.loadEstimate(id: estimateId) }
            }
            .frame(maxWidth: 200)
        }
        .padding(SpacingTokens.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
