import SwiftUI

struct FollowUpSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var model = FollowUpSettingsModel(service: FollowUpService())

    var body: some View {
        Form {
            if let saved = model.saved {
                Section {
                    Toggle("Automatic email reminders", isOn: $model.enabled)
                        .disabled(!saved.canManage || model.isSaving || (!saved.deliveryAvailable && !model.enabled))
                } footer: {
                    Text("Off by default. Saving this setting on applies to documents you send after enabling it. Each document receives at most one automatic reminder.")
                }
                Section("Timing") {
                    Stepper("Quote follow-up after \(model.quoteDays) days", value: $model.quoteDays, in: 1...30)
                    Stepper("Invoice reminder \(model.invoiceDays) days overdue", value: $model.invoiceDays, in: 1...30)
                }
                .disabled(!saved.canManage || model.isSaving)
                Section {
                    Text("Reminders stop when the client responds, requests changes, the proposal expires or the invoice is paid or void. Recipients can stop reminders from each email.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if !saved.canManage { Text("Only owners and administrators can change reminders.").font(.footnote).foregroundStyle(.secondary) }
                    if !saved.deliveryAvailable { Text("Email delivery is not configured. Automatic reminders cannot be enabled.").font(.footnote).foregroundStyle(.secondary) }
                    Button(model.isSaving ? "Saving…" : "Save reminder settings") { Task { await model.save() } }
                        .disabled(!model.canSave)
                    if model.didSave { Label("Settings saved", systemImage: "checkmark.circle").foregroundStyle(ColorTokens.success) }
                }
            } else if model.isLoading { ProgressView("Loading reminder settings…") }
            if let error = model.errorMessage {
                Section {
                    Text(error).foregroundStyle(ColorTokens.error)
                    Button("Refresh saved settings") { Task { await model.load(scope: workspaceScope) } }
                        .disabled(model.isLoading || model.isSaving)
                }
            }
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: workspaceScope) { await model.load(scope: workspaceScope) }
        .refreshable { await model.load(scope: workspaceScope) }
    }

    private var workspaceScope: String { "\(appState.currentUser?.id ?? "signed-out"):\(appState.currentCompany?.id ?? "no-company")" }
}
