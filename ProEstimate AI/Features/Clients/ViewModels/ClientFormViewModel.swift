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

    /// Show the name error only after the user has interacted with the field
    /// in a way that could leave it empty — i.e. never on initial presentation.
    var showsNameError: Bool {
        // Show whenever the user has tapped into the field and the name is empty.
        // Using non-empty on the *other* fields as a pragmatic "has interacted" signal.
        isNameInvalid && (!email.isEmpty || !phone.isEmpty)
    }

    /// Show the email error only when the user has typed something invalid.
    var showsEmailError: Bool {
        !email.isEmpty && isEmailInvalid
    }

    /// Whether the whole form is valid enough to submit.
    var isFormValid: Bool {
        !isNameInvalid && !isEmailInvalid
    }

    func validate() -> Bool {
        if isNameInvalid {
            errorMessage = "Client name is required."
            return false
        }
        if isEmailInvalid {
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
