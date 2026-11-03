import SwiftUI

/// One input page followed directly by the real estimate editor. Projects stay
/// organized behind the estimate, without requiring a separate setup wizard.
struct EstimateCreationFlowView: View {
    let onOpenProject: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(FeatureGateCoordinator.self) private var featureGate
    @Environment(PaywallPresenter.self) private var paywall
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = EstimateCreationViewModel(service: EstimateCreationService(), draftStore: EstimateDraftStore.shared)
    @State private var clientPicker: ClientPickerRoute?
    @State private var editor: EstimateEditorRoute?
    @State private var showTemplates = false
    @State private var selectedTemplateName: String?
    @State private var confirmReplaceInputs = false
    @State private var confirmStartNew = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Start with the work. Review every item before sending anything to your client.")
                        .font(TypographyTokens.subheadline)
                        .foregroundStyle(ColorTokens.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                draftRecoverySection
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
                    .disabled(model.isCreating || model.recovery != .none || model.hasRecoverableDraft || model.isTemplateReplayPending)
                    if model.draft.method == .template {
                        Button { showTemplates = true } label: {
                            Label(selectedTemplateName ?? (model.draft.templateId == nil ? "Choose saved template" : "Saved template selected"), systemImage: "doc.on.doc")
                        }
                        .disabled(model.isCreating || model.recovery != .none || model.hasRecoverableDraft || model.isTemplateReplayPending)
                    }
                    Text(startingPointDescription)
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
                                Text(model.isCreating ? "Preparing estimate…" : (model.isTemplateReplayPending ? "Retry saved template" : (model.createdProject == nil ? "Continue to estimate" : "Continue saved project")))
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
                    Button("Close") { Task { await model.saveDraftNow(); dismiss() } }.disabled(model.isCreating)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .interactiveDismissDisabled(model.isCreating)
            .task(id: "\(appState.currentUser?.id ?? ""):\(appState.currentCompany?.id ?? "")") {
                if let companyId = appState.currentCompany?.id, let userId = appState.currentUser?.id {
                    await model.loadClients(companyId: companyId)
                    await model.restoreDraft(userId: userId, companyId: companyId)
                }
            }
            .onChange(of: scenePhase) { _, phase in if phase != .active { Task { await model.saveDraftNow() } } }
            .onDisappear { Task { await model.saveDraftNow() } }
            .sheet(item: $clientPicker) { _ in
                EstimateCreationClientPicker(model: model)
            }
            .sheet(item: $editor, onDismiss: openSavedProject) { target in
                EstimateEditorView(estimateId: target.id)
            }
            .sheet(isPresented: $showTemplates) {
                EstimateTemplatePickerView { template in
                    model.draft.templateId = template.id
                    selectedTemplateName = template.name
                    if model.draft.trimmedTitle.isEmpty { model.draft.title = template.name }
                    if !model.inputsLocked { model.draft.projectType = template.projectType }
                }
            }
            .confirmationDialog("Replace the current form with your saved draft?", isPresented: $confirmReplaceInputs, titleVisibility: .visible) {
                Button("Resume saved draft") { _ = model.resumeRecoveredDraft(replacingCurrentInputs: true) }
                Button("Keep current form", role: .cancel) {}
            }
            .confirmationDialog("Start a new draft?", isPresented: $confirmStartNew, titleVisibility: .visible) {
                Button("Start new draft", role: .destructive) { Task { await model.startNewDraft(); selectedTemplateName = nil } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Only the recovery copy on this device is cleared. Projects and estimates already saved to your account remain available.") }
        }
    }

    private var startingPointDescription: String {
        switch model.draft.method {
        case .manual: "Add your own materials and labor. Manual drafting is free."
        case .ai: "AI writes a draft from your scope. Requires an active trial or subscription and uses an AI estimate allowance. No image is generated."
        case .template: "Reuse saved scope and pricing in a new draft. No AI allowance is used. Review rates and quantities for this job."
        }
    }

    @ViewBuilder private var draftRecoverySection: some View {
        if model.hasRecoverableDraft {
            Section("Saved on this device") {
                Text(model.recoveredDraftNotice ?? "A previous draft is available.")
                if model.canResumeRecoveredDraft {
                    Button("Resume saved draft") {
                        if !model.resumeRecoveredDraft(), model.restoreNeedsConfirmation { confirmReplaceInputs = true }
                    }
                }
                Button("Start new draft") { confirmStartNew = true }
            }
        } else if model.isDraftSavedOnDevice || model.draftSaveError != nil || model.createdEstimate != nil {
            Section {
                if let error = model.draftSaveError {
                    Text(error).font(TypographyTokens.footnote)
                    Button("Retry saving draft") { Task { await model.saveDraftNow() } }
                } else if model.isDraftSavedOnDevice {
                    Label("Draft saved on this device", systemImage: "checkmark.circle").font(TypographyTokens.caption).foregroundStyle(ColorTokens.secondaryText)
                }
                if let estimate = model.createdEstimate {
                    Button("Open saved estimate") { editor = EstimateEditorRoute(id: estimate.id) }
                }
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
        Task {
            if model.createdEstimate != nil { await model.finishDraft() } else { await model.saveDraftNow() }
            AppEventBus.shared.noteProjectChange()
            onOpenProject(projectId)
            dismiss()
        }
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
