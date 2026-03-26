import Foundation
import Observation
import SwiftUI

@Observable
final class SettingsViewModel {
    // MARK: - Dependencies

    private let service: SettingsServiceProtocol

    // MARK: - State

    var company: Company?
    var pricingProfiles: [PricingProfile] = []
    var isLoading: Bool = false
    var isSaving: Bool = false
    var errorMessage: String?
    var successMessage: String?

    // MARK: - Company Branding Fields

    var companyName: String = ""
    var companyPhone: String = ""
    var companyEmail: String = ""
    var companyAddress: String = ""
    var companyCity: String = ""
    var companyState: String = ""
    var companyZip: String = ""
    var primaryColor: Color = ColorTokens.primaryOrange
    var secondaryColor: Color = Color(hex: 0x1E293B)

    // MARK: - Tax Settings Fields

    var defaultTaxRate: Decimal = 8.25
    var taxRateText: String = "8.25"
    var taxInclusivePricing: Bool = false

    // MARK: - Numbering Settings Fields

    var estimatePrefix: String = "EST"
    var invoicePrefix: String = "INV"
    var nextEstimateNumber: Int = 1001
    var nextInvoiceNumber: Int = 2001

    // MARK: - Language Settings

    var selectedLanguage: AppLanguage = .english

    // MARK: - Computed

    /// Preview of the next estimate number.
    var nextEstimateDisplay: String {
        "\(estimatePrefix)-\(nextEstimateNumber)"
    }

    /// Preview of the next invoice number.
    var nextInvoiceDisplay: String {
        "\(invoicePrefix)-\(nextInvoiceNumber)"
    }

    /// Hex string from the primary color for persistence.
    var primaryColorHex: String? {
        primaryColor.toHex()
    }

    /// Hex string from the secondary color for persistence.
    var secondaryColorHex: String? {
        secondaryColor.toHex()
    }

    // MARK: - Init

    init(service: SettingsServiceProtocol = MockSettingsService()) {
        self.service = service
    }

    // MARK: - Load

    func loadSettings() async {
        isLoading = true
        errorMessage = nil
        do {
            let loadedCompany = try await service.loadCompanySettings()
            company = loadedCompany
            populateFields(from: loadedCompany)

            pricingProfiles = try await service.loadPricingProfiles()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Save Actions

    func saveCompanyBranding() async {
        isSaving = true
        errorMessage = nil
        do {
            let update = CompanyBrandingUpdate(
                name: companyName,
                phone: companyPhone.isEmpty ? nil : companyPhone,
                email: companyEmail.isEmpty ? nil : companyEmail,
                address: companyAddress.isEmpty ? nil : companyAddress,
                city: companyCity.isEmpty ? nil : companyCity,
                state: companyState.isEmpty ? nil : companyState,
                zip: companyZip.isEmpty ? nil : companyZip,
                primaryColor: primaryColorHex,
                secondaryColor: secondaryColorHex
            )
            company = try await service.saveCompanyBranding(update)
            successMessage = "Branding saved successfully."
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    func saveTaxSettings() async {
        isSaving = true
        errorMessage = nil
        do {
            // Sync text field to decimal
            if let parsed = Decimal(string: taxRateText) {
                defaultTaxRate = parsed
            }
            let update = TaxSettingsUpdate(
                defaultTaxRate: defaultTaxRate,
                taxInclusivePricing: taxInclusivePricing
            )
            company = try await service.saveTaxSettings(update)
            successMessage = "Tax settings saved."
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    func saveNumbering() async {
        isSaving = true
        errorMessage = nil
        do {
            let update = NumberingSettingsUpdate(
                estimatePrefix: estimatePrefix,
                invoicePrefix: invoicePrefix,
                nextEstimateNumber: nextEstimateNumber,
                nextInvoiceNumber: nextInvoiceNumber
            )
            company = try await service.saveNumberingSettings(update)
            successMessage = "Numbering settings saved."
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    func saveLanguage() async {
        do {
            try await service.saveLanguagePreference(selectedLanguage)
            successMessage = "Language preference saved."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func savePricingProfile(_ profile: PricingProfile) async {
        isSaving = true
        errorMessage = nil
        do {
            let saved = try await service.savePricingProfile(profile)
            if let index = pricingProfiles.firstIndex(where: { $0.id == saved.id }) {
                pricingProfiles[index] = saved
            } else {
                pricingProfiles.append(saved)
            }
            successMessage = "Profile saved."
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    func deletePricingProfile(id: String) async {
        do {
            try await service.deletePricingProfile(id: id)
            pricingProfiles.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        // This will be handled by AppState; the view triggers it via environment.
    }

    // MARK: - Private

    private func populateFields(from company: Company) {
        companyName = company.name
        companyPhone = company.phone ?? ""
        companyEmail = company.email ?? ""
        companyAddress = company.address ?? ""
        companyCity = company.city ?? ""
        companyState = company.state ?? ""
        companyZip = company.zip ?? ""
        defaultTaxRate = company.defaultTaxRate ?? 8.25
        taxRateText = "\(NSDecimalNumber(decimal: company.defaultTaxRate ?? 8.25).doubleValue)"
        estimatePrefix = company.estimatePrefix ?? "EST"
        invoicePrefix = company.invoicePrefix ?? "INV"
        nextEstimateNumber = company.nextEstimateNumber
        nextInvoiceNumber = company.nextInvoiceNumber

        if let hex = company.primaryColor {
            primaryColor = Color(hex: UInt(hex.dropFirst(), radix: 16) ?? 0xF97316)
        }
        if let hex = company.secondaryColor {
            secondaryColor = Color(hex: UInt(hex.dropFirst(), radix: 16) ?? 0x1E293B)
        }
    }
}

// MARK: - Color to Hex

private extension Color {
    func toHex() -> String? {
        guard let components = UIColor(self).cgColor.components else { return nil }
        let r = components.count > 0 ? components[0] : 0
        let g = components.count > 1 ? components[1] : 0
        let b = components.count > 2 ? components[2] : 0
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
