import SwiftUI

/// Client history is the primary destination; editing stays available in the context menu.
struct ClientListView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState
    @State private var viewModel = ClientListViewModel()
    @State private var showingNewClient = false
    @State private var clientToEdit: Client?
    @State private var showingDeleteConfirmation = false
    @State private var clientToDelete: Client?

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.clientsPath) {
            content
                .navigationTitle("Clients")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        SubscriptionBadge()
                    }
                    ToolbarItem(placement: .primaryAction) {
                      if appState.currentUser?.canEdit == true {
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
                .sheet(item: $clientToEdit) { client in
                    ClientFormView(client: client) { updatedClient in
                        viewModel.addOrUpdateClient(updatedClient)
                    }
                }
                .appNavigationDestinations()
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
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
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
                ctaTitle: appState.currentUser?.canEdit == true ? "Add Client" : nil,
                ctaAction: { showingNewClient = true }
            )
        } else {
            clientList
        }
    }

    // MARK: - Client List

    private var clientList: some View {
        ScrollView {
            LazyVStack(spacing: SpacingTokens.sm) {
                ForEach(viewModel.filteredClients) { client in
                    NavigationLink {
                        ClientDetailView(
                            clientId: client.id,
                            onClientUpdated: { viewModel.addOrUpdateClient($0) },
                            onClientDeleted: { viewModel.removeClient(id: $0) }
                        )
                    } label: {
                        clientRow(client)
                            .padding(SpacingTokens.md)
                            .glassCard()
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Open client details, projects and estimates")
                    .contextMenu {
                        Button {
                            clientToEdit = client
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .disabled(appState.currentUser?.canEdit != true)

                        Button(role: .destructive) {
                            clientToDelete = client
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(appState.currentUser?.canEdit != true)
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
                    .foregroundStyle(ColorTokens.primaryText)

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

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, SpacingTokens.xxs)
    }
}
