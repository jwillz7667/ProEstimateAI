import Foundation

// MARK: - Protocol

protocol ClientServiceProtocol: Sendable {
    func listClients() async throws -> [Client]
    func getClient(id: String) async throws -> Client
    func createClient(request: CreateClientRequest) async throws -> Client
    func updateClient(id: String, request: UpdateClientRequest) async throws -> Client
    func deleteClient(id: String) async throws
}

// MARK: - Request DTOs

struct CreateClientRequest: Codable, Sendable {
    let name: String
    let email: String?
    let phone: String?
    let address: String?
    let city: String?
    let state: String?
    let zip: String?
    let notes: String?
}

struct UpdateClientRequest: Codable, Sendable {
    let name: String
    let email: String?
    let phone: String?
    let address: String?
    let city: String?
    let state: String?
    let zip: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case name, email, phone, address, city, state, zip, notes
    }

    /// Emit `null` for cleared optional fields instead of omitting them.
    /// The backend treats omitted keys as "leave unchanged", so without this
    /// a user clearing email/phone/etc. would silently fail to persist.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(email, forKey: .email)
        try container.encode(phone, forKey: .phone)
        try container.encode(address, forKey: .address)
        try container.encode(city, forKey: .city)
        try container.encode(state, forKey: .state)
        try container.encode(zip, forKey: .zip)
        try container.encode(notes, forKey: .notes)
    }
}

// MARK: - Mock Implementation

final class MockClientService: ClientServiceProtocol {
    private var clients: [Client] = MockClientService.sampleClients

    func listClients() async throws -> [Client] {
        try await Task.sleep(for: .seconds(0.5))
        return clients.sorted { $0.name < $1.name }
    }

    func getClient(id: String) async throws -> Client {
        try await Task.sleep(for: .seconds(0.3))
        guard let client = clients.first(where: { $0.id == id }) else {
            throw ClientServiceError.notFound
        }
        return client
    }

    func createClient(request: CreateClientRequest) async throws -> Client {
        try await Task.sleep(for: .seconds(0.6))
        let client = Client(
            id: "cl-\(UUID().uuidString.prefix(8))",
            companyId: "c-001",
            name: request.name,
            email: request.email,
            phone: request.phone,
            address: request.address,
            city: request.city,
            state: request.state,
            zip: request.zip,
            notes: request.notes,
            createdAt: Date(),
            updatedAt: Date()
        )
        clients.append(client)
        return client
    }

    func updateClient(id: String, request: UpdateClientRequest) async throws -> Client {
        try await Task.sleep(for: .seconds(0.5))
        guard let index = clients.firstIndex(where: { $0.id == id }) else {
            throw ClientServiceError.notFound
        }
        let existing = clients[index]
        let updated = Client(
            id: existing.id,
            companyId: existing.companyId,
            name: request.name,
            email: request.email,
            phone: request.phone,
            address: request.address,
            city: request.city,
            state: request.state,
            zip: request.zip,
            notes: request.notes,
            createdAt: existing.createdAt,
            updatedAt: Date()
        )
        clients[index] = updated
        return updated
    }

    func deleteClient(id: String) async throws {
        try await Task.sleep(for: .seconds(0.3))
        guard let index = clients.firstIndex(where: { $0.id == id }) else {
            throw ClientServiceError.notFound
        }
        clients.remove(at: index)
    }

    // MARK: - Sample Data

    private static let sampleClients: [Client] = [
        Client(
            id: "cl-001",
            companyId: "c-001",
            name: "Sarah Mitchell",
            email: "sarah@example.com",
            phone: "512-555-0300",
            address: "4200 Elm Dr",
            city: "Austin",
            state: "TX",
            zip: "78704",
            notes: "Prefers text over email.",
            createdAt: Date().addingTimeInterval(-86400 * 30),
            updatedAt: Date().addingTimeInterval(-86400 * 2)
        ),
        Client(
            id: "cl-002",
            companyId: "c-001",
            name: "David Chen",
            email: "david.chen@email.com",
            phone: "512-555-0412",
            address: "890 Oak Ln",
            city: "Austin",
            state: "TX",
            zip: "78746",
            notes: "Referred by Sarah Mitchell. Wants modern farmhouse style.",
            createdAt: Date().addingTimeInterval(-86400 * 20),
            updatedAt: Date().addingTimeInterval(-86400 * 5)
        ),
        Client(
            id: "cl-003",
            companyId: "c-001",
            name: "Maria Davis",
            email: "maria.davis@gmail.com",
            phone: "737-555-0188",
            address: "2100 Riverside Blvd",
            city: "Austin",
            state: "TX",
            zip: "78741",
            notes: nil,
            createdAt: Date().addingTimeInterval(-86400 * 15),
            updatedAt: Date().addingTimeInterval(-86400 * 10)
        ),
        Client(
            id: "cl-004",
            companyId: "c-001",
            name: "James Wallace",
            email: "jwallace@wallacehomes.com",
            phone: "512-555-0777",
            address: "6100 Congress Ave",
            city: "Austin",
            state: "TX",
            zip: "78745",
            notes: "Property manager, handles multiple units. Invoice to company address.",
            createdAt: Date().addingTimeInterval(-86400 * 45),
            updatedAt: Date().addingTimeInterval(-86400 * 7)
        ),
        Client(
            id: "cl-005",
            companyId: "c-001",
            name: "Linda Nguyen",
            email: "linda.n@outlook.com",
            phone: "512-555-0233",
            address: "3400 S Lamar Blvd",
            city: "Austin",
            state: "TX",
            zip: "78704",
            notes: "Bilingual — prefers Spanish-language proposals.",
            createdAt: Date().addingTimeInterval(-86400 * 60),
            updatedAt: Date().addingTimeInterval(-86400)
        ),
    ]
}

// MARK: - Errors

enum ClientServiceError: LocalizedError {
    case notFound
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Client not found."
        case let .validationFailed(reason):
            return "Validation failed: \(reason)"
        }
    }
}
