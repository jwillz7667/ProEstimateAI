import Foundation
import Observation

@Observable
final class ClientFormViewModel {
    // MARK: - Form fields

    var name: String = ""
    var email: String = ""
    var phone: String = ""
    var address: String = ""
    var city: String = ""
    var state: String = ""
    var zip: String = ""
    var notes: String = ""

    // MARK: - UI state

    var isLoading: Bool = false
    var isSaving: Bool = false
    var errorMessage: String?

    // MARK: - Mode

    let isEditMode: Bool
    private let existingClientId: String?

    // MARK: - Dependencies

    private let clientService: ClientServiceProtocol

    // MARK: - Init

    /// Creates a form view model for either creating a new client or editing an existing one.
    /// - Parameters:
    ///   - client: Pass an existing `Client` to enter edit mode, or `nil` for create mode.
    ///   - clientService: The service used to persist changes.
    init(client: Client? = nil, clientService: ClientServiceProtocol = LiveClientService()) {
        self.clientService = clientService
        self.isEditMode = client != nil
        self.existingClientId = client?.id

        if let client {
            name = client.name
            email = client.email ?? ""
            phone = client.phone ?? ""
            address = client.address ?? ""
            city = client.city ?? ""
            state = client.state ?? ""
            zip = client.zip ?? ""
            notes = client.notes ?? ""
        }
    }

    // MARK: - Computed

    var navigationTitle: String {
        isEditMode ? "Edit Client" : "New Client"
    }

    var saveButtonTitle: String {
        isEditMode ? "Save Changes" : "Create Client"
    }

    // MARK: - Validation

    func validate() -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedName.isEmpty {
            errorMessage = "Client name is required."
            return false
        }

        // Email is optional but if provided must be valid
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedEmail.isEmpty {
            let pattern = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
            if trimmedEmail.range(of: pattern, options: .regularExpression) == nil {
                errorMessage = "Please enter a valid email address."
                return false
            }
        }

        errorMessage = nil
        return true
    }

    // MARK: - Save

    /// Saves the client (create or update) and returns the resulting `Client` on success, or `nil` on failure.
    func save() async -> Client? {
        guard validate() else { return nil }

        isSaving = true
        errorMessage = nil

        do {
            let client: Client

            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedState = state.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedZip = zip.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

            if isEditMode, let clientId = existingClientId {
                let request = UpdateClientRequest(
                    name: trimmedName,
                    email: trimmedEmail.isEmpty ? nil : trimmedEmail,
                    phone: trimmedPhone.isEmpty ? nil : trimmedPhone,
                    address: trimmedAddress.isEmpty ? nil : trimmedAddress,
                    city: trimmedCity.isEmpty ? nil : trimmedCity,
                    state: trimmedState.isEmpty ? nil : trimmedState,
                    zip: trimmedZip.isEmpty ? nil : trimmedZip,
                    notes: trimmedNotes.isEmpty ? nil : trimmedNotes
                )
                client = try await clientService.updateClient(id: clientId, request: request)
            } else {
                let request = CreateClientRequest(
                    name: trimmedName,
                    email: trimmedEmail.isEmpty ? nil : trimmedEmail,
                    phone: trimmedPhone.isEmpty ? nil : trimmedPhone,
                    address: trimmedAddress.isEmpty ? nil : trimmedAddress,
                    city: trimmedCity.isEmpty ? nil : trimmedCity,
                    state: trimmedState.isEmpty ? nil : trimmedState,
                    zip: trimmedZip.isEmpty ? nil : trimmedZip,
                    notes: trimmedNotes.isEmpty ? nil : trimmedNotes
                )
                client = try await clientService.createClient(request: request)
            }

            isSaving = false
            return client
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
            return nil
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
