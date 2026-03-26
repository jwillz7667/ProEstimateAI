import SwiftUI

struct ClientFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ClientFormViewModel
    private let onSave: ((Client) -> Void)?

    /// Creates a client form for a new client.
    init(onSave: ((Client) -> Void)? = nil) {
        self._viewModel = State(initialValue: ClientFormViewModel())
        self.onSave = onSave
    }

    /// Creates a client form for editing an existing client.
    init(client: Client, onSave: ((Client) -> Void)? = nil) {
        self._viewModel = State(initialValue: ClientFormViewModel(client: client))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Name (Required)
                Section {
                    VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                        TextField("Client name", text: $viewModel.name)
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                    }
                } header: {
                    Text("Name *")
                } footer: {
                    Text("Client name is required.")
                        .foregroundStyle(.secondary)
                }

                // MARK: - Contact
                Section("Contact") {
                    TextField("Email address", text: $viewModel.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Phone number", text: $viewModel.phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                }

                // MARK: - Address
                Section("Address") {
                    TextField("Street address", text: $viewModel.address)
                        .textContentType(.streetAddressLine1)
                        .textInputAutocapitalization(.words)

                    TextField("City", text: $viewModel.city)
                        .textContentType(.addressCity)
                        .textInputAutocapitalization(.words)

                    TextField("State", text: $viewModel.state)
                        .textContentType(.addressState)
                        .textInputAutocapitalization(.characters)

                    TextField("ZIP code", text: $viewModel.zip)
                        .textContentType(.postalCode)
                        .keyboardType(.numberPad)
                }

                // MARK: - Notes
                Section("Notes") {
                    TextField("Additional notes", text: $viewModel.notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(viewModel.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.saveButtonTitle) {
                        Task { await saveClient() }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(ColorTokens.primaryOrange)
                    .disabled(viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSaving)
                }
            }
            .alert("Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.clearError() } }
            )) {
                Button("OK", role: .cancel) { viewModel.clearError() }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .interactiveDismissDisabled(viewModel.isSaving)
            .overlay {
                if viewModel.isSaving {
                    Color.black.opacity(0.1)
                        .ignoresSafeArea()
                        .overlay {
                            ProgressView("Saving...")
                                .padding(SpacingTokens.xl)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: RadiusTokens.card))
                        }
                }
            }
        }
    }

    // MARK: - Save

    private func saveClient() async {
        guard let client = await viewModel.save() else { return }
        onSave?(client)
        dismiss()
    }
}
