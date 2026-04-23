import Foundation

// MARK: - Protocol

protocol SettingsServiceProtocol: Sendable {
    func loadCompanySettings() async throws -> Company
    func saveCompanyBranding(_ settings: CompanyBrandingUpdate) async throws -> Company
    func saveTaxSettings(_ settings: TaxSettingsUpdate) async throws -> Company
    func saveNumberingSettings(_ settings: NumberingSettingsUpdate) async throws -> Company
    func uploadLogo(imageData: Data, mimeType: String) async throws -> Company
    func deleteLogo() async throws -> Company
    func loadPricingProfiles() async throws -> [PricingProfile]
    func savePricingProfile(_ profile: PricingProfile) async throws -> PricingProfile
    func deletePricingProfile(id: String) async throws
    func saveLanguagePreference(_ language: AppLanguage) async throws
}

// MARK: - Update DTOs

struct CompanyBrandingUpdate: Sendable {
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

struct TaxSettingsUpdate: Sendable {
    let defaultTaxRate: Decimal
    let taxInclusivePricing: Bool
}

struct NumberingSettingsUpdate: Sendable {
    let estimatePrefix: String
    let invoicePrefix: String
    let nextEstimateNumber: Int
    let nextInvoiceNumber: Int
}

// MARK: - Language

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case spanish = "es"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: "English"
        case .spanish: "Espa\u{00F1}ol"
        }
    }

    var nativeDisplayName: String {
        switch self {
        case .english: "English"
        case .spanish: "Espa\u{00F1}ol (Spanish)"
        }
    }
}

// MARK: - Mock Implementation

final class MockSettingsService: SettingsServiceProtocol {
    private let simulatedDelay: UInt64 = 500_000_000

    func loadCompanySettings() async throws -> Company {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return Company.sample
    }

    func saveCompanyBranding(_ settings: CompanyBrandingUpdate) async throws -> Company {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return Company(
            id: "c-001",
            name: settings.name,
            phone: settings.phone,
            email: settings.email,
            address: settings.address,
            city: settings.city,
            state: settings.state,
            zip: settings.zip,
            logoURL: nil,
            primaryColor: settings.primaryColor,
            secondaryColor: settings.secondaryColor,
            defaultTaxRate: 8.25,
            defaultMarkupPercent: 20,
            estimatePrefix: "EST",
            invoicePrefix: "INV",
            proposalPrefix: "PROP",
            nextEstimateNumber: 1001,
            nextInvoiceNumber: 2001,
            nextProposalNumber: 3001,
            defaultLanguage: "en",
            timezone: "America/New_York",
            websiteUrl: settings.websiteUrl,
            taxLabel: "Tax",
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func uploadLogo(imageData: Data, mimeType: String) async throws -> Company {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return Company.sample
    }

    func deleteLogo() async throws -> Company {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return Company.sample
    }

    func saveTaxSettings(_ settings: TaxSettingsUpdate) async throws -> Company {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return Company(
            id: "c-001",
            name: "Apex Remodeling Co.",
            phone: "512-555-0199",
            email: "info@apexremodeling.com",
            address: "1200 Main St",
            city: "Austin",
            state: "TX",
            zip: "78701",
            logoURL: nil,
            primaryColor: "#F97316",
            secondaryColor: "#1E293B",
            defaultTaxRate: settings.defaultTaxRate,
            defaultMarkupPercent: 20,
            estimatePrefix: "EST",
            invoicePrefix: "INV",
            proposalPrefix: "PROP",
            nextEstimateNumber: 1001,
            nextInvoiceNumber: 2001,
            nextProposalNumber: 3001,
            defaultLanguage: "en",
            timezone: "America/New_York",
            websiteUrl: nil,
            taxLabel: "Tax",
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func saveNumberingSettings(_ settings: NumberingSettingsUpdate) async throws -> Company {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return Company(
            id: "c-001",
            name: "Apex Remodeling Co.",
            phone: "512-555-0199",
            email: "info@apexremodeling.com",
            address: "1200 Main St",
            city: "Austin",
            state: "TX",
            zip: "78701",
            logoURL: nil,
            primaryColor: "#F97316",
            secondaryColor: "#1E293B",
            defaultTaxRate: 8.25,
            defaultMarkupPercent: 20,
            estimatePrefix: settings.estimatePrefix,
            invoicePrefix: settings.invoicePrefix,
            proposalPrefix: "PROP",
            nextEstimateNumber: settings.nextEstimateNumber,
            nextInvoiceNumber: settings.nextInvoiceNumber,
            nextProposalNumber: 3001,
            defaultLanguage: "en",
            timezone: "America/New_York",
            websiteUrl: nil,
            taxLabel: "Tax",
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func loadPricingProfiles() async throws -> [PricingProfile] {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return Self.sampleProfiles
    }

    func savePricingProfile(_ profile: PricingProfile) async throws -> PricingProfile {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return profile
    }

    func deletePricingProfile(id: String) async throws {
        try await Task.sleep(nanoseconds: simulatedDelay)
    }

    func saveLanguagePreference(_ language: AppLanguage) async throws {
        try await Task.sleep(nanoseconds: simulatedDelay)
    }
}

// MARK: - Errors

enum SettingsServiceError: LocalizedError {
    case loadFailed
    case saveFailed
    case deleteFailed

    var errorDescription: String? {
        switch self {
        case .loadFailed: "Failed to load settings."
        case .saveFailed: "Failed to save settings. Please try again."
        case .deleteFailed: "Failed to delete. Please try again."
        }
    }
}

// MARK: - Sample Data

extension MockSettingsService {
    static let sampleProfiles: [PricingProfile] = [
        PricingProfile(
            id: "pp-001",
            companyId: "c-001",
            name: "Standard",
            defaultMarkupPercent: 20,
            contingencyPercent: 10,
            wasteFactor: 1.10,
            isDefault: true,
            createdAt: Calendar.current.date(byAdding: .month, value: -6, to: Date())!
        ),
        PricingProfile(
            id: "pp-002",
            companyId: "c-001",
            name: "Premium",
            defaultMarkupPercent: 35,
            contingencyPercent: 15,
            wasteFactor: 1.15,
            isDefault: false,
            createdAt: Calendar.current.date(byAdding: .month, value: -3, to: Date())!
        ),
        PricingProfile(
            id: "pp-003",
            companyId: "c-001",
            name: "Economy",
            defaultMarkupPercent: 12,
            contingencyPercent: 5,
            wasteFactor: 1.05,
            isDefault: false,
            createdAt: Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        ),
    ]
}
