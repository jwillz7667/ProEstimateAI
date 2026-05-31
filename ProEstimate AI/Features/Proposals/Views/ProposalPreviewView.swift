import SwiftUI

/// Proposal preview + send screen, presented as a sheet from the project detail
/// screen. Renders the client-facing proposal (hero, intro, scope, timeline,
/// terms), exposes the shareable approval link, and lets the contractor send it.
struct ProposalPreviewView: View {
    @State private var viewModel: ProposalPreviewViewModel
    @Environment(\.dismiss) private var dismiss

    init(proposal: Proposal) {
        _viewModel = State(initialValue: ProposalPreviewViewModel(proposal: proposal))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SpacingTokens.lg) {
                    heroCard
                    if hasNarrative {
                        narrativeCard
                    }
                    if viewModel.shareURL != nil {
                        shareCard
                    }
                    actions
                    Spacer(minLength: SpacingTokens.lg)
                }
                .padding(SpacingTokens.md)
            }
            .background(ColorTokens.background.ignoresSafeArea())
            .navigationTitle("Proposal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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
        }
    }

    // MARK: - Hero

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
                title: viewModel.proposal.status == .sent ? "Resend Proposal" : "Send Proposal to Client",
                icon: "paperplane.fill",
                isLoading: viewModel.isSending
            ) {
                Task { await viewModel.send() }
            }
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
        switch viewModel.proposal.status {
        case .draft: "Draft"
        case .sent: "Sent"
        case .viewed: "Viewed"
        case .approved: "Approved"
        case .declined: "Declined"
        case .expired: "Expired"
        }
    }

    private var statusStyle: StatusBadge.Style {
        switch viewModel.proposal.status {
        case .draft: .neutral
        case .sent: .info
        case .viewed: .warning
        case .approved: .success
        case .declined: .error
        case .expired: .neutral
        }
    }
}

// MARK: - Preview

#Preview {
    ProposalPreviewView(proposal: .sample)
}
