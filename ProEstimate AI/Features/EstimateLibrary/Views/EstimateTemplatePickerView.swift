import SwiftUI

struct EstimateTemplatePickerView: View {
    let onSelect: (EstimateTemplate) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var model = EstimateLibraryViewModel(service: EstimateLibraryService())
    @State private var query = ""
    @State private var actionError: String?
    @State private var deleting: EstimateTemplate?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Reuse your saved scope, line items and pricing. Client details, old photos and approvals stay with the original job.")
                        .font(TypographyTokens.subheadline)
                        .foregroundStyle(ColorTokens.secondaryText)
                }
                if let message = model.errorMessage ?? actionError {
                    Section { Text(message); Button("Refresh templates") { Task { await load() } } }
                }
                Section("Your templates") {
                    ForEach(model.templates) { template in
                        Button { onSelect(template); dismiss() } label: {
                            VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                                Text(template.name).font(TypographyTokens.headline).foregroundStyle(ColorTokens.primaryText)
                                if let description = template.description, !description.isEmpty {
                                    Text(description).font(TypographyTokens.subheadline).foregroundStyle(ColorTokens.secondaryText)
                                }
                                HStack {
                                    Text("\(template.itemCount) items · \(template.projectType.displayName)")
                                    Spacer()
                                    CurrencyText(amount: template.totalAmount, font: TypographyTokens.moneyCaption)
                                }
                                .font(TypographyTokens.caption)
                                .foregroundStyle(ColorTokens.secondaryText)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, SpacingTokens.xs)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Use this template for a new draft estimate")
                        .swipeActions { Button("Delete", role: .destructive) { deleting = template } }
                    }
                    if model.isLoading { ProgressView("Loading templates…") }
                    if model.templates.isEmpty, !model.isLoading, model.errorMessage == nil {
                        Text(query.isEmpty ? "Save an estimate as a template from its editor to reuse it here." : "No templates match this search.")
                            .foregroundStyle(ColorTokens.secondaryText)
                    }
                    if model.nextCursor != nil {
                        Button("Load more templates") { Task { await load(more: true) } }.disabled(model.isLoading)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search saved templates")
            .navigationTitle("Choose template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task(id: "\(scope):\(query)") {
                do { try await Task.sleep(for: .milliseconds(250)); await load() } catch {}
            }
            .refreshable { await load() }
            .confirmationDialog("Delete this template?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete template", role: .destructive) {
                    guard let template = deleting else { return }
                    deleting = nil
                    Task {
                        do { try await EstimateLibraryService().removeTemplate(id: template.id); await load() }
                        catch { actionError = error.localizedDescription }
                    }
                }
                Button("Cancel", role: .cancel) { deleting = nil }
            } message: { Text("Existing estimates and their sent versions stay saved.") }
        }
    }
    private var scope: String { "\(appState.currentUser?.id ?? ""): \(appState.currentCompany?.id ?? "")" }
    private func load(more: Bool = false) async { actionError = nil; await model.load(mode: .templates, scope: scope, query: query, more: more) }
}

struct SaveEstimateTemplateSheet: View {
    let estimate: Estimate
    let onSaved: (EstimateTemplate) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var details = ""
    @State private var mutation = EstimateLibraryMutationModel(service: EstimateLibraryService())
    init(estimate: Estimate, onSaved: @escaping (EstimateTemplate) -> Void = { _ in }) {
        self.estimate = estimate; self.onSaved = onSaved
        _name = State(initialValue: estimate.title ?? estimate.estimateNumber)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Template") {
                    TextField("Template name", text: $name)
                    TextField("Description (optional)", text: $details, axis: .vertical).lineLimit(3 ... 6)
                }
                .disabled(mutation.pending || mutation.isWorking)
                Section {
                    Text("Save the line items, rates, markup, tax, notes and reusable proposal terms. New estimates are drafts with their own number. Review prices before sending.")
                        .font(TypographyTokens.subheadline).foregroundStyle(ColorTokens.secondaryText)
                }
                if let message = mutation.errorMessage { Section { Text(message) } }
                if mutation.isWorking { ProgressView("Saving template…") }
            }
            .navigationTitle("Save template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(mutation.isWorking) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mutation.pending ? "Retry save" : "Save") {
                        Task { if let result = await mutation.saveTemplate(estimateId: estimate.id, name: name, description: details) { onSaved(result); dismiss() } }
                    }.disabled(mutation.isWorking || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(mutation.isWorking)
            .scrollDismissesKeyboard(.interactively)
        }
    }
}
