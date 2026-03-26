import SwiftUI
import PhotosUI

struct CompanyBrandingView: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var selectedLogoItem: PhotosPickerItem?
    @State private var logoImage: Image?
    @Environment(FeatureGateCoordinator.self) private var featureGateCoordinator
    @Environment(PaywallPresenter.self) private var paywallPresenter

    var body: some View {
        Form {
            // Logo Section
            Section("Logo") {
                VStack(spacing: SpacingTokens.md) {
                    // Current logo display
                    if let logoImage {
                        logoImage
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.small))
                    } else {
                        Image(systemName: "building.2")
                            .font(.system(size: 48))
                            .foregroundStyle(ColorTokens.primaryOrange.opacity(0.3))
                            .frame(height: 80)
                    }

                    PhotosPicker(
                        selection: $selectedLogoItem,
                        matching: .images
                    ) {
                        Label("Choose Logo", systemImage: "photo.on.rectangle")
                            .font(TypographyTokens.subheadline)
                            .foregroundStyle(ColorTokens.primaryOrange)
                    }
                    .onChange(of: selectedLogoItem) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self),
                               let uiImage = UIImage(data: data) {
                                logoImage = Image(uiImage: uiImage)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, SpacingTokens.xs)
            }

            // Company Info Section
            Section("Company Information") {
                TextField("Company Name", text: $viewModel.companyName)
                TextField("Phone", text: $viewModel.companyPhone)
                    .keyboardType(.phonePad)
                TextField("Email", text: $viewModel.companyEmail)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
            }

            // Address Section
            Section("Address") {
                TextField("Street Address", text: $viewModel.companyAddress)
                    .textContentType(.streetAddressLine1)
                TextField("City", text: $viewModel.companyCity)
                    .textContentType(.addressCity)
                TextField("State", text: $viewModel.companyState)
                    .textContentType(.addressState)
                TextField("ZIP Code", text: $viewModel.companyZip)
                    .textContentType(.postalCode)
                    .keyboardType(.numberPad)
            }

            // Brand Colors Section
            Section("Brand Colors") {
                ColorPicker("Primary Color", selection: $viewModel.primaryColor)
                ColorPicker("Secondary Color", selection: $viewModel.secondaryColor)
            }

            // Live Preview Section
            Section("Preview") {
                brandingPreview
            }

            // Save Button
            Section {
                PrimaryCTAButton(
                    title: "Save Branding",
                    icon: "checkmark.circle",
                    isLoading: viewModel.isSaving
                ) {
                    let result = featureGateCoordinator.guardUseBranding()
                    switch result {
                    case .allowed:
                        Task { await viewModel.saveCompanyBranding() }
                    case .blocked(let decision):
                        paywallPresenter.present(decision)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Branding")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Preview Card

    private var brandingPreview: some View {
        VStack(spacing: SpacingTokens.sm) {
            // Simulated document header
            VStack(spacing: SpacingTokens.xs) {
                if let logoImage {
                    logoImage
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 32)
                } else {
                    Image(systemName: "building.2")
                        .font(.system(size: 24))
                        .foregroundStyle(viewModel.primaryColor)
                }

                Text(viewModel.companyName.isEmpty ? "Your Company" : viewModel.companyName)
                    .font(TypographyTokens.headline)

                if !viewModel.companyPhone.isEmpty || !viewModel.companyEmail.isEmpty {
                    HStack(spacing: SpacingTokens.sm) {
                        if !viewModel.companyPhone.isEmpty {
                            Text(viewModel.companyPhone)
                                .font(TypographyTokens.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if !viewModel.companyEmail.isEmpty {
                            Text(viewModel.companyEmail)
                                .font(TypographyTokens.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Divider()

            // Sample accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(viewModel.primaryColor)
                .frame(height: 4)

            HStack {
                Text("EST-1001")
                    .font(TypographyTokens.caption)
                    .fontWeight(.bold)
                Spacer()
                Text("$22,732.50")
                    .font(TypographyTokens.moneySmall)
                    .foregroundStyle(viewModel.primaryColor)
            }

            RoundedRectangle(cornerRadius: 2)
                .fill(viewModel.secondaryColor)
                .frame(height: 2)
        }
        .padding(SpacingTokens.md)
        .background(Color.gray.opacity(0.05), in: RoundedRectangle(cornerRadius: RadiusTokens.card))
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CompanyBrandingView(viewModel: SettingsViewModel())
    }
}
