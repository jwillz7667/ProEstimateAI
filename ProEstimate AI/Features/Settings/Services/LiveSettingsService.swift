import Foundation

/// Production implementation of `SettingsServiceProtocol` that delegates
/// company settings operations to the backend REST API via `APIClient` and
/// mirrors a small set of preferences (language) into UserDefaults so that
/// the very first frame after launch — before bootstrap finishes — can pick
/// up the last-known value.
final class LiveSettingsService: SettingsServiceProtocol, Sendable {
    private let apiClient: APIClientProtocol

    /// UserDefaults key for the persisted language preference. Mirrored from
    /// the backend on every save and on `populateFields` so an offline app
    /// launch still renders the user's chosen language.
    static let languagePreferenceKey = "proestimate_language_preference"

    init(apiClient: APIClientProtocol = APIClient.shared) {
        self.apiClient = apiClient
    }

    // MARK: - SettingsServiceProtocol

    func loadCompanySettings() async throws -> Company {
        try await apiClient.request(.getCompany)
    }

    func saveCompanyBranding(_ settings: CompanyBrandingUpdate) async throws -> Company {
        let body = CompanyBrandingBody(
            name: settings.name,
            phone: settings.phone,
            email: settings.email,
            address: settings.address,
            city: settings.city,
            state: settings.state,
            zip: settings.zip,
            websiteUrl: settings.websiteUrl,
            primaryColor: settings.primaryColor,
            secondaryColor: settings.secondaryColor
        )
        return try await apiClient.request(.updateCompany(body: body))
    }

    func saveTaxSettings(_ settings: TaxSettingsUpdate) async throws -> Company {
        let body = TaxSettingsBody(
            defaultTaxRate: settings.defaultTaxRate,
            taxInclusivePricing: settings.taxInclusivePricing
        )
        return try await apiClient.request(.updateCompany(body: body))
    }

    func saveNumberingSettings(_ settings: NumberingSettingsUpdate) async throws -> Company {
        let body = NumberingSettingsBody(
            estimatePrefix: settings.estimatePrefix,
            invoicePrefix: settings.invoicePrefix,
            nextEstimateNumber: settings.nextEstimateNumber,
            nextInvoiceNumber: settings.nextInvoiceNumber
        )
        return try await apiClient.request(.updateCompany(body: body))
    }

    func uploadLogo(imageData: Data, mimeType: String) async throws -> Company {
        let body = CompanyLogoUploadBody(
            imageData: imageData.base64EncodedString(),
            mimeType: mimeType
        )
        return try await apiClient.request(.uploadCompanyLogo(body: body))
    }

    func deleteLogo() async throws -> Company {
        try await apiClient.request(.deleteCompanyLogo)
    }

    func loadPricingProfiles() async throws -> [PricingProfile] {
        try await apiClient.request(.listPricingProfiles)
    }

    func savePricingProfile(_ profile: PricingProfile) async throws -> PricingProfile {
        // We use a sentinel id prefix for client-created profiles so the
        // service can route them to POST. Server-issued ids never start with
        // "pp-new", so the discriminator is unambiguous.
        if profile.id.hasPrefix("pp-new") || profile.id.isEmpty {
            return try await apiClient.request(.createPricingProfile(body: profile))
        } else {
            return try await apiClient.request(
                .updatePricingProfile(id: profile.id, body: profile)
            )
        }
    }

    func deletePricingProfile(id: String) async throws {
        try await apiClient.request(.deletePricingProfile(id: id)) as Void
    }

    func saveLanguagePreference(_ language: AppLanguage) async throws -> Company {
        // Mirror to UserDefaults first so the app can render in the chosen
        // language before the network round-trip completes (and so an
        // offline launch gets the right strings). The backend round-trip is
        // the source of truth for cross-device sync.
        UserDefaults.standard.set(language.rawValue, forKey: Self.languagePreferenceKey)
        let body = LanguageBody(defaultLanguage: language.rawValue)
        return try await apiClient.request(.updateCompany(body: body))
    }

    func saveAppearanceMode(_ mode: AppearanceMode) async throws -> Company {
        let body = AppearanceBody(appearanceMode: mode.persistenceValue)
        return try await apiClient.request(.updateCompany(body: body))
    }
}

// MARK: - Request Bodies

// The APIClient encoder uses `.convertToSnakeCase`, so camelCase property names
// are automatically converted to snake_case in the JSON payload.

/// Partial company update body for branding fields.
private struct CompanyBrandingBody: Encodable, Sendable {
    let name: String
    let phone: String?
    let email: String?
    let address: String?
    let city: String?
    let state: String?
    let zip: String?
    let websiteUrl: String?
    let primaryColor: String?
    let secondaryColor: String?
}

/// Partial company update body for tax settings.
private struct TaxSettingsBody: Encodable, Sendable {
    let defaultTaxRate: Decimal
    let taxInclusivePricing: Bool
}

/// Partial company update body for document numbering settings.
private struct NumberingSettingsBody: Encodable, Sendable {
    let estimatePrefix: String
    let invoicePrefix: String
    let nextEstimateNumber: Int
    let nextInvoiceNumber: Int
}

/// Partial company update body for the document language preference.
private struct LanguageBody: Encodable, Sendable {
    let defaultLanguage: String
}

/// Partial company update body for the appearance preference.
private struct AppearanceBody: Encodable, Sendable {
    let appearanceMode: String
}

/// Logo upload body — base64-encoded payload + explicit MIME so the server
/// can validate the image type without sniffing bytes.
private struct CompanyLogoUploadBody: Encodable, Sendable {
    let imageData: String
    let mimeType: String
}
