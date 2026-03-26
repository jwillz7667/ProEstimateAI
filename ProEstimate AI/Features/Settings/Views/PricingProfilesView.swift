import SwiftUI

struct PricingProfilesView: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var isEditing = false
    @State private var editingProfile: PricingProfileDraft?
    @State private var showingDeleteConfirmation = false
    @State private var profileToDelete: String?

    var body: some View {
        List {
            // Profiles list
            Section {
                ForEach(viewModel.pricingProfiles) { profile in
                    profileRow(profile)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if !profile.isDefault {
                                Button(role: .destructive) {
                                    profileToDelete = profile.id
                                    showingDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }

                            Button {
                                editingProfile = PricingProfileDraft(from: profile)
                                isEditing = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .onTapGesture {
                            editingProfile = PricingProfileDraft(from: profile)
                            isEditing = true
                        }
                }
            } header: {
                Text("Profiles (\(viewModel.pricingProfiles.count))")
            } footer: {
                Text("The default profile is used when creating new estimates. Tap a profile to edit.")
            }

            // Add profile button
            Section {
                Button {
                    editingProfile = PricingProfileDraft()
                    isEditing = true
                } label: {
                    Label("Add Profile", systemImage: "plus.circle")
                        .foregroundStyle(ColorTokens.primaryOrange)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Pricing Profiles")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isEditing) {
            if let draft = editingProfile {
                PricingProfileEditSheet(
                    draft: draft,
                    onSave: { updatedDraft in
                        Task {
                            let profile = updatedDraft.toPricingProfile(companyId: viewModel.company?.id ?? "c-001")
                            await viewModel.savePricingProfile(profile)
                            isEditing = false
                            editingProfile = nil
                        }
                    },
                    onCancel: {
                        isEditing = false
                        editingProfile = nil
                    }
                )
            }
        }
        .confirmationDialog(
            "Delete Profile",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = profileToDelete {
                    Task { await viewModel.deletePricingProfile(id: id) }
                }
            }
            Button("Cancel", role: .cancel) {
                profileToDelete = nil
            }
        } message: {
            Text("This profile will be permanently deleted.")
        }
    }

    // MARK: - Subviews

    private func profileRow(_ profile: PricingProfile) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                HStack(spacing: SpacingTokens.xs) {
                    Text(profile.name)
                        .font(TypographyTokens.headline)

                    if profile.isDefault {
                        Text("DEFAULT")
                            .font(TypographyTokens.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, SpacingTokens.xs)
                            .padding(.vertical, 2)
                            .background(ColorTokens.primaryOrange, in: Capsule())
                    }
                }

                HStack(spacing: SpacingTokens.md) {
                    profileStat(label: "Markup", value: "\(NSDecimalNumber(decimal: profile.defaultMarkupPercent).intValue)%")
                    profileStat(label: "Contingency", value: "\(NSDecimalNumber(decimal: profile.contingencyPercent).intValue)%")
                    profileStat(label: "Waste", value: "\(NSDecimalNumber(decimal: profile.wasteFactor * 100 - 100).intValue)%")
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, SpacingTokens.xxs)
        .contentShape(Rectangle())
    }

    private func profileStat(label: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(TypographyTokens.caption)
                .fontWeight(.semibold)
            Text(label)
                .font(TypographyTokens.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Pricing Profile Draft

struct PricingProfileDraft: Sendable {
    var id: String = UUID().uuidString
    var name: String = ""
    var defaultMarkupPercent: Decimal = 20
    var contingencyPercent: Decimal = 10
    var wasteFactor: Decimal = 1.10
    var isDefault: Bool = false
    var isExisting: Bool = false

    init() {}

    init(from profile: PricingProfile) {
        self.id = profile.id
        self.name = profile.name
        self.defaultMarkupPercent = profile.defaultMarkupPercent
        self.contingencyPercent = profile.contingencyPercent
        self.wasteFactor = profile.wasteFactor
        self.isDefault = profile.isDefault
        self.isExisting = true
    }

    /// Waste factor displayed as a percentage (e.g., 1.10 -> 10%).
    var wastePercentage: Decimal {
        (wasteFactor - 1) * 100
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func toPricingProfile(companyId: String) -> PricingProfile {
        PricingProfile(
            id: id,
            companyId: companyId,
            name: name,
            defaultMarkupPercent: defaultMarkupPercent,
            contingencyPercent: contingencyPercent,
            wasteFactor: wasteFactor,
            isDefault: isDefault,
            createdAt: Date()
        )
    }
}

// MARK: - Edit Sheet

private struct PricingProfileEditSheet: View {
    @State var draft: PricingProfileDraft
    let onSave: (PricingProfileDraft) -> Void
    let onCancel: () -> Void

    @State private var markupText: String = ""
    @State private var contingencyText: String = ""
    @State private var wasteText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile Name") {
                    TextField("e.g. Standard, Premium, Economy", text: $draft.name)
                }

                Section {
                    VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                        HStack {
                            Text("Default Markup")
                            Spacer()
                            TextField("0", text: $markupText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                                .onChange(of: markupText) { _, newValue in
                                    if let value = Decimal(string: newValue), value >= 0 {
                                        draft.defaultMarkupPercent = value
                                    }
                                }
                            Text("%")
                                .foregroundStyle(.secondary)
                        }

                        Slider(
                            value: Binding(
                                get: { NSDecimalNumber(decimal: draft.defaultMarkupPercent).doubleValue },
                                set: {
                                    draft.defaultMarkupPercent = Decimal($0)
                                    markupText = String(format: "%.0f", $0)
                                }
                            ),
                            in: 0...100,
                            step: 5
                        )
                        .tint(ColorTokens.primaryOrange)
                    }
                } header: {
                    Text("Markup")
                } footer: {
                    Text("Applied to line item base costs to calculate the client price.")
                }

                Section {
                    VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                        HStack {
                            Text("Contingency")
                            Spacer()
                            TextField("0", text: $contingencyText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                                .onChange(of: contingencyText) { _, newValue in
                                    if let value = Decimal(string: newValue), value >= 0 {
                                        draft.contingencyPercent = value
                                    }
                                }
                            Text("%")
                                .foregroundStyle(.secondary)
                        }

                        Slider(
                            value: Binding(
                                get: { NSDecimalNumber(decimal: draft.contingencyPercent).doubleValue },
                                set: {
                                    draft.contingencyPercent = Decimal($0)
                                    contingencyText = String(format: "%.0f", $0)
                                }
                            ),
                            in: 0...50,
                            step: 5
                        )
                        .tint(.blue)
                    }
                } header: {
                    Text("Contingency")
                } footer: {
                    Text("An additional buffer added to the total for unexpected costs.")
                }

                Section {
                    VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                        HStack {
                            Text("Waste Factor")
                            Spacer()
                            TextField("0", text: $wasteText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                                .onChange(of: wasteText) { _, newValue in
                                    if let value = Decimal(string: newValue), value >= 0 {
                                        draft.wasteFactor = 1 + (value / 100)
                                    }
                                }
                            Text("%")
                                .foregroundStyle(.secondary)
                        }

                        Slider(
                            value: Binding(
                                get: { NSDecimalNumber(decimal: draft.wastePercentage).doubleValue },
                                set: {
                                    draft.wasteFactor = 1 + Decimal($0) / 100
                                    wasteText = String(format: "%.0f", $0)
                                }
                            ),
                            in: 0...30,
                            step: 5
                        )
                        .tint(.purple)
                    }
                } header: {
                    Text("Material Waste")
                } footer: {
                    Text("Multiplier applied to material quantities to account for waste and cuts (e.g., 10% = order 10% more material).")
                }

                Section {
                    Toggle("Set as Default", isOn: $draft.isDefault)
                        .tint(ColorTokens.primaryOrange)
                }
            }
            .navigationTitle(draft.isExisting ? "Edit Profile" : "New Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                    }
                    .fontWeight(.semibold)
                    .disabled(!draft.isValid)
                }
            }
            .onAppear {
                markupText = "\(NSDecimalNumber(decimal: draft.defaultMarkupPercent).intValue)"
                contingencyText = "\(NSDecimalNumber(decimal: draft.contingencyPercent).intValue)"
                wasteText = "\(NSDecimalNumber(decimal: draft.wastePercentage).intValue)"
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PricingProfilesView(viewModel: {
            let vm = SettingsViewModel()
            return vm
        }())
    }
}
