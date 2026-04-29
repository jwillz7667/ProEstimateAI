import SwiftUI

/// Step 0 of the simplified creation flow. Single decision: pick the
/// project category. The project name moved to the details step so this
/// page stays scannable and decisive.
struct ProjectTypeSelectionStep: View {
    @Bindable var viewModel: ProjectCreationViewModel

    private let columns = [
        GridItem(.flexible(), spacing: SpacingTokens.sm),
        GridItem(.flexible(), spacing: SpacingTokens.sm),
        GridItem(.flexible(), spacing: SpacingTokens.sm),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingTokens.md) {
                Text("What type of project is this?")
                    .font(TypographyTokens.title2)
                    .padding(.top, SpacingTokens.xs)

                Text("Pick the category that best describes the work. We'll tailor the next step's design suggestions to your choice.")
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: columns, spacing: SpacingTokens.sm) {
                    ForEach(Project.ProjectType.allCases, id: \.self) { type in
                        ProjectTypeCard(
                            projectType: type,
                            isSelected: viewModel.selectedProjectType == type
                        ) {
                            viewModel.selectedProjectType = type
                        }
                    }
                }
                .padding(.top, SpacingTokens.xs)
            }
            .padding(.horizontal, SpacingTokens.md)
            .padding(.vertical, SpacingTokens.sm)
        }
    }
}

// MARK: - Preview

#Preview {
    ProjectTypeSelectionStep(viewModel: ProjectCreationViewModel())
}
