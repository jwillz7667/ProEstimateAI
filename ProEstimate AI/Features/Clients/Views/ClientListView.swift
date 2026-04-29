import SwiftUI

struct ClientListView: View {
    @Environment(AppRouter.self) private var router
    @State private var viewModel = ClientListViewModel()
    @State private var showingNewClient = false
    @State private var showingDeleteConfirmation = false
    @State private var clientToDelete: Client?

    var body: some View {
        // NavigationSplitView auto-collapses to a stack on iPhone and shows
        // the list + detail side-by-side on iPad (regular horizontal size class).
        NavigationSplitView {
            sidebar
        } detail: {
            NavigationStack {
                emptyDetailPlaceholder
                    .navigationDestination(for: String.self) { clientId in
                        ClientDetailView(
                            clientId: clientId,
                            onClientUpdated: { updatedClient in
                                viewModel.addOrUpdateClient(updatedClient)
                            },
                            onClientDeleted: { deletedId in
                                viewModel.removeClient(id: deletedId)
                            }
                        )
                    }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        Group {
            if viewModel.isLoading && !viewModel.hasClients {
                LoadingStateView(message: "Loading clients...")
            } else if let errorMessage = viewModel.errorMessage, !viewModel.hasClients {
                RetryStateView(message: errorMessage) {
                    Task { await viewModel.loadClients() }
                }
            } else if !viewModel.hasClients {
                EmptyStateView(
                    icon: "person.2",
                    title: "No Clients Yet",
                    subtitle: "Add your first client to start creating estimates and invoices.",
                    ctaTitle: "Add Client",
                    ctaAction: { showingNewClient = true }
                )
            } else {
                clientList
            }
        }
        .navigationTitle("Clients")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                SubscriptionBadge()
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewClient = true
                } label: {
                    Image(systemName: "plus")
                }
                .tint(ColorTokens.primaryOrange)
                .accessibilityLabel("New client")
                .accessibilityHint("Add a new client")
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Search clients")
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            if !viewModel.hasClients {
                await viewModel.loadClients()
            }
        }
        .sheet(isPresented: $showingNewClient) {
            ClientFormView { newClient in
                viewModel.addOrUpdateClient(newClient)
            }
        }
        .confirmationDialog(
            "Delete Client",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible,
            presenting: clientToDelete
        ) { client in
            Button("Delete \(client.name)", role: .destructive) {
                Task { await viewModel.deleteClient(id: client.id) }
            }
            Button("Cancel", role: .cancel) {
                clientToDelete = nil
            }
        } message: { _ in
            Text("Projects and invoices linked to this client will still exist, but their client information will be removed. This can't be undone.")
        }
    }

    // MARK: - iPad Empty Detail

    private var emptyDetailPlaceholder: some View {
        VStack(spacing: SpacingTokens.md) {
            Image(systemName: "person.2")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(ColorTokens.primaryOrange.opacity(0.55))
                .accessibilityHidden(true)

            Text("Select a Client")
                .font(TypographyTokens.title3)
                .foregroundStyle(ColorTokens.primaryText)

            Text("Pick a client from the list to see their projects and contact details.")
                .font(TypographyTokens.subheadline)
                .foregroundStyle(ColorTokens.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(SpacingTokens.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Client List

    private var clientList: some View {
        ScrollView {
            LazyVStack(spacing: SpacingTokens.sm) {
                ForEach(viewModel.filteredClients) { client in
                    NavigationLink(value: client.id) {
                        clientRow(client)
                            .padding(SpacingTokens.md)
                            .glassCard()
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            clientToDelete = client
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, SpacingTokens.md)
            .padding(.vertical, SpacingTokens.xs)
        }
    }

    // MARK: - Client Row

    private func clientRow(_ client: Client) -> some View {
        HStack(spacing: SpacingTokens.sm) {
            AvatarView(name: client.name, size: 44)

            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                Text(client.name)
                    .font(TypographyTokens.headline)

                if let email = client.email {
                    Text(email)
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let city = client.city, let state = client.state {
                Text("\(city), \(state)")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, SpacingTokens.xxs)
    }
}
