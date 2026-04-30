import SwiftUI

/// Step 0 of the simplified creation flow. Single decision: pick the
/// project category. The project name moved to the details step so this
/// page stays scannable and decisive.
///
/// The grid renders 13 photographic tiles in a 3-column layout — every
/// `Project.ProjectType` case. The trailing single tile on the final row
/// is acceptable inside this `ScrollView`; the grid scrolls anyway, so a
/// short last row reads as natural pagination instead of a layout bug.
/// Tile design and selection cues live in `ProjectTypeCard`.
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
                header

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

    private var header: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
            Text("What type of project is this?")
                .font(TypographyTokens.title2)

            Text("Pick the category that best describes the work. We'll tailor the next step's design suggestions to your choice.")
                .font(TypographyTokens.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, SpacingTokens.xs)
    }
}

// MARK: - Preview

#Preview {
    ProjectTypeSelectionStep(viewModel: ProjectCreationViewModel())
}
