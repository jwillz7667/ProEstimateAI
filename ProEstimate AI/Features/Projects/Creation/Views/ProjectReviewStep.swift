import SwiftUI

/// Step 5 (final): Review all selected options before creating the project.
/// Shows a summary of type, client, photo count, prompt preview, and details.
struct ProjectReviewStep: View {
    @Bindable var viewModel: ProjectCreationViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingTokens.md) {
                Text("Review & Create")
                    .font(TypographyTokens.title3)

                Text("Please confirm the details below before creating your project.")
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(.secondary)

                // Generated title
                GlassCard {
                    VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                        Text("Project Title")
                            .font(TypographyTokens.caption)
                            .foregroundStyle(.secondary)
                        Text(viewModel.generatedTitle)
                            .font(TypographyTokens.headline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Project type
                reviewRow(
                    icon: projectTypeIcon,
                    label: "Project Type",
                    value: projectTypeLabel
                )

                // Client
                reviewRow(
                    icon: "person",
                    label: "Client",
                    value: viewModel.selectedClient?.name ?? "Not assigned"
                )

                // Photos
                reviewRow(
                    icon: "photo.on.rectangle",
                    label: "Photos",
                    value: "\(viewModel.selectedImageData.count) photo\(viewModel.selectedImageData.count == 1 ? "" : "s")"
                )

                // Photo thumbnails
                if !viewModel.selectedImageData.isEmpty {
                    photoThumbnails
                }

                // Prompt
                if !viewModel.prompt.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                            HStack(spacing: SpacingTokens.xxs) {
                                Image(systemName: "text.quote")
                                    .font(.caption)
                                    .foregroundStyle(ColorTokens.primaryOrange)
                                Text("Description")
                                    .font(TypographyTokens.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(viewModel.prompt)
                                .font(TypographyTokens.body)
                                .lineLimit(4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Details
                detailsSummary

                // Auto-generate toggle
                autoGenerateToggle

                // Submission error with inline Retry
                if let error = viewModel.submissionError {
                    submissionErrorBanner(error)
                }
            }
            .padding(.horizontal, SpacingTokens.md)
            .padding(.vertical, SpacingTokens.sm)
        }
    }

    // MARK: - Auto-generate Toggle

    private var autoGenerateToggle: some View {
        GlassCard {
            HStack(spacing: SpacingTokens.sm) {
                Image(systemName: "wand.and.stars")
                    .font(.body)
                    .foregroundStyle(ColorTokens.primaryOrange)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text("Generate AI preview automatically")
                        .font(TypographyTokens.subheadline)
                    Text("Start rendering a before-and-after preview as soon as the project opens.")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Toggle("", isOn: $viewModel.autoGenerateEnabled)
                    .labelsHidden()
                    .tint(ColorTokens.primaryOrange)
            }
        }
    }

    // MARK: - Error Banner

    private func submissionErrorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            HStack(alignment: .top, spacing: SpacingTokens.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(ColorTokens.error)
                    .accessibilityHidden(true)
                Text(message)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.error)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task { await viewModel.createProject() }
            } label: {
                HStack(spacing: SpacingTokens.xxs) {
                    if viewModel.isSubmitting {
                        ProgressView().controlSize(.mini).tint(ColorTokens.error)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Try Again")
                }
                .font(TypographyTokens.caption.weight(.semibold))
                .foregroundStyle(ColorTokens.error)
            }
            .disabled(viewModel.isSubmitting)
        }
        .padding(SpacingTokens.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorTokens.error.opacity(0.1), in: RoundedRectangle(cornerRadius: RadiusTokens.small))
    }

    // MARK: - Subviews

    private func reviewRow(icon: String, label: String, value: String) -> some View {
        GlassCard {
            HStack(spacing: SpacingTokens.sm) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(ColorTokens.primaryOrange)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text(label)
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(TypographyTokens.body)
                }

                Spacer()
            }
        }
    }

    private var photoThumbnails: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SpacingTokens.xs) {
                ForEach(Array(viewModel.selectedImageData.prefix(5).enumerated()), id: \.offset) { _, data in
                    if let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.small))
                    }
                }

                if viewModel.selectedImageData.count > 5 {
                    Text("+\(viewModel.selectedImageData.count - 5)")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 64, height: 64)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: RadiusTokens.small))
                }
            }
            .padding(.horizontal, SpacingTokens.md)
        }
    }

    @ViewBuilder
    private var detailsSummary: some View {
        let hasDetails = viewModel.budgetMin != nil
            || viewModel.budgetMax != nil
            || viewModel.squareFootage != nil
            || !viewModel.dimensions.isEmpty

        if hasDetails {
            GlassCard {
                VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                    HStack(spacing: SpacingTokens.xxs) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.caption)
                            .foregroundStyle(ColorTokens.primaryOrange)
                        Text("Details")
                            .font(TypographyTokens.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let min = viewModel.budgetMin, let max = viewModel.budgetMax {
                        detailLine(label: "Budget", value: "$\(min) – $\(max)")
                    } else if let min = viewModel.budgetMin {
                        detailLine(label: "Budget", value: "From $\(min)")
                    } else if let max = viewModel.budgetMax {
                        detailLine(label: "Budget", value: "Up to $\(max)")
                    }

                    detailLine(label: "Quality", value: tierLabel(viewModel.qualityTier))

                    if let sqft = viewModel.squareFootage {
                        detailLine(label: "Area", value: "\(sqft) sq ft")
                    }

                    if !viewModel.dimensions.isEmpty {
                        detailLine(label: "Dimensions", value: viewModel.dimensions)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func detailLine(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(TypographyTokens.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(TypographyTokens.subheadline)
        }
    }

    // MARK: - Helpers

    private var projectTypeIcon: String {
        viewModel.selectedProjectType?.iconName ?? "questionmark.circle"
    }

    private var projectTypeLabel: String {
        viewModel.selectedProjectType?.displayName ?? "Not selected"
    }

    private func tierLabel(_ tier: Project.QualityTier) -> String {
        switch tier {
        case .standard: "Standard"
        case .premium: "Premium"
        case .luxury: "Luxury"
        }
    }
}

// MARK: - Preview

#Preview {
    ProjectReviewStep(viewModel: {
        let vm = ProjectCreationViewModel()
        vm.selectedProjectType = .kitchen
        vm.prompt = "Modern kitchen with white shaker cabinets and quartz countertops"
        return vm
    }())
}
