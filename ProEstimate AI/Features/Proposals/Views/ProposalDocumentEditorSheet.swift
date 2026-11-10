import SwiftUI

struct ProposalDocumentEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var form: ProposalDocumentForm
    @State private var saving = false
    @State private var errorMessage: String?
    let onSave: (ProposalDocumentForm) async throws -> Void
    private let companyId: String

    init(proposal: Proposal, onSave: @escaping (ProposalDocumentForm) async throws -> Void) {
        _form = State(initialValue: ProposalDocumentForm(proposal: proposal))
        self.onSave = onSave
        self.companyId = proposal.companyId
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Proposal") {
                    TextField("Title", text: $form.title)
                    TextField("Message to client", text: $form.message, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("Scope & schedule") {
                    documentField("Introduction", text: $form.introduction)
                    documentField("Scope of work", text: $form.scope)
                    documentField("Timeline", text: $form.timeline)
                }
                Section("Terms") {
                    documentField("Terms & conditions", text: $form.terms)
                    documentField("Footer", text: $form.footer)
                    Toggle("Set expiration", isOn: $form.hasExpiration)
                    if form.hasExpiration {
                        DatePicker("Expires", selection: $form.expiration, displayedComponents: [.date, .hourAndMinute])
                    }
                }
                Section {
                    Text("Sending preserves this scope, price and terms. Later changes require a new revision.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let errorMessage { Text(errorMessage).foregroundStyle(ColorTokens.error).accessibilityIdentifier("proposal.document.error") }
                }
            }
            .disabled(saving || !canEditDocument)
            .navigationTitle("Scope & terms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(saving || !canEditDocument)
                }
            }
            .interactiveDismissDisabled(saving)
        }
    }

    private func documentField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: text, axis: .vertical).lineLimit(3...10)
        }
    }

    private func save() async {
        guard !saving, canEditDocument else { return }
        if let validation = form.validationMessage() { errorMessage = validation; return }
        saving = true
        defer { saving = false }
        do {
            try await onSave(form)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var canEditDocument: Bool {
        appState.currentUser?.canEdit == true && appState.currentCompany?.id == companyId
    }
}
