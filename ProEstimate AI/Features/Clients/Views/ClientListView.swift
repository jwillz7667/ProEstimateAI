import SwiftUI

/// Clients tab landing page. The contractor's primary action here is to
/// update a client's contact info, so tapping a card opens the edit
/// form sheet directly rather than routing through a separate detail
/// screen first. Long-press (context menu) still surfaces the
/// destructive delete affordance.
struct ClientListView: View {
    @State private var viewModel = ClientListViewModel()
    @State private var showingNewClient = false
    @State private var clientToEdit: Client?
    @State private var showingDeleteConfirmation = false
    @State private var clientToDelete: Client?

    var body: some View {
        NavigationStack {
            content
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
                .sheet(item: $clientToEdit) { client in
                    ClientFormView(client: client) { updatedClient in
                        viewModel.addOrUpdateClient(updatedClient)
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
                ctaTitle: "Add Client",
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
                    Button {
                        clientToEdit = client
                    } label: {
                        clientRow(client)
                            .padding(SpacingTokens.md)
                            .glassCard()
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the edit form for this client")
                    .contextMenu {
                        Button {
                            clientToEdit = client
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }

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
