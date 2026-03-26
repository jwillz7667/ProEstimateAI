import Foundation

/// Production implementation of `SettingsServiceProtocol` that delegates
/// company settings operations to the backend REST API via `APIClient`
/// and persists local-only preferences in `UserDefaults`.
final class LiveSettingsService: SettingsServiceProtocol, Sendable {
    private let apiClient: APIClientProtocol

    /// UserDefaults key for the persisted language preference.
    private static let languagePreferenceKey = "proestimate_language_preference"

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

    func loadPricingProfiles() async throws -> [PricingProfile] {
        try await apiClient.request(.listPricingProfiles)
    }

    func savePricingProfile(_ profile: PricingProfile) async throws -> PricingProfile {
        // If the profile has a known ID that exists on the server, update it.
        // Otherwise, create a new one. We use a simple heuristic: profiles
        // fetched from the server always have a non-empty ID, while new
        // profiles created on the client use a UUID prefix.
        // For safety, we attempt an update first; if the profile is truly new,
        // the caller should ensure the ID is set to a sentinel or empty string.
        // However, since PricingProfile.id is always non-empty, we check if
        // the profile was previously fetched by trying an update and falling
        // back to create on failure.
        //
        // Simplified approach: the caller is responsible for providing
        // a profile with a valid server-side ID for updates, or a client-generated
        // ID for creates. We detect "new" profiles by checking for the "pp-new" prefix.
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

    func saveLanguagePreference(_ language: AppLanguage) async throws {
        // Language preference is stored locally — no backend round-trip needed.
        UserDefaults.standard.set(language.rawValue, forKey: Self.languagePreferenceKey)
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
