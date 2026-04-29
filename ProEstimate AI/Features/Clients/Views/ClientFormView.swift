import SwiftUI

struct ClientFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ClientFormViewModel
    @FocusState private var focusedField: Field?
    private let onSave: ((Client) -> Void)?

    private enum Field: Hashable {
        case name, email, phone, address, city, state, zip, notes
    }

    /// Creates a client form for a new client.
    init(onSave: ((Client) -> Void)? = nil) {
        _viewModel = State(initialValue: ClientFormViewModel())
        self.onSave = onSave
    }

    /// Creates a client form for editing an existing client.
    init(client: Client, onSave: ((Client) -> Void)? = nil) {
        _viewModel = State(initialValue: ClientFormViewModel(client: client))
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
                            .focused($focusedField, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .email }

                        if viewModel.showsNameError {
                            Text("Client name is required.")
                                .font(TypographyTokens.caption2)
                                .foregroundStyle(ColorTokens.error)
                                .accessibilityIdentifier("clientForm.error.name")
                        }
                    }
                } header: {
                    Text("Name *")
                }

                // MARK: - Contact

                Section("Contact") {
                    VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                        TextField("Email address", text: $viewModel.email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .phone }

                        if viewModel.showsEmailError {
                            Text("Please enter a valid email address.")
                                .font(TypographyTokens.caption2)
                                .foregroundStyle(ColorTokens.error)
                                .accessibilityIdentifier("clientForm.error.email")
                        }
                    }

                    TextField("Phone number", text: $viewModel.phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .focused($focusedField, equals: .phone)
                }

                // MARK: - Address

                Section("Address") {
                    TextField("Street address", text: $viewModel.address)
                        .textContentType(.streetAddressLine1)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .address)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .city }

                    TextField("City", text: $viewModel.city)
                        .textContentType(.addressCity)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .city)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .state }

                    TextField("State", text: $viewModel.state)
                        .textContentType(.addressState)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .state)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .zip }

                    TextField("ZIP code", text: $viewModel.zip)
                        .textContentType(.postalCode)
                        .keyboardType(.numbersAndPunctuation)
                        .focused($focusedField, equals: .zip)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .notes }
                }

                // MARK: - Notes

                Section("Notes") {
                    TextField("Additional notes", text: $viewModel.notes, axis: .vertical)
                        .lineLimit(3 ... 6)
                        .focused($focusedField, equals: .notes)
                }
            }
            .navigationTitle(viewModel.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(viewModel.isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.saveButtonTitle) {
                        Task { await saveClient() }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(ColorTokens.primaryOrange)
                    .disabled(!viewModel.isFormValid || viewModel.isSaving)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                        .fontWeight(.semibold)
                        .tint(ColorTokens.primaryOrange)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .alert("Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.clearError() } }
            )) {
                Button("OK", role: .cancel) { viewModel.clearError() }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .interactiveDismissDisabled(viewModel.isSaving)
            .sensoryFeedback(.success, trigger: viewModel.saveSuccessCount)
            .onChange(of: focusedField) { previous, _ in
                // Track which fields the user has visited so inline errors only
                // appear after the user has had a chance to type and leave.
                if previous == .name { viewModel.nameWasVisited = true }
                if previous == .email { viewModel.emailWasVisited = true }
            }
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
        focusedField = nil
        guard let client = await viewModel.save() else { return }
        onSave?(client)
        dismiss()
    }
}
