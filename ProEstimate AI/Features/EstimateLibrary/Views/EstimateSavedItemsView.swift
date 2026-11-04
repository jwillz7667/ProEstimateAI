import SwiftUI

struct EstimateSavedItemsView: View {
    let estimateId: String
    let onApplied: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var model = EstimateLibraryViewModel(service: EstimateLibraryService())
    @State private var mutation = EstimateLibraryMutationModel(service: EstimateLibraryService())
    @State private var query = ""
    @State private var editing: SavedItemEditorRoute?
    @State private var applying: SavedEstimateLibraryItem?
    @State private var deleting: SavedEstimateLibraryItem?
    @State private var actionError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Tap an item to add its saved quantity, price, markup and tax. You can adjust the new line in the estimate editor.")
                        .font(TypographyTokens.subheadline).foregroundStyle(ColorTokens.secondaryText)
                }
                if let message = model.errorMessage ?? mutation.errorMessage ?? actionError {
                    Section {
                        Text(message)
                        if mutation.pending, let item = applying {
                            Button("Check added item") { Task { await apply(item) } }.disabled(mutation.isWorking)
                        } else { Button("Refresh items") { Task { await load() } } }
                    }
                }
                Section("Saved items") {
                    ForEach(model.items) { item in
                        Button { Task { await apply(item) } } label: {
                            VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                                Text(item.name).font(TypographyTokens.headline).foregroundStyle(ColorTokens.primaryText)
                                HStack {
                                    Text("\(item.quantity.formatted()) \(item.unit) · \(item.category.rawValue.capitalized)")
                                    Spacer()
                                    CurrencyText(amount: item.unitCost, font: TypographyTokens.moneyCaption)
                                }
                                Text("Markup \(item.markupPercent.formatted())% · Tax \((item.taxRate * 100).formatted())%")
                            }
                            .font(TypographyTokens.caption).foregroundStyle(ColorTokens.secondaryText)
                            .fixedSize(horizontal: false, vertical: true).padding(.vertical, SpacingTokens.xs)
                        }
                        .buttonStyle(.plain)
                        .disabled(mutation.isWorking || (mutation.pending && applying?.id != item.id))
                        .accessibilityHint("Add this saved item to the current draft")
                        .contextMenu {
                            Button("Edit saved item") { editing = .init(item: item) }
                            Button("Delete saved item", role: .destructive) { deleting = item }
                        }
                    }
                    if model.isLoading || mutation.isWorking { ProgressView(mutation.isWorking ? "Adding saved item…" : "Loading saved items…") }
                    if model.items.isEmpty, !model.isLoading, model.errorMessage == nil {
                        Text(query.isEmpty ? "Create your first saved item using the plus button, or save a line from an estimate." : "No saved items match this search.")
                            .foregroundStyle(ColorTokens.secondaryText)
                    }
                    if model.nextCursor != nil { Button("Load more items") { Task { await load(more: true) } }.disabled(model.isLoading) }
                }
            }
            .searchable(text: $query, prompt: "Search materials and labor")
            .navigationTitle("Saved items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(mutation.isWorking) }
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = .init(item: nil) } label: { Label("New saved item", systemImage: "plus") }
                        .disabled(mutation.isWorking || mutation.pending)
                }
            }
            .task(id: "\(scope):\(query)") {
                do { try await Task.sleep(for: .milliseconds(250)); await load() } catch {}
            }
            .sheet(item: $editing, onDismiss: { Task { await load() } }) { route in
                EstimateLibraryItemEditorView(item: route.item)
            }
            .refreshable { await load() }
            .interactiveDismissDisabled(mutation.isWorking)
            .confirmationDialog("Delete this saved item?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete saved item", role: .destructive) {
                    guard let item = deleting else { return }; deleting = nil
                    Task { do { try await EstimateLibraryService().removeItem(id: item.id); await load() } catch { actionError = error.localizedDescription } }
                }
                Button("Cancel", role: .cancel) { deleting = nil }
            } message: { Text("Items already added to estimates stay unchanged.") }
        }
    }
    private var scope: String { "\(appState.currentUser?.id ?? ""): \(appState.currentCompany?.id ?? "")" }
    private func load(more: Bool = false) async { actionError = nil; await model.load(mode: .items, scope: scope, query: query, more: more) }
    private func apply(_ item: SavedEstimateLibraryItem) async {
        applying = item
        if await mutation.applyItem(id: item.id, estimateId: estimateId) { onApplied(); dismiss() }
    }
    private struct SavedItemEditorRoute: Identifiable { let id = UUID(); let item: SavedEstimateLibraryItem? }
}

struct EstimateLibraryItemEditorView: View {
    let item: SavedEstimateLibraryItem?
    let itemType: String?
    @Environment(\.dismiss) private var dismiss
    @State private var form: EstimateLineItemForm
    @State private var mutation = EstimateLibraryMutationModel(service: EstimateLibraryService())

    init(item: SavedEstimateLibraryItem? = nil, sourceLine: EstimateLineItem? = nil) {
        self.item = item; itemType = item?.itemType ?? sourceLine?.itemType ?? "per_unit"
        _form = State(initialValue: item?.editForm() ?? sourceLine.map { EstimateLineItemForm(item: $0) } ?? EstimateLineItemForm())
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    Picker("Category", selection: $form.category) {
                        ForEach(EstimateLineItem.Category.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    TextField("Name", text: $form.name, axis: .vertical).lineLimit(1 ... 4)
                    TextField("Description (optional)", text: $form.details, axis: .vertical).lineLimit(3 ... 6)
                }
                .disabled(mutation.pending || mutation.isWorking)
                Section {
                    decimalField("Default quantity", text: $form.quantity)
                    TextField("Unit (each, hours, sq ft)", text: $form.unit)
                    decimalField("Unit cost", text: $form.unitCost)
                    decimalField("Markup (%)", text: $form.markupPercent)
                    decimalField("Tax (%)", text: $form.taxPercent)
                } header: { Text("Reusable pricing") } footer: { Text("Saving changes your library only. Existing estimates keep their own saved prices.") }
                .disabled(mutation.pending || mutation.isWorking)
                if let message = mutation.errorMessage { Section { Text(message) } }
                if mutation.isWorking { ProgressView("Saving item…") }
            }
            .navigationTitle(item == nil ? "Save library item" : "Edit library item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(mutation.isWorking) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mutation.pending ? "Retry save" : "Save") {
                        Task { if await mutation.saveItem(form: form, itemId: item?.id, itemType: itemType) != nil { dismiss() } }
                    }.disabled(mutation.isWorking)
                }
            }
            .interactiveDismissDisabled(mutation.isWorking)
            .scrollDismissesKeyboard(.interactively)
        }
    }
    private func decimalField(_ title: String, text: Binding<String>) -> some View {
        LabeledContent(title) { TextField("0", text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityLabel(title) }
    }
}
