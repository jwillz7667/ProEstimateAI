import SwiftUI

/// Small toolbar pill that mirrors the autosave pipeline in
/// `SettingsViewModel`. Replaces the explicit "Save" buttons on each
/// settings sub-screen — the user no longer has to remember to commit
/// changes; this view tells them when changes are pending, in flight,
/// or persisted.
struct SettingsSaveStatusView: View {
    let status: SettingsSaveStatus

    var body: some View {
        Group {
            switch status {
            case .idle:
                EmptyView()
            case .pending:
                Label("Pending", systemImage: "ellipsis.circle")
                    .labelStyle(StatusLabelStyle(tint: .secondary))
            case .saving:
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Saving…")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                }
            case .saved:
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .labelStyle(StatusLabelStyle(tint: ColorTokens.success))
            case let .failed(message):
                Label("Retry", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(StatusLabelStyle(tint: ColorTokens.error))
                    .help(message)
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .animation(.easeInOut(duration: 0.2), value: statusKey)
    }

    private var statusKey: String {
        switch status {
        case .idle: "idle"
        case .pending: "pending"
        case .saving: "saving"
        case .saved: "saved"
        case .failed: "failed"
        }
    }

    private var accessibilityLabel: String {
        switch status {
        case .idle: "All changes saved"
        case .pending: "Pending save"
        case .saving: "Saving"
        case .saved: "Saved"
        case let .failed(message): "Save failed: \(message)"
        }
    }
}

private struct StatusLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
                .foregroundStyle(tint)
            configuration.title
                .font(TypographyTokens.caption)
                .foregroundStyle(.secondary)
        }
    }
}
