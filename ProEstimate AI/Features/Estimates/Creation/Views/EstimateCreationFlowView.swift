import SwiftUI

/// One input page followed directly by the real estimate editor. Projects stay
/// organized behind the estimate, without requiring a separate setup wizard.
struct EstimateCreationFlowView: View {
    let onOpenProject: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(FeatureGateCoordinator.self) private var featureGate
    @Environment(PaywallPresenter.self) private var paywall
    @State private var model = EstimateCreationViewModel(service: EstimateCreationService())
    @State private var clientPicker: ClientPickerRoute?
    @State private var editor: EstimateEditorRoute?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Start with the work. Review every item before sending anything to your client.")
                        .font(TypographyTokens.subheadline)
                        .foregroundStyle(ColorTokens.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section("Client") {
                    Button { clientPicker = ClientPickerRoute() } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                                Text(model.selectedClient?.name ?? "Choose or add a client")
                                    .foregroundStyle(ColorTokens.primaryText)
                                Text(model.selectedClient?.email ?? "Optional while drafting")
                                    .font(TypographyTokens.caption)
                                    .foregroundStyle(ColorTokens.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote)
                        }
                        .frame(minHeight: 44)
                    }
                    .disabled(model.inputsLocked)
                }
                Section("Work") {
                    TextField("Estimate name", text: $model.draft.title)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("estimateCreation.title")
                    Picker("Type of work", selection: $model.draft.projectType) {
                        ForEach(Project.ProjectType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.iconName).tag(type)
                        }
                    }
                    TextField("Describe the work (optional for manual estimates)", text: $model.draft.scope, axis: .vertical)
                        .lineLimit(4 ... 10)
                        .accessibilityIdentifier("estimateCreation.scope")
                }
                .disabled(model.inputsLocked)
                Section {
                    Picker("Build estimate", selection: $model.draft.method) {
                        ForEach(EstimateCreationMethod.allCases) { method in
                            Text(method.title).tag(method)
                        }
                    }
                    .disabled(model.isCreating || model.recovery != .none)
                    Text(model.draft.method == .manual
                         ? "Add your own materials and labor. Manual drafting is free."
                         : "AI writes a draft from your scope. Requires an active trial or subscription and uses an AI estimate allowance. No image is generated.")
                        .font(TypographyTokens.footnote)
                        .foregroundStyle(ColorTokens.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } header: { Text("Starting point") }
                recoverySection
                if model.recovery == .none {
                    Section {
                        Button { Task { await create() } } label: {
                            HStack {
                                Spacer()
                                if model.isCreating { ProgressView().tint(ColorTokens.brandDark) }
                                Text(model.isCreating ? "Preparing estimate…" : (model.createdProject == nil ? "Continue to estimate" : "Continue saved project"))
                                    .font(TypographyTokens.headline)
                                Spacer()
                            }
                            .foregroundStyle(ColorTokens.brandDark)
                            .padding(.vertical, SpacingTokens.sm)
                        }
                        .listRowBackground(ColorTokens.primaryOrange)
                        .disabled(!model.canCreate || model.draft.validationMessage != nil)
                        .accessibilityIdentifier("estimateCreation.continue")
                    } footer: {
                        if !model.draft.title.isEmpty, let validation = model.draft.validationMessage {
                            Text(validation)
                        }
                    }
                }
            }
            .navigationTitle("New estimate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.disabled(model.isCreating)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .interactiveDismissDisabled(model.isCreating)
            .task(id: appState.currentCompany?.id) {
                if let companyId = appState.currentCompany?.id { await model.loadClients(companyId: companyId) }
            }
            .sheet(item: $clientPicker) { _ in
                EstimateCreationClientPicker(model: model)
            }
            .sheet(item: $editor, onDismiss: openSavedProject) { target in
                EstimateEditorView(estimateId: target.id)
            }
        }
    }

    @ViewBuilder
    private var recoverySection: some View {
        if let message = model.errorMessage {
            Section {
                Text(message).fixedSize(horizontal: false, vertical: true)
                if model.recovery == .checkEstimates {
                    Button("Check saved estimates") { Task { await model.checkSavedEstimates() } }
                        .disabled(model.isRecovering)
                    ForEach(model.recoveredEstimates) { estimate in
                        Button("Review \(estimate.title ?? estimate.estimateNumber)") {
                            if model.chooseRecoveredEstimate(estimate) { editor = EstimateEditorRoute(id: estimate.id) }
                        }
                    }
                }
                if model.createdProject != nil {
                    Button("Open saved project", action: openSavedProject)
                        .disabled(model.isCreating)
                }
                if model.recovery == .checkProjects {
                    Button("Close and check Projects") { dismiss() }
                }
            } header: { Text("Saved work") }
        }
    }

    private func create() async {
        guard let companyId = appState.currentCompany?.id else { return }
        if model.createdProject == nil {
            switch featureGate.guardCreateProject() {
            case .allowed: break
            case let .blocked(decision): paywall.present(decision); return
            }
        }
        if model.draft.method == .ai {
            switch featureGate.guardGenerateAIEstimate() {
            case .allowed: break
            case let .blocked(decision): paywall.present(decision); return
            }
        }
        let success = await model.create(companyId: companyId, language: Locale.current.language.languageCode?.identifier ?? "en")
        if model.createdProject != nil { AppEventBus.shared.noteProjectChange() }
        if success, let estimate = model.createdEstimate { editor = EstimateEditorRoute(id: estimate.id) }
        else if let error = model.lastError as? APIError, case let .paywall(decision) = error { paywall.present(decision) }
    }

    private func openSavedProject() {
        guard let projectId = model.createdProject?.id else { return }
        AppEventBus.shared.noteProjectChange()
        onOpenProject(projectId)
        dismiss()
    }
}

private struct ClientPickerRoute: Identifiable { let id = UUID() }
private struct EstimateEditorRoute: Identifiable { let id: String }

struct EstimateCreationClientPicker: View {
    let model: EstimateCreationViewModel
    var allowsNoClient = true
    var onSelected: ((Client) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var search = ""
    @State private var addClient: ClientPickerRoute?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { addClient = ClientPickerRoute() } label: {
                        Label("Add new client", systemImage: "person.badge.plus")
                    }
                    if allowsNoClient {
                        Button("Continue without a client") { model.selectClient(nil); dismiss() }
                    }
                }
                if model.isLoadingClients { ProgressView("Loading clients…") }
                if let message = model.clientsError {
                    Section {
                        Text(message)
                        Button("Retry") {
                            if let companyId = appState.currentCompany?.id {
                                Task { await model.loadClients(companyId: companyId) }
                            }
                        }
                    }
                }
                Section("Saved clients") {
                    ForEach(filteredClients) { client in
                        Button { model.selectClient(client); onSelected?(client); dismiss() } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                                    Text(client.name).foregroundStyle(ColorTokens.primaryText)
                                    if let contact = client.email ?? client.phone {
                                        Text(contact).font(TypographyTokens.caption).foregroundStyle(ColorTokens.secondaryText)
                                    }
                                }
                                Spacer()
                                if model.selectedClient?.id == client.id { Image(systemName: "checkmark") }
                            }
                            .frame(minHeight: 44)
                        }
                    }
                    if filteredClients.isEmpty, !model.isLoadingClients {
                        Text(search.isEmpty ? "No clients saved yet." : "No matching clients.")
                            .foregroundStyle(ColorTokens.secondaryText)
                    }
                }
            }
            .searchable(text: $search, prompt: "Name, email or phone")
            .navigationTitle("Choose client")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(item: $addClient) { _ in
                ClientFormView { client in model.selectClient(client); onSelected?(client); dismiss() }
            }
        }
    }

    private var filteredClients: [Client] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.clients }
        return model.clients.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.email?.localizedCaseInsensitiveContains(query) ?? false)
                || ($0.phone?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }
}
