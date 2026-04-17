import SwiftUI

struct ProposalPreviewView: View {
    let proposalId: String
    @State private var viewModel = ProposalViewModel()
    @State private var exportPDFURL: URL?
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @Environment(FeatureGateCoordinator.self) private var featureGateCoordinator
    @Environment(PaywallPresenter.self) private var paywallPresenter

    var body: some View {
        Group {
            if viewModel.isLoading {
                LoadingStateView(message: "Loading proposal...")
            } else if viewModel.proposal != nil {
                proposalContent
            } else if let error = viewModel.errorMessage {
                RetryStateView(message: error) {
                    Task { await viewModel.loadProposal(id: proposalId) }
                }
            } else {
                EmptyStateView(
                    icon: "doc.richtext",
                    title: "Proposal Not Found",
                    subtitle: "This proposal could not be loaded."
                )
            }
        }
        .navigationTitle("Proposal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: SpacingTokens.sm) {
                    if let proposal = viewModel.proposal {
                        StatusBadge(
                            text: proposal.status.rawValue.capitalized,
                            style: viewModel.statusBadgeStyle
                        )
                    }

                    Menu {
                        if let shareURL = viewModel.shareURL {
                            Button {
                                handleShareApprovalLink(shareURL)
                            } label: {
                                Label("Share Link", systemImage: "link")
                            }
                        }

                        Button {
                            handleExportPDF()
                        } label: {
                            Label("Export PDF", systemImage: "arrow.down.doc")
                        }

                        if viewModel.canSend {
                            Button {
                                handleSendProposal()
                            } label: {
                                Label("Send to Client", systemImage: "paperplane")
                            }
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share and export")
                    .accessibilityHint("Share link, export PDF, or send to client")
                }
            }
        }
        .task {
            await viewModel.loadProposal(id: proposalId)
        }
        .sheet(isPresented: $showShareSheet) {
            if !shareItems.isEmpty {
                ActivityViewRepresentable(activityItems: shareItems)
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
    }

    // MARK: - Feature-Gated Actions

    private func handleExportPDF() {
        let result = featureGateCoordinator.guardExportQuote()
        switch result {
        case .allowed:
            let allItems = viewModel.lineItems
            let lineItemTuples: [(name: String, qty: Decimal, unit: String, unitCost: Decimal, total: Decimal)] =
                allItems.map { ($0.name, $0.quantity, $0.unit, $0.unitCost, $0.lineTotal) }

            if let url = PDFGenerator.generateProposalPDF(
                companyName: viewModel.company?.name ?? "Company",
                projectTitle: viewModel.project?.title ?? "Project",
                clientName: viewModel.client?.name,
                proposalDate: viewModel.proposal?.createdAt ?? Date(),
                expiresAt: viewModel.proposal?.expiresAt,
                clientMessage: viewModel.proposal?.clientMessage,
                lineItems: lineItemTuples,
                subtotalMaterials: viewModel.estimate?.subtotalMaterials ?? 0,
                subtotalLabor: viewModel.estimate?.subtotalLabor ?? 0,
                subtotalOther: viewModel.estimate?.subtotalOther ?? 0,
                taxAmount: viewModel.estimate?.taxAmount ?? 0,
                totalAmount: viewModel.estimate?.totalAmount ?? 0,
                termsAndConditions: viewModel.proposal?.termsAndConditions
            ) {
                shareItems = [url]
                showShareSheet = true
            }
        case .blocked(let decision):
            paywallPresenter.present(decision)
        }
    }

    private func handleShareApprovalLink(_ url: URL) {
        let result = featureGateCoordinator.guardShareApprovalLink()
        switch result {
        case .allowed:
            shareItems = [url]
            showShareSheet = true
        case .blocked(let decision):
            paywallPresenter.present(decision)
        }
    }

    private func handleSendProposal() {
        let result = featureGateCoordinator.guardShareApprovalLink()
        switch result {
        case .allowed:
            Task { await viewModel.sendProposal() }
        case .blocked(let decision):
            paywallPresenter.present(decision)
        }
    }

    // MARK: - Proposal Content

    private var proposalContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Company header
                companyHeader

                // Hero section
                ProposalHeroSection(
                    heroImageURL: viewModel.proposal?.heroImageURL,
                    projectTitle: viewModel.project?.title ?? "Project",
                    clientName: viewModel.client?.name,
                    date: viewModel.formattedDate
                )

                // Client message
                if let message = viewModel.proposal?.clientMessage, !message.isEmpty {
                    clientMessageSection(message)
                }

                // Scope section
                ProposalScopeSection(
                    project: viewModel.project,
                    estimate: viewModel.estimate,
                    materialItemCount: viewModel.materialLineItems.count,
                    laborItemCount: viewModel.laborLineItems.count,
                    otherItemCount: viewModel.otherLineItems.count
                )

                Divider()
                    .padding(.horizontal, SpacingTokens.lg)

                // Estimate table
                ProposalEstimateTableSection(
                    materialItems: viewModel.materialLineItems,
                    laborItems: viewModel.laborLineItems,
                    otherItems: viewModel.otherLineItems,
                    estimate: viewModel.estimate
                )

                // Terms & conditions
                if let terms = viewModel.proposal?.termsAndConditions, !terms.isEmpty {
                    termsSection(terms)
                }

                // Company footer
                companyFooter

                // Send button (for draft proposals)
                if viewModel.canSend {
                    sendSection
                }
            }
        }
    }

    // MARK: - Subviews

    private var companyHeader: some View {
        VStack(spacing: SpacingTokens.xs) {
            if let logoURL = viewModel.company?.logoURL {
                AsyncImage(url: logoURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 48)
                } placeholder: {
                    companyLogoPlaceholder
                }
            } else {
                companyLogoPlaceholder
            }

            Text(viewModel.company?.name ?? "Company")
                .font(TypographyTokens.title3)

            Text("PROPOSAL")
                .font(TypographyTokens.caption)
                .fontWeight(.bold)
                .tracking(4)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, SpacingTokens.lg)
        .frame(maxWidth: .infinity)
    }

    private var companyLogoPlaceholder: some View {
        Image("housd-icon-light")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 48, height: 48)
    }

    private func clientMessageSection(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            Text("Message")
                .font(TypographyTokens.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Text(message)
                .font(TypographyTokens.body)
                .foregroundStyle(.primary)
        }
        .padding(SpacingTokens.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorTokens.surface)
    }

    private func termsSection(_ terms: String) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            Divider()
                .padding(.horizontal, SpacingTokens.lg)

            VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                Text("Terms & Conditions")
                    .font(TypographyTokens.subheadline)
                    .fontWeight(.semibold)

                Text(terms)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(SpacingTokens.lg)
        }
    }

    private var companyFooter: some View {
        VStack(spacing: SpacingTokens.xs) {
            Divider()

            VStack(spacing: SpacingTokens.xxs) {
                Text(viewModel.company?.name ?? "")
                    .font(TypographyTokens.subheadline)
                    .fontWeight(.semibold)

                if let address = viewModel.companyAddress {
                    Text(address)
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: SpacingTokens.md) {
                    if let phone = viewModel.company?.phone {
                        Label(phone, systemImage: "phone")
                            .font(TypographyTokens.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let email = viewModel.company?.email {
                        Label(email, systemImage: "envelope")
                            .font(TypographyTokens.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, SpacingTokens.lg)
        }
    }

    private var sendSection: some View {
        VStack(spacing: SpacingTokens.sm) {
            PrimaryCTAButton(
                title: "Send Proposal",
                icon: "paperplane",
                isLoading: viewModel.isSending
            ) {
                handleSendProposal()
            }

            if let expiryDate = viewModel.formattedExpiryDate {
                Text("Expires \(expiryDate)")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(SpacingTokens.lg)
    }

}

// MARK: - Preview

#Preview {
    NavigationStack {
        ProposalPreviewView(proposalId: "prop-001")
    }
    .environment(FeatureGateCoordinator.preview())
    .environment(PaywallPresenter())
}
