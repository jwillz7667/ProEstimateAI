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

    /// Whether the user has visited (and left) the name field at least once.
    /// Drives the inline "name required" error so it doesn't flash on first
    /// presentation before the user has typed anything.
    var nameWasVisited: Bool = false

    /// Whether the user has visited (and left) the email field at least once.
    var emailWasVisited: Bool = false

    /// Bumps every successful save so views can drive sensoryFeedback/haptics.
    var saveSuccessCount: Int = 0

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
        isEditMode = client != nil
        existingClientId = client?.id

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

    /// Whether the required name field is currently empty (after trimming).
    /// Drives the inline "Client name is required" message under the field.
    var isNameInvalid: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether the email field, if provided, matches a valid pattern.
    var isEmailInvalid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false } // Email is optional.
        let pattern = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return trimmed.range(of: pattern, options: .regularExpression) == nil
    }

    /// Show the name error only after the user has interacted with the name
    /// field — never on initial presentation.
    var showsNameError: Bool {
        nameWasVisited && isNameInvalid
    }

    /// Show the email error only when the user has typed something invalid
    /// and has left the field.
    var showsEmailError: Bool {
        emailWasVisited && !email.isEmpty && isEmailInvalid
    }

    /// Whether the whole form is valid enough to submit.
    var isFormValid: Bool {
        !isNameInvalid && !isEmailInvalid
    }

    func validate() -> Bool {
        if isNameInvalid {
            // Surface the inline marker as well so the field is highlighted.
            nameWasVisited = true
            errorMessage = "Client name is required."
            return false
        }
        if isEmailInvalid {
            emailWasVisited = true
            errorMessage = "Please enter a valid email address."
            return false
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
            saveSuccessCount &+= 1
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
