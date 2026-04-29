import Foundation
import Observation

@Observable
final class ClientListViewModel {
    // MARK: - State

    var clients: [Client] = []
    var searchText: String = ""
    var isLoading: Bool = false
    var errorMessage: String?

    // MARK: - Computed

    var filteredClients: [Client] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return clients
        }
        let query = searchText.lowercased()
        return clients.filter { client in
            client.name.lowercased().contains(query)
                || (client.email?.lowercased().contains(query) ?? false)
                || (client.phone?.contains(query) ?? false)
                || (client.city?.lowercased().contains(query) ?? false)
        }
    }

    var hasClients: Bool {
        !clients.isEmpty
    }

    // MARK: - Dependencies

    private let clientService: ClientServiceProtocol

    // MARK: - Init

    init(clientService: ClientServiceProtocol = LiveClientService()) {
        self.clientService = clientService
    }

    // MARK: - Actions

    func loadClients() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            clients = try await clientService.listClients()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func deleteClient(id: String) async {
        do {
            try await clientService.deleteClient(id: id)
            clients.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        await loadClients()
    }

    /// Called after a client is created or updated to refresh the list.
    func addOrUpdateClient(_ client: Client) {
        if let index = clients.firstIndex(where: { $0.id == client.id }) {
            clients[index] = client
        } else {
            clients.append(client)
        }
        // Re-sort alphabetically
        clients.sort { $0.name < $1.name }
    }

    /// Drop a client from the in-memory list when the network deletion has
    /// already been performed upstream (e.g. from `ClientDetailView`).
    func removeClient(id: String) {
        clients.removeAll { $0.id == id }
    }
}
