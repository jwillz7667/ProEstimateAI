import SwiftUI

struct FollowUpHistoryView: View {
    @Environment(AppState.self) private var appState
    @State private var model: FollowUpHistoryModel
    @State private var confirmSend = false

    init(kind: FollowUpKind, entityId: String) {
        _model = State(initialValue: FollowUpHistoryModel(kind: kind, entityId: entityId, service: FollowUpService()))
    }

    var body: some View {
        List {
            if let history = model.history {
                Section("Follow up") {
                    if let email = history.recipientEmail { Label(email, systemImage: "envelope").textSelection(.enabled) }
                    if let date = history.lastContactAt {
                        LabeledContent("Last send or follow-up", value: date.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let reason = history.unavailableReason { Text(reason).font(.footnote).foregroundStyle(.secondary) }
                    if !history.deliveryAvailable { Text("Email delivery is unavailable. You can still share the document link.").font(.footnote).foregroundStyle(.secondary) }
                    Button { confirmSend = true } label: {
                        Label(model.isWorking ? "Queuing follow-up…" : "Send follow-up email", systemImage: "paperplane")
                            .frame(minHeight: 44)
                    }
                    .disabled(!model.canSend)
                }
                Section("History") {
                    if history.messages.isEmpty { Text("No follow-up emails yet.").foregroundStyle(.secondary) }
                    ForEach(history.messages) { record in recordRow(record) }
                }
            } else if model.isLoading { ProgressView("Loading follow-up history…") }
            if let receipt = model.queuedReceipt { Section("Latest request") { recordRow(receipt) } }
            if let error = model.errorMessage {
                Section { Text(error).foregroundStyle(ColorTokens.error) }
            }
            Section {
                Text("A queued message is sent by the server. Provider acceptance does not confirm that the recipient received or opened it. Reminders stop after a response, change request, expiration or payment.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Follow-ups")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: workspaceScope) { await model.load(scope: workspaceScope) }
        .refreshable { await model.load(scope: workspaceScope) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await model.load(scope: workspaceScope) } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(model.isLoading || model.isWorking)
            }
        }
        .confirmationDialog("Send follow-up email?", isPresented: $confirmSend, titleVisibility: .visible) {
            Button("Send email") { Task { await model.send() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The client will receive a reminder with a link to this document. It will be checked again before sending.")
        }
    }

    private var workspaceScope: String { "\(appState.currentUser?.id ?? "signed-out"):\(appState.currentCompany?.id ?? "no-company")" }

    private func recordRow(_ record: FollowUpRecord) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            Text(record.statusTitle).font(.subheadline.weight(.semibold))
            Text(record.source == "automatic" ? "Automatic reminder" : "Requested follow-up")
                .font(.caption).foregroundStyle(.secondary)
            Text((record.deliveredAt ?? record.acceptedAt ?? record.createdAt).formatted(date: .abbreviated, time: .shortened))
                .font(.caption).foregroundStyle(.secondary)
            if let error = record.errorMessage { Text(error).font(.footnote).foregroundStyle(.secondary) }
        }
        .padding(.vertical, SpacingTokens.xxs)
    }
}
