import SwiftUI

/// Step 0: Name the project and pick a category.
/// The name field is optional — if left blank we auto-generate a title
/// from the selected type and client. The 3-column grid below is the
/// required choice.
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
                titleSection

                Divider()
                    .padding(.vertical, SpacingTokens.xxs)

                Text("What type of project is this?")
                    .font(TypographyTokens.title3)

                Text("Select the category that best describes the work.")
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

    // MARK: - Title

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            HStack(spacing: SpacingTokens.xxs) {
                Image(systemName: "pencil.line")
                    .font(.caption)
                    .foregroundStyle(ColorTokens.primaryOrange)
                Text("Project Name")
                    .font(TypographyTokens.subheadline)
                    .fontWeight(.semibold)
                Text("Optional")
                    .font(TypographyTokens.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, SpacingTokens.xs)
                    .padding(.vertical, 1)
                    .background(ColorTokens.inputBackground, in: Capsule())
            }

            TextField(
                "e.g. Kitchen remodel for Anderson residence",
                text: $viewModel.customTitle,
                axis: .vertical
            )
            .lineLimit(1...2)
            .padding(SpacingTokens.sm)
            .background(
                ColorTokens.inputBackground,
                in: RoundedRectangle(cornerRadius: RadiusTokens.small)
            )
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .strokeBorder(ColorTokens.subtleBorder, lineWidth: 1)
            )
            .submitLabel(.done)

            Text("Leave blank and we'll auto-name this from the project type and the client.")
                .font(TypographyTokens.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    ProjectTypeSelectionStep(viewModel: ProjectCreationViewModel())
}
