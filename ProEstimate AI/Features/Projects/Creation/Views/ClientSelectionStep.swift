import SwiftUI

/// Step 1: Select an existing client or skip.
/// Shows a searchable list of clients with the selected client highlighted.
struct ClientSelectionStep: View {
    @Bindable var viewModel: ProjectCreationViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingTokens.md) {
                Text("Assign a Client")
                    .font(TypographyTokens.title3)

                Text("Link this project to an existing client, or skip for now.")
                    .font(TypographyTokens.subheadline)
                    .foregroundStyle(.secondary)

                // Search bar
                SearchBar(text: $viewModel.clientSearchText, placeholder: "Search clients")
                    .padding(.top, SpacingTokens.xxs)

                // Skip option
                skipButton

                // Client list
                LazyVStack(spacing: SpacingTokens.xs) {
                    ForEach(viewModel.filteredClients) { client in
                        clientRow(client)
                    }
                }

                if viewModel.filteredClients.isEmpty && !viewModel.clientSearchText.isEmpty {
                    noResultsView
                }
            }
            .padding(.horizontal, SpacingTokens.md)
            .padding(.vertical, SpacingTokens.sm)
        }
    }

    // MARK: - Subviews

    private var skipButton: some View {
        Button {
            viewModel.selectedClient = nil
        } label: {
            HStack(spacing: SpacingTokens.sm) {
                Image(systemName: "person.slash")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(ColorTokens.inputBackground, in: Circle())

                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text("No Client")
                        .font(TypographyTokens.headline)
                    Text("Assign a client later")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if viewModel.selectedClient == nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(ColorTokens.primaryOrange)
                }
            }
            .padding(SpacingTokens.sm)
            .glassCard(cornerRadius: RadiusTokens.card)
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.card)
                    .strokeBorder(
                        viewModel.selectedClient == nil ? ColorTokens.primaryOrange : .clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func clientRow(_ client: Client) -> some View {
        let isSelected = viewModel.selectedClient?.id == client.id

        return Button {
            viewModel.selectedClient = client
        } label: {
            HStack(spacing: SpacingTokens.sm) {
                AvatarView(name: client.name, size: 40)

                VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                    Text(client.name)
                        .font(TypographyTokens.headline)

                    if let address = client.formattedAddress {
                        Text(address)
                            .font(TypographyTokens.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(ColorTokens.primaryOrange)
                }
            }
            .padding(SpacingTokens.sm)
            .glassCard(cornerRadius: RadiusTokens.card)
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.card)
                    .strokeBorder(
                        isSelected ? ColorTokens.primaryOrange : .clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var noResultsView: some View {
        VStack(spacing: SpacingTokens.sm) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("No clients match \"\(viewModel.clientSearchText)\"")
                .font(TypographyTokens.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SpacingTokens.xl)
    }
}

// MARK: - Preview

#Preview {
    ClientSelectionStep(viewModel: ProjectCreationViewModel())
}
