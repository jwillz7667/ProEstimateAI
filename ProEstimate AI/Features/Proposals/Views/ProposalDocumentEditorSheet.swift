import SwiftUI

struct ProposalDocumentEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var form: ProposalDocumentForm
    @State private var saving = false
    @State private var errorMessage: String?
    let onSave: (ProposalDocumentForm) async throws -> Void

    init(proposal: Proposal, onSave: @escaping (ProposalDocumentForm) async throws -> Void) {
        _form = State(initialValue: ProposalDocumentForm(proposal: proposal))
        self.onSave = onSave
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
            .disabled(saving)
            .navigationTitle("Scope & terms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(saving)
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
        guard !saving else { return }
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
}
