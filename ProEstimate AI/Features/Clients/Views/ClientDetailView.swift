import SwiftUI

struct ClientDetailView: View {
    let clientId: String
    var onClientUpdated: ((Client) -> Void)?

    @Environment(AppRouter.self) private var router
    @State private var client: Client?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingEditSheet = false
    @State private var estimates: [Estimate] = []
    @State private var isLoadingEstimates = false
    @State private var estimatesError: String?

    private let clientService: ClientServiceProtocol = LiveClientService()
    private let estimateService: EstimateServiceProtocol = LiveEstimateService()

    var body: some View {
        Group {
            if isLoading {
                LoadingStateView(message: "Loading client...")
            } else if let errorMessage, client == nil {
                RetryStateView(message: errorMessage) {
                    Task { await loadClient() }
                }
            } else if let client {
                clientContent(client)
            }
        }
        .navigationTitle(client?.name ?? "Client")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    showingEditSheet = true
                }
                .tint(ColorTokens.primaryOrange)
            }
        }
        .task {
            await loadClient()
            await loadEstimates()
        }
        .sheet(isPresented: $showingEditSheet) {
            if let client {
                ClientFormView(client: client) { updatedClient in
                    self.client = updatedClient
                    onClientUpdated?(updatedClient)
                }
            }
        }
    }

    // MARK: - Content

    private func clientContent(_ client: Client) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingTokens.lg) {
                // MARK: - Header

                clientHeader(client)
                    .padding(.horizontal, SpacingTokens.md)

                // MARK: - Contact Info

                contactInfoSection(client)

                // MARK: - Address

                if client.formattedAddress != nil {
                    addressSection(client)
                }

                // MARK: - Notes

                if let notes = client.notes, !notes.isEmpty {
                    notesSection(notes)
                }

                // MARK: - Projects

                projectsSection

                // MARK: - Estimates & Invoices

                estimatesSection
            }
            .padding(.top, SpacingTokens.sm)
            .padding(.bottom, SpacingTokens.xxl)
        }
    }

    // MARK: - Header

    private func clientHeader(_ client: Client) -> some View {
        HStack(spacing: SpacingTokens.md) {
            AvatarView(name: client.name, size: 64)

            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                Text(client.name)
                    .font(TypographyTokens.title2)

                if let email = client.email {
                    Text(email)
                        .font(TypographyTokens.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text("Client since \(client.createdAt.formatted(as: .medium))")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Contact Info

    private func contactInfoSection(_ client: Client) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            SectionHeaderView(title: "Contact Information")

            GlassCard {
                VStack(spacing: SpacingTokens.sm) {
                    if let email = client.email {
                        contactRow(icon: "envelope", label: "Email", value: email)
                    }

                    if let phone = client.phone {
                        if client.email != nil {
                            Divider()
                        }
                        contactRow(icon: "phone", label: "Phone", value: phone)
                    }
                }
            }
            .padding(.horizontal, SpacingTokens.md)
        }
    }

    private func contactRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: SpacingTokens.sm) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(ColorTokens.primaryOrange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(TypographyTokens.body)
            }

            Spacer()
        }
    }

    // MARK: - Address

    private func addressSection(_ client: Client) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            SectionHeaderView(title: "Address")

            GlassCard {
                HStack(spacing: SpacingTokens.sm) {
                    Image(systemName: "mappin.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(ColorTokens.primaryOrange)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        if let address = client.address {
                            Text(address)
                                .font(TypographyTokens.body)
                        }

                        let cityStateZip = [client.city, client.state, client.zip]
                            .compactMap { $0 }
                            .joined(separator: ", ")
                        if !cityStateZip.isEmpty {
                            Text(cityStateZip)
                                .font(TypographyTokens.body)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
            }
            .padding(.horizontal, SpacingTokens.md)
        }
    }

    // MARK: - Notes

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            SectionHeaderView(title: "Notes")

            GlassCard {
                Text(notes)
                    .font(TypographyTokens.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, SpacingTokens.md)
        }
    }

    // MARK: - Projects Section (Placeholder)

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            SectionHeaderView(title: "Projects", actionTitle: "See All") {
                // Navigate to filtered project list — will be implemented in Projects phase
            }

            GlassCard {
                HStack {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text("Projects will appear here")
                        .font(TypographyTokens.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding(.horizontal, SpacingTokens.md)
        }
    }

    // MARK: - Estimates Section

    private var estimatesSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            SectionHeaderView(title: "Past Estimates")

            Group {
                if isLoadingEstimates && estimates.isEmpty {
                    GlassCard {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Loading estimates…")
                                .font(TypographyTokens.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                } else if let estimatesError, estimates.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(ColorTokens.error)
                                Text(estimatesError)
                                    .font(TypographyTokens.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            Button("Retry") {
                                Task { await loadEstimates() }
                            }
                            .buttonStyle(.borderless)
                            .tint(ColorTokens.primaryOrange)
                        }
                    }
                } else if estimates.isEmpty {
                    GlassCard {
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.secondary)
                            Text("No estimates created for this client yet.")
                                .font(TypographyTokens.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                } else {
                    VStack(spacing: SpacingTokens.xs) {
                        ForEach(estimates) { estimate in
                            estimateRow(estimate)
                        }
                    }
                }
            }
            .padding(.horizontal, SpacingTokens.md)
        }
    }

    private func estimateRow(_ estimate: Estimate) -> some View {
        Button {
            router.navigate(to: .estimateEditor(id: estimate.id))
        } label: {
            GlassCard {
                HStack(spacing: SpacingTokens.sm) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(ColorTokens.primaryOrange)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: SpacingTokens.xs) {
                            Text(estimate.estimateNumber)
                                .font(TypographyTokens.headline)
                            StatusBadge(
                                text: estimate.status.rawValue.capitalized,
                                style: badgeStyle(for: estimate.status)
                            )
                        }

                        if let title = estimate.title, !title.isEmpty {
                            Text(title)
                                .font(TypographyTokens.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Text("Created \(estimate.createdAt.formatted(as: .medium))")
                            .font(TypographyTokens.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        CurrencyText(amount: estimate.totalAmount, font: TypographyTokens.moneyMedium)
                        if let validUntil = estimate.validUntil {
                            Text("Valid \(validUntil.formatted(as: .short))")
                                .font(TypographyTokens.caption2)
                                .foregroundStyle(estimate.isExpired ? ColorTokens.error : .secondary)
                        }
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data Loading

    private func loadClient() async {
        isLoading = true
        errorMessage = nil

        do {
            client = try await clientService.getClient(id: clientId)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func loadEstimates() async {
        isLoadingEstimates = true
        estimatesError = nil

        do {
            estimates = try await estimateService.listByClient(clientId: clientId)
        } catch {
            estimatesError = error.localizedDescription
        }

        isLoadingEstimates = false
    }

    private func badgeStyle(for status: Estimate.Status) -> StatusBadge.Style {
        switch status {
        case .draft: return .neutral
        case .sent: return .info
        case .approved: return .success
        case .declined: return .error
        case .expired: return .warning
        }
    }
}
