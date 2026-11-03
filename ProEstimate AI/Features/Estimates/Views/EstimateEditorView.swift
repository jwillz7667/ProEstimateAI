import SwiftUI

struct EstimateEditorView: View {
    @Environment(AppState.self) private var appState
    let initialNotice: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(FeatureGateCoordinator.self) private var featureGate
    @Environment(PaywallPresenter.self) private var paywall
    @State private var viewModel: EstimateEditorViewModel
    @State private var delivery = EstimateDeliveryViewModel(service: EstimateDeliveryService())
    @State private var clientPicker = EstimateCreationViewModel(service: EstimateCreationService())
    @State private var destination: EstimateEditorDestination?
    @State private var pendingClient: Client?
    @State private var confirmRevision = false
    @State private var confirmDuplicate = false
    @State private var libraryMutation = EstimateLibraryMutationModel(service: EstimateLibraryService())

    init(estimateId: String, initialNotice: String? = nil) {
        self.initialNotice = initialNotice
        _viewModel = State(initialValue: EstimateEditorViewModel(estimateId: estimateId))
    }

    var body: some View {
        NavigationStack {
            Form {
                if let estimate = viewModel.estimate {
                    documentSection(estimate)
                    clientSection(estimate)
                    if let initialNotice {
                        Section { Text(initialNotice).font(TypographyTokens.subheadline) }
                    }
                    errorSection
                    itemsSection
                    totalsSection(estimate)
                    documentNotes(estimate)
                    reuseSection(estimate)
                    nextActionsSection(estimate)
                } else if viewModel.isLoading {
                    ProgressView("Loading estimate…")
                } else {
                    errorSection
                }
            }
            .navigationTitle("Estimate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(viewModel.isSaving || delivery.isWorking || libraryMutation.isWorking)
                }
            }
            .refreshable { await refresh() }
            .task { await refresh() }
            .sheet(item: $destination, onDismiss: destinationDismissed) { target in
                switch target {
                case let .line(selection): EstimateLineEditorSheet(model: viewModel, selection: selection)
                case let .changeOrder(id): NavigationStack { ChangeOrderDetailView(orderId: id) }
                case let .newChangeOrder(estimate): CreateChangeOrderView(estimate: estimate)
                case let .document(estimate): EstimateDocumentFormView(model: viewModel, estimate: estimate)
                case .client:
                    EstimateCreationClientPicker(model: clientPicker, allowsNoClient: false) { client in pendingClient = client }
                case let .proposal(proposal):
                    ProposalPreviewView(proposal: proposal, reviewedEstimate: viewModel.estimate,
                                        client: proposal.status == .draft ? delivery.client : nil)
                case let .revision(estimate): EstimateEditorView(estimateId: estimate.id, initialNotice: "This is a new draft revision. The previously sent version stays unchanged.")
                case let .invoice(invoice):
                    NavigationStack { InvoiceDetailView(invoiceId: invoice.id, isPresentedInSheet: true) }
                case .savedItems:
                    EstimateSavedItemsView(estimateId: viewModel.estimateId) { AppEventBus.shared.noteProjectChange() }
                case let .saveTemplate(estimate): SaveEstimateTemplateSheet(estimate: estimate)
                case let .saveLibraryItem(item): EstimateLibraryItemEditorView(sourceLine: item)
                case let .priceReview(item): EstimatePriceReviewView(item: item)
                case let .copy(estimate): EstimateEditorView(estimateId: estimate.id, initialNotice: "This is a new draft copy. Prices were calculated from the copied items. Review them before sending.")
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving || delivery.isWorking || libraryMutation.isWorking)
            .confirmationDialog("Create a new draft revision?", isPresented: $confirmRevision, titleVisibility: .visible) {
                Button("Create revision") { Task { await revise() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The sent version and its approval history stay unchanged. Review and send the new version separately.")
            }
            .confirmationDialog("Duplicate this estimate?", isPresented: $confirmDuplicate, titleVisibility: .visible) {
                Button("Create draft copy") { Task { await duplicate() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("A separate draft is created in this project with a new estimate number. Existing sent versions and approvals stay unchanged.")
            }
        }
    }

    private func documentSection(_ estimate: Estimate) -> some View {
        Section {
            VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                Text(estimate.title ?? estimate.estimateNumber)
                    .font(TypographyTokens.title3)
                Text("\(estimate.estimateNumber) · Version \(estimate.version)")
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(ColorTokens.secondaryText)
                Text(estimate.status.rawValue.capitalized)
                    .font(TypographyTokens.caption.weight(.semibold))
                if !estimate.isEditable {
                    Text("This estimate is read-only because it is no longer a draft. You can still review every item and its saved total.")
                        .font(TypographyTokens.footnote)
                        .foregroundStyle(ColorTokens.secondaryText)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if estimate.isEditable {
                Button("Edit scope, notes & discount") { destination = .document(estimate) }
                    .disabled(!viewModel.canEdit || delivery.isWorking || libraryMutation.isWorking || appState.currentUser?.canEdit != true)
            }
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let message = viewModel.errorMessage {
            Section {
                Text(message)
                    .font(TypographyTokens.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Refresh estimate") { Task { await viewModel.load() } }
                    .disabled(viewModel.isLoading || viewModel.isSaving)
            }
        }
    }

    private var itemsSection: some View {
        Section {
            if viewModel.lineItems.isEmpty {
                Text("Add materials, labor or other costs to build this estimate. Nothing is charged for manual edits.")
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(ColorTokens.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(viewModel.lineItems) { item in
                Group {
                if viewModel.canEdit && appState.currentUser?.canEdit == true {
                    Button {
                        destination = .line(LineEditorSelection(itemId: item.id, form: EstimateLineItemForm(item: item)))
                    } label: {
                        lineItemRow(item, editable: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Edit quantity, unit cost, markup or tax")
                } else {
                    lineItemRow(item, editable: false)
                }
                }
                .contextMenu {
                    Button { destination = .saveLibraryItem(item) } label: {
                        Label("Save to item library", systemImage: "books.vertical")
                    }
                    .disabled(appState.currentUser?.canEdit != true)
                }
                if viewModel.canEdit && appState.currentUser?.canEdit == true {
                    Button("Check price & quantity") { destination = .priceReview(item) }
                        .font(TypographyTokens.caption.weight(.semibold))
                        .frame(minHeight: 44)
                }
            }
            if viewModel.estimate?.isEditable == true && appState.currentUser?.canEdit == true {
                Button {
                    destination = .line(LineEditorSelection(itemId: nil, form: viewModel.newItemForm()))
                } label: {
                    Label("Add line item", systemImage: "plus.circle")
                }
                .disabled(!viewModel.canEdit)
                Button { destination = .savedItems } label: {
                    Label("Add from saved items", systemImage: "books.vertical")
                }
                .disabled(!viewModel.canEdit)
            }
        } header: {
            Text("Line items")
        } footer: {
            Text(viewModel.requiresRefresh
                ? "Refresh before making changes. Saved totals are shown until the document is current."
                : "Amounts below are calculated and saved by the server after each change.")
        }
    }

    private func lineItemRow(_ item: EstimateLineItem, editable: Bool) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.name)
                    .font(TypographyTokens.headline)
                    .foregroundStyle(ColorTokens.primaryText)
                Spacer(minLength: SpacingTokens.xs)
                if editable {
                    Image(systemName: "pencil")
                        .font(.footnote)
                        .foregroundStyle(ColorTokens.secondaryText)
                        .accessibilityHidden(true)
                }
            }
            Text(item.category.rawValue.capitalized)
                .font(TypographyTokens.caption)
                .foregroundStyle(ColorTokens.secondaryText)
            if let description = item.description, !description.isEmpty {
                Text(description)
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(ColorTokens.secondaryText)
            }
            HStack {
                Text("\(item.quantity.formatted()) \(item.unit) × ")
                CurrencyText(amount: item.unitCost, font: TypographyTokens.moneyCaption)
                Spacer(minLength: 0)
            }
            .font(TypographyTokens.caption)
            .foregroundStyle(ColorTokens.secondaryText)
            Text("Markup \(item.markupPercent.formatted())% · Tax \(item.taxRate.formatted())%")
                .font(TypographyTokens.caption)
                .foregroundStyle(ColorTokens.secondaryText)
            Text(item.priceOriginLabel)
                .font(TypographyTokens.caption)
                .foregroundStyle(ColorTokens.secondaryText)
            if let checkedAt = item.priceCheckedAt {
                Text("Base price checked by contractor · \(checkedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.secondaryText)
                if let source = item.priceSourceLabel { Text(source).font(TypographyTokens.caption) }
            } else {
                Text("Base price not checked")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.secondaryText)
            }
            if let basis = item.quantityBasis, item.quantityCheckedAt != nil {
                Text("Quantity basis: \(basis)").font(TypographyTokens.caption)
            }
            HStack {
                Text("Line subtotal")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.secondaryText)
                Spacer()
                CurrencyText(amount: item.lineTotal)
                    .foregroundStyle(ColorTokens.primaryText)
            }
        }
        .padding(.vertical, SpacingTokens.xxs)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func totalsSection(_ estimate: Estimate) -> some View {
        Section("Saved totals") {
            moneyRow("Materials", estimate.subtotalMaterials)
            moneyRow("Labor", estimate.subtotalLabor)
            moneyRow("Other", estimate.subtotalOther)
            moneyRow("Tax", estimate.taxAmount)
            if estimate.discountAmount > 0 { moneyRow("Discount", -estimate.discountAmount) }
            if let contingency = estimate.contingencyAmount, contingency > 0 {
                moneyRow("Contingency reference", contingency)
                Text("Reference only. Include contingency in the line items when pricing the work.")
                    .font(TypographyTokens.footnote).foregroundStyle(ColorTokens.secondaryText)
            }
            moneyRow("Total", estimate.totalAmount)
                .fontWeight(.semibold)
        }
    }

    private func moneyRow(_ title: String, _ value: Decimal) -> some View {
        LabeledContent(title) { CurrencyText(amount: value) }
    }

    private func clientSection(_ estimate: Estimate) -> some View {
        Section("Client") {
            if let client = delivery.client {
                Text(client.name).font(TypographyTokens.headline)
                if let contact = client.email ?? client.phone {
                    Text(contact).font(TypographyTokens.subheadline).foregroundStyle(ColorTokens.secondaryText)
                }
            } else {
                Text(delivery.isLoading ? "Loading client…" : "Choose a client before sending.")
                    .foregroundStyle(ColorTokens.secondaryText)
            }
            if appState.currentUser?.canEdit == true && (estimate.isEditable || (estimate.status == .approved && delivery.client == nil)) {
                Button(delivery.client == nil ? "Choose or add client" : "Change client") {
                    Task {
                        await clientPicker.loadClients(companyId: estimate.companyId)
                        clientPicker.selectClient(delivery.client)
                        destination = .client
                    }
                }
                .disabled(delivery.isWorking || delivery.isLoading || viewModel.isSaving || delivery.needsClientRefresh)
            }
            if delivery.needsClientRefresh {
                Button("Refresh client details") { Task { await delivery.load(for: estimate) } }
                    .disabled(delivery.isWorking || delivery.isLoading)
            }
        }
    }

    private func nextActionsSection(_ estimate: Estimate) -> some View {
        Section {
            if estimate.isEditable && !viewModel.lineItems.isEmpty {
                let checkedPrices = viewModel.lineItems.filter { $0.priceCheckedAt != nil }.count
                let checkedQuantities = viewModel.lineItems.filter { $0.quantityCheckedAt != nil }.count
                Text("Base prices checked: \(checkedPrices) of \(viewModel.lineItems.count)")
                    .font(TypographyTokens.footnote).foregroundStyle(ColorTokens.secondaryText)
                Text("Quantities checked: \(checkedQuantities) of \(viewModel.lineItems.count)")
                    .font(TypographyTokens.footnote).foregroundStyle(ColorTokens.secondaryText)
            }
            if let changeOrderId = estimate.changeOrderId {
                Button("Review change order & billing") { destination = .changeOrder(changeOrderId) }
            }
            if estimate.status == .approved && estimate.changeOrderId == nil && appState.currentUser?.canEdit == true {
                Button(delivery.needsInvoiceReconciliation ? "Check saved invoice" : "Create invoice") {
                    Task { await invoice() }
                }
                .font(TypographyTokens.headline)
            }
            Button {
                Task { await reviewAndSend() }
            } label: {
                Label(delivery.needsProposalReconciliation ? "Check saved proposal" : (estimate.isEditable ? "Review & send" : "View sent proposal"),
                      systemImage: estimate.isEditable ? "paperplane" : "doc.text.magnifyingglass")
                    .font(estimate.isEditable ? TypographyTokens.headline : TypographyTokens.subheadline)
            }
            .disabled((estimate.isEditable && viewModel.lineItems.isEmpty) || viewModel.requiresRefresh || (estimate.isEditable && appState.currentUser?.canEdit != true))
            if !estimate.isEditable && appState.currentUser?.canEdit == true {
                if estimate.status == .approved {
                    Button("Create change order") { destination = .newChangeOrder(estimate) }
                }
                if estimate.changeOrderId == nil { Button("Create revision") { confirmRevision = true } }
            }
            if delivery.isWorking { ProgressView("Preparing next step…") }
            if let message = delivery.errorMessage {
                Text(message).font(TypographyTokens.footnote).fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Next step")
        } footer: {
            if estimate.isEditable {
                Text("Review the client, line items and total before sending. Sending preserves this version; future changes use a new revision.")
            }
        }
        .disabled(delivery.isWorking || delivery.isLoading || viewModel.isSaving || viewModel.isLoading)
    }

    private func reuseSection(_ estimate: Estimate) -> some View {
        Section("Reuse this work") {
            Button { destination = .saveTemplate(estimate) } label: {
                Label("Save as template", systemImage: "doc.badge.plus")
            }
            Button(libraryMutation.pending ? "Check draft copy" : "Duplicate estimate") {
                if libraryMutation.pending { Task { await duplicate() } }
                else { confirmDuplicate = true }
            }
            if libraryMutation.isWorking { ProgressView("Preparing draft copy…") }
            if let message = libraryMutation.errorMessage { Text(message).font(TypographyTokens.footnote) }
        }
        .disabled(viewModel.isLoading || viewModel.isSaving || delivery.isWorking || libraryMutation.isWorking || viewModel.requiresRefresh || appState.currentUser?.canEdit != true)
    }

    private func duplicate() async {
        guard let estimate = viewModel.estimate else { return }
        if let result = await libraryMutation.duplicate(estimate: estimate) {
            AppEventBus.shared.noteProjectChange()
            destination = .copy(result)
        }
    }

    private func refresh() async {
        await viewModel.load()
        if let estimate = viewModel.estimate { await delivery.load(for: estimate) }
    }

    private func destinationDismissed() {
        Task {
            if let client = pendingClient, let estimate = viewModel.estimate {
                pendingClient = nil
                _ = await delivery.assign(client: client, estimate: estimate)
            }
            await refresh()
            AppEventBus.shared.noteProjectChange()
        }
    }

    private func reviewAndSend() async {
        guard let estimate = viewModel.estimate else { return }
        if estimate.isEditable {
            switch featureGate.guardShareApprovalLink() {
            case .allowed: break
            case let .blocked(decision): paywall.present(decision); return
            }
        }
        if let proposal = await delivery.prepareProposal(estimate: estimate, hasLineItems: !viewModel.lineItems.isEmpty) {
            destination = .proposal(proposal)
        } else { showServerPaywall() }
    }

    private func revise() async {
        guard let estimate = viewModel.estimate else { return }
        if let revised = await delivery.revise(estimate: estimate) {
            AppEventBus.shared.noteProjectChange()
            destination = .revision(revised)
        } else { showServerPaywall() }
    }

    private func invoice() async {
        guard let estimate = viewModel.estimate else { return }
        switch featureGate.guardCreateInvoice() {
        case .allowed: break
        case let .blocked(decision): paywall.present(decision); return
        }
        if let invoice = await delivery.convertToInvoice(estimate: estimate) {
            AppEventBus.shared.noteProjectChange()
            destination = .invoice(invoice)
        } else { showServerPaywall() }
    }

    private func showServerPaywall() {
        if let error = delivery.lastError as? APIError, case let .paywall(decision) = error { paywall.present(decision) }
    }

    @ViewBuilder
    private func documentNotes(_ estimate: Estimate) -> some View {
        if let assumptions = estimate.assumptions, !assumptions.isEmpty {
            Section("Assumptions") { Text(assumptions) }
        }
        if let exclusions = estimate.exclusions, !exclusions.isEmpty {
            Section("Exclusions") { Text(exclusions) }
        }
        if let notes = estimate.notes, !notes.isEmpty {
            Section("Notes") { Text(notes) }
        }
    }
}

private enum EstimateEditorDestination: Identifiable {
    case line(LineEditorSelection)
    case document(Estimate)
    case changeOrder(String)
    case newChangeOrder(Estimate)
    case client
    case proposal(Proposal)
    case revision(Estimate)
    case invoice(Invoice)
    case savedItems
    case saveTemplate(Estimate)
    case saveLibraryItem(EstimateLineItem)
    case priceReview(EstimateLineItem)
    case copy(Estimate)

    var id: String {
        switch self {
        case let .line(selection): "line-\(selection.id)"
        case let .changeOrder(id): "change-order-\(id)"
        case let .newChangeOrder(estimate): "new-change-order-\(estimate.id)"
        case let .document(estimate): "document-\(estimate.id)"
        case .client: "client"
        case let .proposal(proposal): "proposal-\(proposal.id)"
        case let .revision(estimate): "revision-\(estimate.id)"
        case let .invoice(invoice): "invoice-\(invoice.id)"
        case .savedItems: "saved-items"
        case let .saveTemplate(estimate): "save-template-\(estimate.id)"
        case let .saveLibraryItem(item): "save-library-item-\(item.id)"
        case let .priceReview(item): "price-review-\(item.id)"
        case let .copy(estimate): "copy-\(estimate.id)"
        }
    }
}

private struct LineEditorSelection: Identifiable {
    let id = UUID()
    let itemId: String?
    let form: EstimateLineItemForm
}

private struct EstimateLineEditorSheet: View {
    let model: EstimateEditorViewModel
    let selection: LineEditorSelection
    @Environment(\.dismiss) private var dismiss
    @State private var form: EstimateLineItemForm
    @State private var showDiscard = false
    @State private var showRemove = false

    init(model: EstimateEditorViewModel, selection: LineEditorSelection) {
        self.model = model
        self.selection = selection
        _form = State(initialValue: selection.form)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    Picker("Category", selection: $form.category) {
                        ForEach(EstimateLineItem.Category.allCases, id: \.self) { category in
                            Text(category.rawValue.capitalized).tag(category)
                        }
                    }
                    TextField("Item name", text: $form.name, axis: .vertical)
                        .lineLimit(1 ... 4)
                    TextField("Description (optional)", text: $form.details, axis: .vertical)
                        .lineLimit(3 ... 8)
                }
                Section {
                    decimalField("Quantity", text: $form.quantity)
                    LabeledContent("Unit") {
                        TextField("each, hours, sq ft…", text: $form.unit)
                            .multilineTextAlignment(.trailing)
                    }
                    decimalField("Unit cost", text: $form.unitCost)
                    decimalField("Markup (%)", text: $form.markupPercent)
                    decimalField("Tax (%)", text: $form.taxPercent)
                } header: {
                    Text("Pricing")
                } footer: {
                    Text("Enter percentages as shown: 8.25 means 8.25%. The saved estimate total updates after you save.")
                }
                if let message = model.errorMessage {
                    Section {
                        Text(message)
                        if model.requiresRefresh {
                            Button("Review saved estimate") {
                                Task { await model.load(); dismiss() }
                            }
                        }
                    }
                }
                if selection.itemId != nil {
                    Section {
                        Button("Remove line item", role: .destructive) { showRemove = true }
                            .disabled(!model.canEdit)
                    }
                }
            }
            .disabled(model.isSaving)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(selection.itemId == nil ? "Add line item" : "Edit line item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if form != selection.form { showDiscard = true } else { dismiss() }
                    }
                    .disabled(model.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await model.save(itemId: selection.itemId, form: form) { dismiss() }
                        }
                    }
                    .disabled(!model.canEdit)
                }
            }
            .interactiveDismissDisabled(model.isSaving || form != selection.form)
            .confirmationDialog("Discard your changes?", isPresented: $showDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
            .confirmationDialog("Remove this line item?", isPresented: $showRemove, titleVisibility: .visible) {
                Button("Remove line item", role: .destructive) {
                    if let itemId = selection.itemId {
                        Task { if await model.remove(itemId: itemId) { dismiss() } }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func decimalField(_ title: String, text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(title)
        }
    }
}
