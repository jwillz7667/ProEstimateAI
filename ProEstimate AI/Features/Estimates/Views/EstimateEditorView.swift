import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

struct EstimateEditorView: View {
    let estimateId: String
    var initialDIY: Bool = false
    @State private var viewModel = EstimateEditorViewModel()
    @State private var exportedPDF: ExportedPDF?
    @State private var isExportingPDF = false
    @State private var isCreatingProposal = false
    @State private var showDiscardConfirmation = false
    @State private var exportProgressMessage: String?
    /// Whether the contractor wants the before / after images embedded in
    /// the exported PDF. Defaults on so the rich proposal is the
    /// out-of-the-box result; flipping off produces a numbers-only PDF.
    @AppStorage("estimatePDFIncludeBeforeAfter")
    private var includeBeforeAfterImages: Bool = true

    /// Identifiable wrapper so `.sheet(item:)` can drive the share sheet
    /// without the race that kills `.sheet(isPresented:) + if let url`.
    private struct ExportedPDF: Identifiable, Hashable {
        let url: URL
        var id: URL {
            url
        }
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

            if isExportingPDF, let message = exportProgressMessage {
                exportProgressOverlay(message: message)
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

    /// Export the current estimate to a fully branded PDF. The heavy lift
    /// lives in `performBrandedExport`: it asynchronously pulls the full
    /// company record, the project + its client, and downloads the logo
    /// plus before/after images in parallel, then hands everything to
    /// `PDFGenerator`. Any individual fetch can fail — the PDF still goes
    /// out, just with fewer adornments — so the user always gets a file.
    private func handleExportPDF() {
        let result = featureGateCoordinator.guardExportQuote()
        switch result {
        case .allowed:
            guard !isExportingPDF else { return }
            isExportingPDF = true
            exportProgressMessage = "Preparing estimate..."
            Task {
                if viewModel.hasUnsavedChanges {
                    await viewModel.save()
                }
                let url = await performBrandedExport()
                await MainActor.run {
                    if let url {
                        exportedPDF = ExportedPDF(url: url)
                    } else {
                        viewModel.errorMessage = "Couldn't build the PDF. Make sure the estimate has at least one line item and try again."
                    }
                    isExportingPDF = false
                    exportProgressMessage = nil
                }
            }
        case let .blocked(decision):
            paywallPresenter.present(decision)
        }
    }

    /// Fetches every piece of contextual data the estimate PDF needs and
    /// then renders it. Fail-soft: each optional fetch is independent, so a
    /// missing logo or generation doesn't kill the export.
    private func performBrandedExport() async -> URL? {
        guard let estimate = viewModel.estimate else { return nil }
        let projectId = estimate.projectId

        await setProgress("Fetching branding...")

        // 1. Full Company (may not be in AppState if the user hasn't visited
        // Settings yet). Fail-soft: fall back to the minimal AppState
        // snapshot if this 404s or the network drops.
        let settingsService = LiveSettingsService()
        let projectService = LiveProjectService()

        async let companyTask: Company? = try? await settingsService.loadCompanySettings()
        async let projectTask: Project? = try? await projectService.getProject(id: projectId)
        async let assetsTask: [Asset] = (try? await APIClient.shared.request(.listAssets(projectId: projectId))) ?? []
        async let generationsTask: [AIGeneration] = (try? await APIClient.shared.request(.listGenerations(projectId: projectId))) ?? []

        let company = await companyTask
        let project = await projectTask
        let assets = await assetsTask
        let generations = await generationsTask

        await setProgress("Downloading images...")

        // 2. Identify images to fetch.
        let beforeURL = assets
            .filter { $0.assetType == .original }
            .sorted { $0.sortOrder < $1.sortOrder || ($0.sortOrder == $1.sortOrder && $0.createdAt < $1.createdAt) }
            .first?
            .url

        let afterURL = generations
            .filter { $0.status == .completed }
            .sorted { $0.createdAt > $1.createdAt }
            .first?
            .previewURL

        let logoURL = company?.logoURL ?? appState.currentCompany?.logoURL

        // Parallel image downloads. Each fetch is independently optional.
        // The before/after fetches are skipped entirely when the contractor
        // toggled the "Include before/after on PDF" setting off.
        async let logoFetch: UIImage? = logoURL.flatMap { url in Task { try? await ImageFetcher.fetch(url) } }?.value
        async let beforeFetch: UIImage? = (includeBeforeAfterImages ? beforeURL : nil)
            .flatMap { url in Task { try? await ImageFetcher.fetch(url) } }?.value
        async let afterFetch: UIImage? = (includeBeforeAfterImages ? afterURL : nil)
            .flatMap { url in Task { try? await ImageFetcher.fetch(url) } }?.value

        let logoImage = await logoFetch
        let beforeImage = await beforeFetch
        let afterImage = await afterFetch

        // 3. Client resolution for the "Prepared For" block.
        let client = await resolveClient(for: project)

        // 4. Branding composition — prefer the freshly-fetched Company; fall
        // back to the AppState snapshot; fall back to bare defaults.
        let branding = buildBranding(from: company, logoImage: logoImage)

        await setProgress("Rendering PDF...")

        return await MainActor.run {
            viewModel.generatePDF(
                branding: branding,
                client: client,
                beforeImage: beforeImage,
                afterImage: afterImage,
                projectTitle: project?.title
            )
        }
    }

    @MainActor
    private func setProgress(_ message: String) {
        exportProgressMessage = message
    }

    private func resolveClient(for project: Project?) async -> PDFGenerator.ClientInfo? {
        guard let clientId = project?.clientId, !clientId.isEmpty else { return nil }
        guard let record: Client = try? await APIClient.shared.request(.getClient(id: clientId)) else {
            return nil
        }
        let addressLines = AppState.CurrentCompany.composeAddressLines(
            street: record.address,
            city: record.city,
            state: record.state,
            zip: record.zip
        )
        return PDFGenerator.ClientInfo(
            name: record.name,
            company: nil,
            phone: record.phone,
            email: record.email,
            addressLines: addressLines
        )
    }

    private func buildBranding(from company: Company?, logoImage: UIImage?) -> PDFGenerator.CompanyBranding {
        if let company {
            let addressLines = AppState.CurrentCompany.composeAddressLines(
                street: company.address,
                city: company.city,
                state: company.state,
                zip: company.zip
            )
            return PDFGenerator.CompanyBranding(
                name: company.name,
                phone: company.phone,
                email: company.email,
                addressLines: addressLines,
                websiteUrl: company.websiteUrl,
                logoImage: logoImage,
                accentHex: company.primaryColor
            )
        }
        let snapshot = appState.currentCompany
        return PDFGenerator.CompanyBranding(
            name: snapshot?.name ?? "ProEstimate AI",
            phone: snapshot?.phone,
            email: snapshot?.email,
            addressLines: snapshot?.addressLines ?? [],
            websiteUrl: snapshot?.websiteUrl,
            logoImage: logoImage,
            accentHex: snapshot?.primaryColorHex
        )
    }

    // MARK: - Branding Completeness

    /// Derived from the AppState snapshot; drives the incomplete-branding
    /// banner and the PDF hardening guidance. Mirrors the
    /// `SettingsViewModel.isBrandingComplete` rule so the user sees the same
    /// criteria here and in Settings.
    private var isBrandingComplete: Bool {
        guard let snapshot = appState.currentCompany else { return false }
        guard !snapshot.name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        let hasContact = (snapshot.phone?.isEmpty == false) || (snapshot.email?.isEmpty == false)
        let hasAddress = snapshot.addressLines.contains { !$0.isEmpty }
        let hasLogo = snapshot.logoURL != nil
        return hasContact && hasAddress && hasLogo
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

                // Incomplete branding nudge — shown before the DIY toggle so
                // it's the first thing a contractor sees when about to ship
                // a bare-bones PDF.
                if !isBrandingComplete {
                    brandingNudgeSection
                }

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

                // PDF export options — controls what shows up in the
                // exported / shared PDF without touching the line items.
                pdfOptionsSection

                // Notes section
                notesSection

                // Bottom spacer for totals bar
                Section {
                    Color.clear
                        .frame(height: 80)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(ColorTokens.background)

            // Sticky bottom totals bar — gains per-visit / monthly / annual
            // / contract-total rollup rows when the parent project is a
            // recurring service contract (LAWN_CARE).
            EstimateTotalsView(
                subtotalMaterials: viewModel.subtotalMaterials,
                subtotalLabor: viewModel.isDIY ? 0 : viewModel.subtotalLabor,
                subtotalOther: viewModel.subtotalOther,
                taxAmount: viewModel.isDIY ? viewModel.materialsTaxOnly : viewModel.taxAmount,
                discountAmount: $viewModel.discountAmount,
                grandTotal: viewModel.isDIY ? viewModel.diyGrandTotal : viewModel.grandTotal,
                recurring: viewModel.recurringContext
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

    /// Toggle row for PDF export options. Currently surfaces a single
    /// preference: whether the contractor's original (before) photo and
    /// the AI-generated (after) preview both appear in the exported
    /// estimate / proposal PDF. Persists across sessions via @AppStorage
    /// so a contractor who doesn't want client-facing AI imagery only has
    /// to flip it once.
    private var pdfOptionsSection: some View {
        Section {
            HStack(spacing: SpacingTokens.sm) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title3)
                    .foregroundStyle(ColorTokens.primaryOrange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Before & After on PDF")
                        .font(TypographyTokens.headline)
                    Text(includeBeforeAfterImages
                        ? "Both images appear on the exported estimate"
                        : "PDF will export numbers-only (no images)")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: $includeBeforeAfterImages)
                    .labelsHidden()
                    .tint(ColorTokens.primaryOrange)
            }
        } header: {
            Text("PDF Options")
        } footer: {
            Text("Includes the original property photo + AI-generated preview side-by-side on the proposal/estimate PDF you send to clients.")
        }
    }

    private var brandingNudgeSection: some View {
        Section {
            HStack(alignment: .top, spacing: SpacingTokens.sm) {
                Image(systemName: "paintbrush.pointed")
                    .font(.title3)
                    .foregroundStyle(ColorTokens.primaryOrange)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Complete your branding")
                        .font(TypographyTokens.headline)
                    Text("Add your logo, address, and contact info in Settings so every estimate PDF goes out on a professional letterhead.")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        openBrandingSettings()
                    } label: {
                        Text("Complete in Settings")
                            .font(TypographyTokens.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(ColorTokens.primaryOrange)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            .padding(.vertical, SpacingTokens.xs)
        }
    }

    private func openBrandingSettings() {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            appState.selectedTab = .settings
            router.settingsPath.append(AppDestination.companyBranding)
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

    private func exportProgressOverlay(message: String) -> some View {
        VStack(spacing: SpacingTokens.sm) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(TypographyTokens.subheadline)
                .foregroundStyle(.primary)
        }
        .padding(SpacingTokens.lg)
        .frame(maxWidth: 260)
        .glassCard()
        .padding(SpacingTokens.md)
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
    .environment(AppState())
}
