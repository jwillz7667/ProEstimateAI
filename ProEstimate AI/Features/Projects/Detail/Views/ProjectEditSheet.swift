import SwiftUI

/// Edit any aspect of a project without re-running the creation wizard.
/// Covers title, description, type, quality tier, budget range, square
/// footage, and dimensions. Saves via `ProjectServiceProtocol.updateProject`
/// and calls the completion with the refreshed record.
struct ProjectEditSheet: View {
    let project: Project
    let onSaved: (Project) -> Void

    @State private var title: String
    @State private var description: String
    @State private var projectType: Project.ProjectType
    /// `nil` = Auto (backend picks tier-neutral defaults). When set, the
    /// backend enforces tier price floors/ceilings on materials and labor.
    @State private var qualityTier: Project.QualityTier?
    @State private var budgetMinText: String
    @State private var budgetMaxText: String
    @State private var squareFootageText: String
    @State private var dimensions: String
    /// Whether the project generates an AI design preview. Service trades
    /// seed this off at creation; the contractor can flip it here for any
    /// project (e.g. turn a fencing job's before/after preview back on).
    @State private var aiPreviewEnabled: Bool

    @State private var isSaving: Bool = false
    @State private var errorMessage: String?

    @Environment(\.dismiss) private var dismiss
    private let projectService: ProjectServiceProtocol

    init(
        project: Project,
        onSaved: @escaping (Project) -> Void,
        projectService: ProjectServiceProtocol = LiveProjectService()
    ) {
        self.project = project
        self.onSaved = onSaved
        self.projectService = projectService

        _title = State(initialValue: project.title)
        _description = State(initialValue: project.description ?? "")
        _projectType = State(initialValue: project.projectType)
        _qualityTier = State(initialValue: project.qualityTier)
        _budgetMinText = State(initialValue: project.budgetMin.map { "\($0)" } ?? "")
        _budgetMaxText = State(initialValue: project.budgetMax.map { "\($0)" } ?? "")
        _squareFootageText = State(initialValue: project.squareFootage.map { "\($0)" } ?? "")
        _dimensions = State(initialValue: project.dimensions ?? "")
        _aiPreviewEnabled = State(initialValue: project.aiPreviewEnabled)
    }

    // MARK: - Computed

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                titleSection
                descriptionSection
                typeSection
                qualitySection
                aiPreviewSection
                budgetSection
                squareFootageSection
                dimensionsSection

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(TypographyTokens.caption)
                            .foregroundStyle(ColorTokens.error)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ColorTokens.background)
            .navigationTitle("Edit Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Save") {
                            Task { await save() }
                        }
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var titleSection: some View {
        Section {
            TextField("Project Name", text: $title, axis: .vertical)
                .lineLimit(1 ... 2)
        } header: {
            Text("Name")
        }
    }

    private var descriptionSection: some View {
        Section {
            TextField("What's the scope of work?", text: $description, axis: .vertical)
                .lineLimit(3 ... 8)
        } header: {
            Text("Description")
        }
    }

    private var typeSection: some View {
        Section {
            Picker("Type", selection: $projectType) {
                ForEach(Project.ProjectType.allCases, id: \.self) { type in
                    Text(typeLabel(type)).tag(type)
                }
            }
        } header: {
            Text("Project Type")
        }
    }

    private var qualitySection: some View {
        Section {
            Picker("Quality", selection: $qualityTier) {
                Text("Auto").tag(Project.QualityTier?.none)
                ForEach(Project.QualityTier.allCases, id: \.self) { tier in
                    Text(tier.displayName).tag(Project.QualityTier?.some(tier))
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text("Quality Tier")
        } footer: {
            Text("Auto lets us pick tier-neutral defaults from the project type. Selecting a tier enforces price floors/ceilings on materials and labor.")
                .font(TypographyTokens.caption)
        }
    }

    private var aiPreviewSection: some View {
        Section {
            Toggle("Generate AI design preview", isOn: $aiPreviewEnabled)
                .tint(ColorTokens.primaryOrange)
        } header: {
            Text("AI Preview")
        } footer: {
            Text("On generates a before/after design image alongside the estimate. Turn off for service calls (plumbing, cleaning, repairs) where there's nothing to redesign — you'll still get an itemized materials and labor estimate.")
                .font(TypographyTokens.caption)
        }
    }

    private var budgetSection: some View {
        Section {
            HStack(spacing: SpacingTokens.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Minimum").font(TypographyTokens.caption).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text("$").foregroundStyle(.secondary)
                        TextField("0", text: $budgetMinText).keyboardType(.decimalPad)
                    }
                }
                Text("–").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Maximum").font(TypographyTokens.caption).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text("$").foregroundStyle(.secondary)
                        TextField("0", text: $budgetMaxText).keyboardType(.decimalPad)
                    }
                }
            }
        } header: {
            Text("Budget Range")
        }
    }

    private var squareFootageSection: some View {
        Section {
            TextField("e.g. 250", text: $squareFootageText)
                .keyboardType(.decimalPad)
        } header: {
            Text("Square Footage")
        }
    }

    private var dimensionsSection: some View {
        Section {
            TextField("e.g. 20x12.5", text: $dimensions)
        } header: {
            Text("Dimensions")
        } footer: {
            Text("Length × Width, in feet.")
                .font(TypographyTokens.caption)
        }
    }

    // MARK: - Save

    private func save() async {
        guard isValid else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let request = ProjectCreationRequest(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            projectType: projectType,
            clientId: project.clientId,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : description.trimmingCharacters(in: .whitespacesAndNewlines),
            budgetMin: Decimal(string: budgetMinText),
            budgetMax: Decimal(string: budgetMaxText),
            qualityTier: qualityTier,
            squareFootage: Decimal(string: squareFootageText),
            dimensions: dimensions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : dimensions.trimmingCharacters(in: .whitespacesAndNewlines),
            language: project.language,
            aiPreviewEnabled: aiPreviewEnabled,
            // Project edit sheet doesn't expose recurrence today; preserve
            // whatever the project already has by passing the existing
            // values through unchanged.
            isRecurring: project.isRecurring,
            recurrenceFrequency: project.recurrenceFrequency?.rawValue,
            visitsPerMonth: project.visitsPerMonth,
            contractMonths: project.contractMonths,
            recurrenceStartDate: project.recurrenceStartDate
        )

        do {
            let updated = try await projectService.updateProject(id: project.id, request: request)
            onSaved(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func typeLabel(_ type: Project.ProjectType) -> String {
        type.displayName
    }
}
