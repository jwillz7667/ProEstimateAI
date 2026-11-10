import SwiftUI
import QuickLook

struct JobCostView: View {
    let projectTitle: String
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var model: JobCostViewModel
    @State private var route: CostSheet?
    @State private var includeVoided = false
    @State private var entryToVoid: JobCostEntry?
    @State private var previewURL: URL?
    @State private var previewError: String?
    @State private var isLoadingReceipt = false

    init(projectId: String, projectTitle: String = "Project") {
        self.projectTitle = projectTitle
        _model = State(initialValue: JobCostViewModel(projectId: projectId, service: JobCostService(), journal: JobCostPendingJournal()))
    }

    var body: some View {
        NavigationStack {
            costsList
                .navigationTitle("Costs & receipts")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(model.isWorking) }
                }
                .task(id: workspaceScope) { await reload() }
                .refreshable { await reload() }
                .sheet(item: $route, onDismiss: { Task { await reload() } }) { route in
                    switch route {
                    case .create: JobCostFormView(model: model)
                    case let .attach(entry): JobCostAttachReceiptView(entry: entry, model: model)
                    }
                }
                .quickLookPreview($previewURL)
                .onChange(of: previewURL) { old, new in
                    if let old, new != old { Task { await JobCostReceiptFiles.shared.removePreview(old) } }
                }
                .onDisappear {
                    if let url = previewURL { Task { await JobCostReceiptFiles.shared.removePreview(url) } }
                }
                .onChange(of: includeVoided) { _, _ in Task { await reload() } }
                .onChange(of: model.savedRevision) { _, _ in AppEventBus.shared.noteProjectChange() }
                .confirmationDialog("Void this recorded cost?", isPresented: Binding(
                    get: { entryToVoid != nil }, set: { if !$0 { entryToVoid = nil } }
                ), titleVisibility: .visible) {
                    if let entry = entryToVoid {
                        Button("Void cost", role: .destructive) { Task { if await model.voidEntry(entry) { await reload() } } }
                    }
                    Button("Cancel", role: .cancel) { entryToVoid = nil }
                } message: {
                    Text("It will be excluded from active costs. The original record remains available when you show voided history.")
                }
                .interactiveDismissDisabled(model.isWorking)
        }
    }

    private var costsList: some View {
        List {
            Section {
                Text(projectTitle).font(TypographyTokens.headline)
                Button { route = .create } label: { Label("Record job cost", systemImage: "plus.circle") }
                    .disabled(!model.canAdd)
            }
            if let pending = model.pending {
                Section("Pending confirmation") {
                    Text(pending.request.description)
                    Text("Check the saved costs or retry the same locked request before recording another copy.")
                        .font(TypographyTokens.footnote).foregroundStyle(ColorTokens.secondaryText)
                    Button("Review pending cost") { route = .create }.disabled(model.isWorking || !model.canEdit)
                    Button("Check saved costs") { Task { await reload() } }.disabled(model.isLoading || model.isWorking)
                }
            }
            if let summary = model.summary { comparisonSection(summary); currencySections(summary) }
            if let entry = model.savedEntry, let error = model.receiptError {
                Section("Receipt attachment") {
                    Text(error).fixedSize(horizontal: false, vertical: true)
                    Button("Attach receipt to saved cost") { route = .attach(entry) }
                        .disabled(!model.canEdit || model.isWorking || entry.voidedAt != nil)
                }
            }
            Section {
                Toggle("Show voided history", isOn: $includeVoided)
                if model.entries.isEmpty, !model.isLoading { Text("No costs recorded here yet.").foregroundStyle(ColorTokens.secondaryText) }
                ForEach(model.entries) { entry in costRow(entry) }
                if model.nextCursor != nil {
                    Button(model.isLoadingMore ? "Loading…" : "Load more costs") { Task { await model.loadMore() } }
                        .disabled(model.isLoadingMore || model.isLoading || model.isWorking)
                }
            } header: { Text(includeVoided ? "Cost history" : "Recorded costs") }
            if model.isLoading { ProgressView("Loading recorded costs…") }
            if let error = model.errorMessage ?? previewError {
                Section {
                    Text(error).font(TypographyTokens.footnote).foregroundStyle(ColorTokens.error)
                    Button("Refresh costs") { Task { await reload() } }.disabled(model.isLoading || model.isWorking)
                }
            }
        }
    }

    private func comparisonSection(_ summary: JobCostSummary) -> some View {
        Section {
            if let number = summary.estimateNumber {
                Text("\(number) · \(summary.estimateStatus?.capitalized ?? "Estimate")")
                    .font(TypographyTokens.caption).foregroundStyle(ColorTokens.secondaryText)
            }
            if let quote = summary.quoteBeforeTax {
                LabeledContent("Quote before tax") { JobCostMoneyText(amount: quote, currencyCode: summary.currencyCode) }
            }
            if let cost = summary.estimatedItemCost {
                LabeledContent("Estimated item cost") { JobCostMoneyText(amount: cost, currencyCode: summary.currencyCode) }
            }
            LabeledContent("Recorded costs") { JobCostMoneyText(amount: summary.recordedCost, currencyCode: summary.currencyCode) }
            if let remaining = summary.quoteLessRecordedCost {
                LabeledContent("Quote less recorded costs") { JobCostMoneyText(amount: remaining, currencyCode: summary.currencyCode) }
                    .fontWeight(.semibold)
            }
        } header: { Text("Running cost comparison · \(summary.currencyCode)") }
        footer: { Text("Uses the latest approved quote when available. Before tax and overhead, based only on costs recorded here. Other currencies remain separate.") }
    }

    @ViewBuilder private func currencySections(_ summary: JobCostSummary) -> some View {
        ForEach(summary.costsByCurrency) { costs in
            Section("Recorded costs · \(costs.currencyCode)") {
                LabeledContent("Materials") { JobCostMoneyText(amount: costs.materials, currencyCode: costs.currencyCode) }
                LabeledContent("Labor") { JobCostMoneyText(amount: costs.labor, currencyCode: costs.currencyCode) }
                LabeledContent("Other") { JobCostMoneyText(amount: costs.other, currencyCode: costs.currencyCode) }
                LabeledContent("Total") { JobCostMoneyText(amount: costs.total, currencyCode: costs.currencyCode) }
            }
        }
    }

    private func costRow(_ entry: JobCostEntry) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.description).font(TypographyTokens.headline).strikethrough(entry.voidedAt != nil)
                Spacer(minLength: SpacingTokens.xs)
                JobCostMoneyText(amount: entry.amount, currencyCode: entry.currencyCode)
            }
            Text("\(entry.category.capitalized) · \(entry.recordedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(TypographyTokens.caption).foregroundStyle(ColorTokens.secondaryText)
            if let hours = entry.laborHours, let rate = entry.hourlyRate {
                HStack {
                    Text("\(hours.formatted()) hours ×").font(TypographyTokens.caption)
                    JobCostMoneyText(amount: rate, currencyCode: entry.currencyCode)
                }
            }
            if let date = entry.voidedAt {
                Label("Voided \(date.formatted(date: .abbreviated, time: .omitted))", systemImage: "minus.circle")
                    .font(TypographyTokens.caption).foregroundStyle(ColorTokens.secondaryText)
            }
            HStack {
                if entry.receiptFilename != nil {
                    Button("View receipt") { Task { await preview(entry) } }.disabled(isLoadingReceipt)
                }
                if entry.voidedAt == nil, model.canEdit {
                    Menu("Actions") {
                        Button(entry.receiptFilename == nil ? "Attach receipt" : "Replace receipt") { route = .attach(entry) }
                        Button("Void cost", role: .destructive) { entryToVoid = entry }
                    }
                    .disabled(model.isWorking)
                }
            }
            .font(TypographyTokens.subheadline)
            .frame(minHeight: 44)
        }
        .padding(.vertical, SpacingTokens.xxs)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var workspaceScope: String { "\(appState.currentUser?.id ?? ""):\(appState.currentCompany?.id ?? "")" }

    private func reload() async {
        guard let user = appState.currentUser, let companyId = appState.currentCompany?.id else { return }
        await model.load(scope: EstimateDraftScope(userId: user.id, companyId: companyId), canEdit: user.canEdit, includeVoided: includeVoided)
    }

    private func preview(_ entry: JobCostEntry) async {
        guard let filename = entry.receiptFilename, let mime = entry.receiptMimeType else { return }
        isLoadingReceipt = true
        defer { isLoadingReceipt = false }
        do {
            let data = try await model.receiptData(for: entry)
            previewURL = try await JobCostReceiptFiles.shared.preview(data: data, filename: filename, mimeType: mime)
            previewError = nil
        } catch { previewError = error.localizedDescription }
    }
}

struct JobCostMoneyText: View {
    let amount: Decimal
    let currencyCode: String
    var body: some View { Text(amount.formatted(.currency(code: currencyCode))).monospacedDigit() }
}

private enum CostSheet: Identifiable {
    case create
    case attach(JobCostEntry)
    var id: String {
        switch self {
        case .create: "create"
        case let .attach(entry): "attach-\(entry.id)"
        }
    }
}
