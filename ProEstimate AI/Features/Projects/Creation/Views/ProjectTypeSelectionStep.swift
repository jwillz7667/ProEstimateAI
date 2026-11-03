import SwiftUI

/// Establish the project in one place: category and an optional name.
/// Search and adaptive tiles keep the full trade catalog usable on small
/// displays and at larger text sizes.
struct ProjectTypeSelectionStep: View {
    @Bindable var viewModel: ProjectCreationViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var searchQuery = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case name, search }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 280 : 148), spacing: 24)]
    }

    private var matchingTypes: [Project.ProjectType] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? Project.ProjectType.allCases : Project.ProjectType.allCases.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingTokens.md) {
                header
                nameSection
                categorySearch

                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(matchingTypes, id: \.self) { type in
                        ProjectTypeCard(
                            projectType: type,
                            isSelected: viewModel.selectedProjectType == type
                        ) {
                            viewModel.selectedProjectType = type
                            focusedField = nil
                        }
                    }
                }
                .padding(.top, SpacingTokens.xs)
                if matchingTypes.isEmpty {
                    ContentUnavailableView.search(text: searchQuery)
                }
            }
            .frame(maxWidth: 960)
            .padding(.horizontal, SpacingTokens.md)
            .padding(.vertical, SpacingTokens.sm)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if focusedField != nil {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
            Text("Start with the work.")
                .font(TypographyTokens.title2)

            Text("Choose a project type. Add photos and notes next, then create an estimate from your project.")
                .font(TypographyTokens.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, SpacingTokens.xs)
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            Text("Project name (optional)")
                .font(TypographyTokens.headline)
            TextField(viewModel.generatedTitle, text: $viewModel.customTitle, axis: .vertical)
                .focused($focusedField, equals: .name)
                .submitLabel(.done)
                .onSubmit { focusedField = nil }
                .lineLimit(1 ... 2)
                .padding(SpacingTokens.sm)
                .background(ColorTokens.inputBackground, in: RoundedRectangle(cornerRadius: RadiusTokens.small))
                .overlay(RoundedRectangle(cornerRadius: RadiusTokens.small).strokeBorder(ColorTokens.subtleBorder, lineWidth: 1))
                .accessibilityLabel("Project name, optional")
            if let message = viewModel.projectNameValidationMessage {
                Text(message)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.error)
            } else {
                Text("Leave this blank to use the project type as its name.")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var categorySearch: some View {
        HStack(spacing: SpacingTokens.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search project types", text: $searchQuery)
                .focused($focusedField, equals: .search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { focusedField = nil }
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Clear project type search")
            }
        }
        .padding(SpacingTokens.sm)
        .background(ColorTokens.inputBackground, in: RoundedRectangle(cornerRadius: RadiusTokens.small))
    }
}

// MARK: - Preview

#Preview {
    ProjectTypeSelectionStep(viewModel: ProjectCreationViewModel())
}
