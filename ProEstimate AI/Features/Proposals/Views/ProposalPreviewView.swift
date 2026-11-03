import SwiftUI

/// Proposal preview + send screen, presented as a sheet from the project detail
/// screen. Renders the client-facing proposal (hero, intro, scope, timeline,
/// terms), exposes the shareable approval link, and lets the contractor send it.
struct ProposalPreviewView: View {
    @State private var viewModel: ProposalPreviewViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(PaywallPresenter.self) private var paywall
    @State private var destination: ProposalPreviewDestination?
    @State private var revisionDelivery = EstimateDeliveryViewModel(service: EstimateDeliveryService())
    private let client: Client?

    init(proposal: Proposal, reviewedEstimate: Estimate? = nil, client: Client? = nil) {
        self.client = client
        _viewModel = State(initialValue: ProposalPreviewViewModel(proposal: proposal, reviewedEstimate: reviewedEstimate))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SpacingTokens.lg) {
                    heroCard
                    if viewModel.proposal.changesRequestedAt != nil { requestedChangesCard }
                    if viewModel.proposal.isEditableDraft {
                        Button { destination = .document(viewModel.proposal) } label: {
                            Label("Edit scope & terms", systemImage: "square.and.pencil")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isLoading || viewModel.isSending || viewModel.isSavingDocument)
                    }
                    if let comparison = viewModel.proposal.changeOrder { changeOrderReviewCard(comparison) }
                    estimateReviewCard
                    if hasNarrative {
                        narrativeCard
                    }
                    if viewModel.shareURL != nil {
                        shareCard
                    }
                    actions
                    approvalRecordCard
                    if viewModel.proposal.status != .draft {
                        NavigationLink {
                            FollowUpHistoryView(kind: .proposal, entityId: viewModel.proposal.id)
                        } label: {
                            Label("Follow-ups & contact history", systemImage: "envelope.badge")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    }
                    if viewModel.reviewNeedsRefresh {
                        Button("Refresh review") { Task { await viewModel.load() } }
                            .disabled(viewModel.isLoading || viewModel.isSending)
                    }
                    Spacer(minLength: SpacingTokens.lg)
                }
                .padding(SpacingTokens.md)
            }
            .background(ColorTokens.background.ignoresSafeArea())
            .navigationTitle(viewModel.proposal.changeOrder == nil ? "Proposal" : "Change order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(viewModel.isSending || viewModel.isSavingDocument || revisionDelivery.isWorking)
                }
            }
            .overlay {
                if viewModel.isSending {
                    Color.black.opacity(0.2).ignoresSafeArea()
                        .overlay {
                            ProgressView("Sending proposal…")
                                .padding()
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                }
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )
            ) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                if let message = viewModel.errorMessage { Text(message) }
            }
            .task { await viewModel.load() }
            .sheet(item: $destination) { target in
                switch target {
                case let .document(proposal):
                    ProposalDocumentEditorSheet(proposal: proposal) { form in
                        try await viewModel.saveDocument(form)
                    }
                case let .revision(estimate):
                    EstimateEditorView(estimateId: estimate.id, initialNotice: "Revise this draft, then send the updated proposal. The previous version stays available for reference.")
                }
            }
            .refreshable { await viewModel.load() }
            .interactiveDismissDisabled(viewModel.isSending || viewModel.isSavingDocument || revisionDelivery.isWorking)
            .onChange(of: viewModel.failureRevision) { _, _ in
                if let error = viewModel.lastError as? APIError, case let .paywall(decision) = error {
                    paywall.present(decision)
                }
            }
        }
    }

    // MARK: - Hero

    private var requestedChangesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: SpacingTokens.sm) {
                Label("Client requested changes", systemImage: "bubble.left.and.text.bubble.right")
                    .font(TypographyTokens.headline)
                if let message = viewModel.proposal.requestedChangesMessage { Text(message) }
                if let comparison = viewModel.proposal.changeOrder {
                    Text("Keep this sent change order for reference. Open it to review the request and prepare a replacement from the approved contract.")
                        .font(TypographyTokens.footnote).foregroundStyle(.secondary)
                    NavigationLink { ChangeOrderDetailView(orderId: comparison.id) } label: {
                        Label("Open change order", systemImage: "doc.badge.gearshape")
                    }.frame(minHeight: 44)
                } else {
                    Text("Keep this sent version for reference. Create a revision from the estimate to update the offer.")
                        .font(TypographyTokens.footnote).foregroundStyle(.secondary)
                    Button(revisionDelivery.isWorking ? "Creating revision…" : "Create revision") {
                        Task { await createRevision() }
                    }
                    .frame(minHeight: 44)
                    .disabled(viewModel.isLoading || viewModel.isSending || revisionDelivery.isWorking)
                }
                if let error = revisionDelivery.errorMessage { Text(error).font(TypographyTokens.footnote).foregroundStyle(ColorTokens.error) }
            }
        }
    }

    private func createRevision() async {
        await viewModel.load()
        guard let estimate = viewModel.reviewedEstimate, !estimate.isEditable else {
            viewModel.errorMessage = "Refresh the estimate before creating its revision."
            return
        }
        if let revision = await revisionDelivery.revise(estimate: estimate) {
            AppEventBus.shared.noteProjectChange()
            destination = .revision(revision)
        }
    }

    @ViewBuilder
    private var approvalRecordCard: some View {
        if let acceptance = viewModel.proposal.acceptance {
            GlassCard {
                VStack(alignment: .leading, spacing: SpacingTokens.sm) {
                    Label("Approval record", systemImage: "signature").font(TypographyTokens.headline)
                    Text(acceptance.signerName).font(TypographyTokens.subheadline.weight(.semibold))
                    Text(acceptance.acceptedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(TypographyTokens.caption).foregroundStyle(.secondary)
                    Text(acceptance.consentText).font(TypographyTokens.footnote)
                    Text("The entered name is self-attested. Identity was not independently verified.")
                        .font(TypographyTokens.caption).foregroundStyle(.secondary)
                    DisclosureGroup("Document reference") {
                        Text("Version \(acceptance.estimateVersion)").font(TypographyTokens.caption)
                        Text(acceptance.documentHash).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        } else if viewModel.proposal.status == .approved {
            Text("This approval was recorded without a typed acknowledgement.")
                .font(TypographyTokens.footnote).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var estimateReviewCard: some View {
        if let estimate = viewModel.reviewedEstimate {
            GlassCard {
                VStack(alignment: .leading, spacing: SpacingTokens.md) {
                    Text("Review estimate").font(TypographyTokens.headline)
                    if let name = viewModel.proposal.recipientName ?? (viewModel.proposal.isEditableDraft ? client?.name : nil) {
                        Text(name).font(TypographyTokens.subheadline.weight(.semibold))
                        Text(viewModel.proposal.recipientEmail ?? "Share the approval link with the reviewed recipient after sending.")
                            .font(TypographyTokens.caption)
                            .foregroundStyle(ColorTokens.secondaryText)
                    } else if !viewModel.proposal.isEditableDraft {
                        Text("Original recipient details were not recorded for this older proposal.")
                            .font(TypographyTokens.caption).foregroundStyle(.secondary)
                    }
                    if viewModel.proposal.status == .sent || viewModel.proposal.status == .viewed,
                       viewModel.proposal.recipientMatchesCurrent == false {
                        Text("The original recipient is unknown or has changed. Create a revision and review its recipient before emailing again.")
                            .font(TypographyTokens.footnote).foregroundStyle(ColorTokens.warning)
                    }
                    ForEach(viewModel.reviewedLineItems) { item in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                                Text(item.name).font(TypographyTokens.subheadline)
                                HStack(spacing: SpacingTokens.xxs) {
                                    Text("\(NSDecimalNumber(decimal: item.quantity).stringValue) \(item.unit)")
                                    if let price = customerUnitPrice(item) {
                                        Text("·")
                                        CurrencyText(amount: price)
                                        Text("each")
                                    }
                                }
                                .font(TypographyTokens.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: SpacingTokens.sm)
                            CurrencyText(amount: item.lineTotal)
                        }
                    }
                    Divider()
                    HStack {
                        Text(viewModel.proposal.changeOrder == nil ? "Total" : "Revised contract total").font(TypographyTokens.headline)
                        Spacer()
                        CurrencyText(amount: estimate.totalAmount)
                    }
                    if viewModel.proposal.status == .draft {
                        Text("Sending locks this version and activates the approval link. Changes after sending require a revision.")
                            .font(TypographyTokens.footnote)
                            .foregroundStyle(ColorTokens.secondaryText)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        } else if viewModel.isLoading {
            ProgressView("Loading estimate review…")
        }
    }

    private func changeOrderReviewCard(_ comparison: ProposalChangeOrder) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: SpacingTokens.md) {
                Text("Change to approved contract").font(TypographyTokens.caption).foregroundStyle(.secondary)
                Text(comparison.title).font(TypographyTokens.headline)
                Text(comparison.reason).font(TypographyTokens.body)
                changeOrderAmountRow("Previously approved total", comparison.baseTotal)
                changeOrderAmountRow("Revised contract total", comparison.newTotal)
                Divider()
                changeOrderAmountRow(comparison.changeAmount < 0 ? "Contract reduction" : comparison.changeAmount > 0 ? "Contract increase" : "Price change", comparison.changeAmount)
                Text(comparison.billingExplanation).font(TypographyTokens.footnote).foregroundStyle(.secondary)
                DisclosureGroup("Previously approved scope") {
                    VStack(alignment: .leading, spacing: SpacingTokens.sm) {
                        Text("\(comparison.baseEstimateNumber) · Version \(comparison.baseVersion)").font(TypographyTokens.caption).foregroundStyle(.secondary)
                        ForEach(comparison.baseScope.lineItems.indices, id: \.self) { index in
                            let item = comparison.baseScope.lineItems[index]
                            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                                changeOrderAmountRow(item.name, item.lineTotal)
                                Text("\(NSDecimalNumber(decimal: item.quantity).stringValue) \(item.unit)").font(TypographyTokens.caption).foregroundStyle(.secondary)
                                if let description = item.description { Text(description).font(TypographyTokens.footnote) }
                            }
                        }
                        if let assumptions = comparison.baseScope.assumptions { Text("Previous assumptions: \(assumptions)").font(TypographyTokens.footnote) }
                        if let exclusions = comparison.baseScope.exclusions { Text("Previous exclusions: \(exclusions)").font(TypographyTokens.footnote) }
                        Divider()
                        changeOrderAmountRow("Subtotal change", comparison.subtotalDelta)
                        changeOrderAmountRow("Tax change", comparison.taxDelta)
                        changeOrderAmountRow("Discount change (deducted)", comparison.discountDelta)
                    }.padding(.top, SpacingTokens.sm)
                }
                Text("Review the complete revised scope, price and terms below before sending.").font(TypographyTokens.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func changeOrderAmountRow(_ title: String, _ amount: Decimal) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SpacingTokens.md) {
            Text(title).font(TypographyTokens.subheadline)
            Spacer(minLength: SpacingTokens.sm)
            CurrencyText(amount: amount).font(TypographyTokens.subheadline.weight(.semibold))
        }
    }

    private var heroCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: SpacingTokens.sm) {
                if let heroURL = viewModel.proposal.heroImageURL {
                    AsyncImage(url: heroURL) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            placeholderHero
                        case .empty:
                            placeholderHero.overlay { ProgressView() }
                        @unknown default:
                            placeholderHero
                        }
                    }
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.card))
                }

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                        Text(viewModel.proposal.displayTitle)
                            .font(TypographyTokens.title3)
                        if let number = viewModel.proposal.proposalNumber, !number.isEmpty {
                            Text(number)
                                .font(TypographyTokens.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    StatusBadge(text: statusName, style: statusStyle)
                }

                if let expires = viewModel.proposal.expiresAt {
                    HStack(spacing: SpacingTokens.xxs) {
                        Image(systemName: "clock")
                        Text("Expires \(expires.formatted(as: .invoiceDate))")
                    }
                    .font(TypographyTokens.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func customerUnitPrice(_ item: EstimateLineItem) -> Decimal? {
        guard item.quantity > 0 else { return nil }
        var rate = item.lineTotal / item.quantity
        var rounded = Decimal()
        NSDecimalRound(&rounded, &rate, 2, .plain)
        return rounded * item.quantity == item.lineTotal ? rounded : nil
    }

    private var placeholderHero: some View {
        Rectangle()
            .fill(ColorTokens.surface)
            .overlay {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
    }

    // MARK: - Narrative

    private var hasNarrative: Bool {
        [
            viewModel.proposal.introText,
            viewModel.proposal.scopeOfWork,
            viewModel.proposal.timelineText,
            viewModel.proposal.termsAndConditions,
            viewModel.proposal.clientMessage
        ].contains { $0?.isEmpty == false }
    }

    private var narrativeCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: SpacingTokens.md) {
                narrativeSection(title: "Message", text: viewModel.proposal.clientMessage)
                narrativeSection(title: "Introduction", text: viewModel.proposal.introText)
                narrativeSection(title: "Scope of Work", text: viewModel.proposal.scopeOfWork)
                narrativeSection(title: "Timeline", text: viewModel.proposal.timelineText)
                narrativeSection(title: "Terms & Conditions", text: viewModel.proposal.termsAndConditions)
            }
        }
    }

    @ViewBuilder
    private func narrativeSection(title: String, text: String?) -> some View {
        if let text, !text.isEmpty {
            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                Text(title)
                    .font(TypographyTokens.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(ColorTokens.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Share

    private var shareCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: SpacingTokens.sm) {
                Text("Approval Link")
                    .font(TypographyTokens.headline)
                Text("Share this link so your client can review and approve the proposal online.")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(.secondary)

                if let shareURL = viewModel.shareURL {
                    HStack(spacing: SpacingTokens.sm) {
                        ShareLink(item: shareURL) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(TypographyTokens.buttonSecondary)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(ColorTokens.surface, in: RoundedRectangle(cornerRadius: RadiusTokens.button))
                        }

                        Button {
                            viewModel.copyShareLink()
                        } label: {
                            Label(
                                viewModel.didCopyShareLink ? "Copied" : "Copy",
                                systemImage: viewModel.didCopyShareLink ? "checkmark" : "doc.on.doc"
                            )
                            .font(TypographyTokens.buttonSecondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(ColorTokens.surface, in: RoundedRectangle(cornerRadius: RadiusTokens.button))
                        }
                    }
                    .foregroundStyle(ColorTokens.primaryText)
                }
            }
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        if viewModel.proposal.canSend {
            PrimaryCTAButton(
                title: viewModel.proposal.status == .draft ? "Send & lock this version" : "Resend proposal",
                icon: "paperplane.fill",
                isLoading: viewModel.isSending
            ) {
                Task { await viewModel.send() }
            }
            .disabled(!viewModel.canSend)
        } else if viewModel.proposal.hasResponse {
            HStack(spacing: SpacingTokens.xs) {
                Image(systemName: viewModel.proposal.status == .approved ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .foregroundStyle(viewModel.proposal.status == .approved ? ColorTokens.success : ColorTokens.error)
                Text(viewModel.proposal.status == .approved ? "Approved by client" : "Declined by client")
                    .font(TypographyTokens.subheadline.weight(.semibold))
                    .foregroundStyle(viewModel.proposal.status == .approved ? ColorTokens.success : ColorTokens.error)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SpacingTokens.sm)
        }
    }

    // MARK: - Status Presentation

    private var statusName: String {
        if viewModel.proposal.changesRequestedAt != nil { return "Changes requested" }
        return switch viewModel.proposal.status {
        case .draft: "Draft"
        case .sent: "Sent"
        case .viewed: "Viewed"
        case .approved: "Approved"
        case .declined: "Declined"
        case .expired: "Expired"
        }
    }

    private var statusStyle: StatusBadge.Style {
        if viewModel.proposal.changesRequestedAt != nil { return .warning }
        return switch viewModel.proposal.status {
        case .draft: .neutral
        case .sent: .info
        case .viewed: .warning
        case .approved: .success
        case .declined: .error
        case .expired: .neutral
        }
    }
}

private enum ProposalPreviewDestination: Identifiable {
    case document(Proposal)
    case revision(Estimate)
    var id: String {
        switch self {
        case let .document(proposal): "document-\(proposal.id)"
        case let .revision(estimate): "revision-\(estimate.id)"
        }
    }
}

// MARK: - Preview

#Preview {
    ProposalPreviewView(proposal: .sample)
}
