import Foundation

/// Represents a homeowner or client that a company works with.
/// Clients are company-scoped — each company has its own client list.
struct Client: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let companyId: String
    let name: String
    let email: String?
    let phone: String?
    let address: String?
    let city: String?
    let state: String?
    let zip: String?
    let notes: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case companyId = "company_id"
        case name
        case email
        case phone
        case address
        case city
        case state
        case zip
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Convenience

extension Client {
    /// Formatted single-line address, or nil if no address components are present.
    var formattedAddress: String? {
        let parts = [address, city, state, zip].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Sample Data

extension Client {
    static let sample = Client(
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
        createdAt: Date(),
        updatedAt: Date()
    )
}
