import SwiftUI

struct ClientListView: View {
    @Environment(AppRouter.self) private var router
    @State private var viewModel = ClientListViewModel()
    @State private var showingNewClient = false

    var body: some View {
        NavigationStack {
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
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewClient = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .tint(ColorTokens.primaryOrange)
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
            .navigationDestination(for: String.self) { clientId in
                ClientDetailView(
                    clientId: clientId,
                    onClientUpdated: { updatedClient in
                        viewModel.addOrUpdateClient(updatedClient)
                    }
                )
            }
        }
    }

    // MARK: - Client List

    private var clientList: some View {
        List {
            ForEach(viewModel.filteredClients) { client in
                NavigationLink(value: client.id) {
                    clientRow(client)
                }
            }
            .onDelete { indexSet in
                deleteClients(at: indexSet)
            }
        }
        .listStyle(.plain)
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

    // MARK: - Delete

    private func deleteClients(at offsets: IndexSet) {
        let clientsToDelete = offsets.map { viewModel.filteredClients[$0] }
        for client in clientsToDelete {
            Task {
                await viewModel.deleteClient(id: client.id)
            }
        }
    }
}
