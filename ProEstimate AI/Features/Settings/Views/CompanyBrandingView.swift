import PhotosUI
import SwiftUI

struct CompanyBrandingView: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var selectedLogoItem: PhotosPickerItem?
    @Environment(FeatureGateCoordinator.self) private var featureGateCoordinator
    @Environment(PaywallPresenter.self) private var paywallPresenter

    var body: some View {
        Form {
            // Logo Section
            Section("Logo") {
                VStack(spacing: SpacingTokens.md) {
                    logoDisplay
                        .frame(height: 80)
                        .frame(maxWidth: .infinity)

                    HStack(spacing: SpacingTokens.sm) {
                        PhotosPicker(
                            selection: $selectedLogoItem,
                            matching: .images
                        ) {
                            Label(
                                viewModel.companyLogoURL == nil ? "Choose Logo" : "Replace Logo",
                                systemImage: "photo.on.rectangle"
                            )
                            .font(TypographyTokens.subheadline)
                            .foregroundStyle(ColorTokens.primaryOrange)
                        }
                        .disabled(viewModel.isUploadingLogo)

                        if viewModel.companyLogoURL != nil {
                            Spacer()
                            Button(role: .destructive) {
                                Task { await viewModel.removeCompanyLogo() }
                            } label: {
                                Label("Remove", systemImage: "trash")
                                    .font(TypographyTokens.subheadline)
                            }
                            .disabled(viewModel.isUploadingLogo)
                        }

                        if viewModel.isUploadingLogo {
                            Spacer()
                            ProgressView().controlSize(.small)
                        }
                    }
                    .onChange(of: selectedLogoItem) { _, newItem in
                        guard let newItem else { return }
                        Task { await handleLogoSelection(newItem) }
                    }

                    Text("PNG, JPEG, or WebP up to 2 MB. Appears on every estimate, proposal, and invoice PDF.")
                        .font(TypographyTokens.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, SpacingTokens.xs)
            }

            // Company Info Section
            Section("Company Information") {
                TextField("Company Name", text: $viewModel.companyName)
                    .onChange(of: viewModel.companyName) { _, _ in viewModel.scheduleSaveBranding() }
                TextField("Phone", text: $viewModel.companyPhone)
                    .keyboardType(.phonePad)
                    .onChange(of: viewModel.companyPhone) { _, _ in viewModel.scheduleSaveBranding() }
                TextField("Email", text: $viewModel.companyEmail)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .onChange(of: viewModel.companyEmail) { _, _ in viewModel.scheduleSaveBranding() }
                TextField("Website", text: $viewModel.companyWebsite)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .autocapitalization(.none)
                    .onChange(of: viewModel.companyWebsite) { _, _ in viewModel.scheduleSaveBranding() }
            }

            // Address Section
            Section("Address") {
                TextField("Street Address", text: $viewModel.companyAddress)
                    .textContentType(.streetAddressLine1)
                    .onChange(of: viewModel.companyAddress) { _, _ in viewModel.scheduleSaveBranding() }
                TextField("City", text: $viewModel.companyCity)
                    .textContentType(.addressCity)
                    .onChange(of: viewModel.companyCity) { _, _ in viewModel.scheduleSaveBranding() }
                TextField("State", text: $viewModel.companyState)
                    .textContentType(.addressState)
                    .onChange(of: viewModel.companyState) { _, _ in viewModel.scheduleSaveBranding() }
                TextField("ZIP Code", text: $viewModel.companyZip)
                    .textContentType(.postalCode)
                    .keyboardType(.numberPad)
                    .onChange(of: viewModel.companyZip) { _, _ in viewModel.scheduleSaveBranding() }
            }

            // Brand Colors Section
            Section("Brand Colors") {
                ColorPicker("Primary Color", selection: $viewModel.primaryColor)
                    .onChange(of: viewModel.primaryColor) { _, _ in viewModel.scheduleSaveBranding() }
                ColorPicker("Secondary Color", selection: $viewModel.secondaryColor)
                    .onChange(of: viewModel.secondaryColor) { _, _ in viewModel.scheduleSaveBranding() }
            }

            // Live Preview Section
            Section("Preview") {
                brandingPreview
            }
        }
        .navigationTitle("Branding")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SettingsSaveStatusView(status: viewModel.saveStatus)
            }
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Logo Display

    /// Renders (in order): the locally picked image that hasn't finished
    /// uploading yet, the persisted backend URL, then the app-icon fallback.
    @ViewBuilder
    private var logoDisplay: some View {
        if let uiImage = viewModel.companyLogoImage {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.small))
        } else if let url = viewModel.companyLogoURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.small))
                case .failure:
                    fallbackLogo
                case .empty:
                    ProgressView()
                @unknown default:
                    fallbackLogo
                }
            }
        } else {
            fallbackLogo
        }
    }

    private var fallbackLogo: some View {
        Image("housd-icon-light")
            .resizable()
            .aspectRatio(contentMode: .fit)
    }

    // MARK: - Logo Selection

    /// Loads the picked photo as Data, validates size + MIME, then hands it
    /// to the view model's upload path. Any failure surfaces through the
    /// view model's `errorMessage`.
    private func handleLogoSelection(_ item: PhotosPickerItem) async {
        let gate = featureGateCoordinator.guardUseBranding()
        if case let .blocked(decision) = gate {
            paywallPresenter.present(decision)
            selectedLogoItem = nil
            return
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                viewModel.errorMessage = "Couldn't read the selected image."
                return
            }
            // 2 MB hard cap — matches the backend validator.
            guard data.count <= 2 * 1024 * 1024 else {
                viewModel.errorMessage = "Logo must be 2 MB or smaller. Please pick a smaller image."
                return
            }
            let mimeType = mimeType(for: data) ?? "image/jpeg"
            await viewModel.uploadCompanyLogo(data: data, mimeType: mimeType)
        } catch {
            viewModel.errorMessage = "Couldn't load the selected image: \(error.localizedDescription)"
        }

        selectedLogoItem = nil
    }

    /// Sniff image bytes for a supported MIME type. Keeps us out of the
    /// business of trusting `UTType` metadata from arbitrary picker sources
    /// and ensures the value we send to the server matches the allowlist.
    private func mimeType(for data: Data) -> String? {
        guard data.count >= 4 else { return nil }
        let bytes = [UInt8](data.prefix(12))
        // PNG: 89 50 4E 47
        if bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47 {
            return "image/png"
        }
        // JPEG: FF D8 FF
        if bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
            return "image/jpeg"
        }
        // WEBP: 52 49 46 46 .. .. .. .. 57 45 42 50
        if bytes.count >= 12,
           bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46,
           bytes[8] == 0x57, bytes[9] == 0x45, bytes[10] == 0x42, bytes[11] == 0x50
        {
            return "image/webp"
        }
        return nil
    }

    // MARK: - Preview Card

    private var brandingPreview: some View {
        VStack(spacing: SpacingTokens.sm) {
            // Simulated document header
            VStack(spacing: SpacingTokens.xs) {
                logoDisplay
                    .frame(height: 40)

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
        .glassCard()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CompanyBrandingView(viewModel: SettingsViewModel())
    }
}
