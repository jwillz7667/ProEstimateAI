import Foundation
import Observation
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// State of the autosave pipeline. Surfaced to the UI so the user gets
/// continuous feedback that their edits are being persisted server-side.
enum SettingsSaveStatus: Equatable {
    case idle
    case pending
    case saving
    case saved(at: Date)
    case failed(message: String)
}

@Observable
@MainActor
final class SettingsViewModel {
    // MARK: - Dependencies

    private let service: SettingsServiceProtocol
    weak var appState: AppState?
    weak var appearanceStore: AppearanceStore?

    // MARK: - State

    var company: Company?
    var pricingProfiles: [PricingProfile] = []
    var isLoading: Bool = false
    var isUploadingLogo: Bool = false
    var errorMessage: String?
    var saveStatus: SettingsSaveStatus = .idle

    // MARK: - Company Branding Fields

    var companyName: String = ""
    var companyPhone: String = ""
    var companyEmail: String = ""
    var companyAddress: String = ""
    var companyCity: String = ""
    var companyState: String = ""
    var companyZip: String = ""
    var companyWebsite: String = ""
    var primaryColor: Color = ColorTokens.primaryOrange
    var secondaryColor: Color = .init(hex: 0x1E293B)

    /// Locally selected logo (set immediately on PhotosPicker pick so the UI
    /// reflects the new image before the upload round-trip completes). Nil
    /// once the uploaded URL is the source of truth.
    var companyLogoImage: UIImage?
    /// The persisted logo URL from the backend — used by `AsyncImage` to
    /// render the saved logo when `companyLogoImage` is nil.
    var companyLogoURL: URL?

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

    /// True when enough branding is saved to produce a polished PDF —
    /// driver for the incomplete-branding banner in the estimate editor.
    var isBrandingComplete: Bool {
        guard !companyName.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        let hasContact = !companyPhone.trimmingCharacters(in: .whitespaces).isEmpty
            || !companyEmail.trimmingCharacters(in: .whitespaces).isEmpty
        let hasAddress = !companyCity.trimmingCharacters(in: .whitespaces).isEmpty
            && !companyState.trimmingCharacters(in: .whitespaces).isEmpty
        let hasLogo = companyLogoURL != nil
        return hasContact && hasAddress && hasLogo
    }

    // MARK: - Internal Save Pipeline

    /// While `true`, scheduled saves are suppressed. We flip this on while
    /// `populateFields(from:)` overwrites every published field — without it,
    /// each assignment would queue a no-op autosave and we'd round-trip the
    /// server immediately after `loadSettings()`.
    private var isHydrating: Bool = false

    /// Outstanding debounced save tasks, one per logical group, so a fast
    /// stream of edits collapses into a single PATCH instead of N PATCHes.
    private var brandingSaveTask: Task<Void, Never>?
    private var taxSaveTask: Task<Void, Never>?
    private var numberingSaveTask: Task<Void, Never>?
    /// Debounce window for text field edits. Long enough that typing doesn't
    /// fire a request per keystroke; short enough that the user perceives
    /// changes as immediately saved when they pause.
    private let debounceNanoseconds: UInt64 = 600_000_000

    // MARK: - Init

    init(service: SettingsServiceProtocol = LiveSettingsService()) {
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

    // MARK: - Auto-save Schedulers

    /// Debounce a branding save. Called from view `.onChange` handlers for
    /// every editable branding field (text inputs and color pickers).
    func scheduleSaveBranding() {
        guard !isHydrating else { return }
        saveStatus = .pending
        brandingSaveTask?.cancel()
        brandingSaveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.debounceNanoseconds)
            if Task.isCancelled { return }
            await self.commitBranding()
        }
    }

    /// Debounce a tax save. Called from `.onChange` of the tax rate text
    /// field and slider; the toggle uses the same scheduler since back-to-back
    /// toggle/edit changes should still coalesce.
    func scheduleSaveTax() {
        guard !isHydrating else { return }
        saveStatus = .pending
        taxSaveTask?.cancel()
        taxSaveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.debounceNanoseconds)
            if Task.isCancelled { return }
            await self.commitTax()
        }
    }

    /// Debounce a numbering save. Stepper increments fire many `onChange`
    /// events — debouncing collapses a held-down stepper into one PATCH.
    func scheduleSaveNumbering() {
        guard !isHydrating else { return }
        saveStatus = .pending
        numberingSaveTask?.cancel()
        numberingSaveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.debounceNanoseconds)
            if Task.isCancelled { return }
            await self.commitNumbering()
        }
    }

    /// Save the language preference immediately. Picker selections are a
    /// single, deliberate user action — no need to debounce them.
    func saveLanguageImmediately() async {
        guard !isHydrating else { return }
        saveStatus = .saving
        do {
            let updated = try await service.saveLanguagePreference(selectedLanguage)
            apply(updated: updated)
            markSaved()
        } catch {
            saveStatus = .failed(message: error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    /// Save the appearance mode immediately on user pick.
    func saveAppearanceImmediately(_ mode: AppearanceMode) async {
        guard !isHydrating else { return }
        saveStatus = .saving
        do {
            let updated = try await service.saveAppearanceMode(mode)
            apply(updated: updated)
            markSaved()
        } catch {
            saveStatus = .failed(message: error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Commit (executed after debounce)

    private func commitBranding() async {
        saveStatus = .saving
        do {
            let update = CompanyBrandingUpdate(
                name: companyName,
                phone: companyPhone.isEmpty ? nil : companyPhone,
                email: companyEmail.isEmpty ? nil : companyEmail,
                address: companyAddress.isEmpty ? nil : companyAddress,
                city: companyCity.isEmpty ? nil : companyCity,
                state: companyState.isEmpty ? nil : companyState,
                zip: companyZip.isEmpty ? nil : companyZip,
                websiteUrl: companyWebsite.isEmpty ? nil : companyWebsite,
                primaryColor: primaryColorHex,
                secondaryColor: secondaryColorHex
            )
            let updated = try await service.saveCompanyBranding(update)
            apply(updated: updated)
            markSaved()
        } catch {
            saveStatus = .failed(message: error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    private func commitTax() async {
        // Sync the free-form text field into the canonical decimal so the
        // server sees what the user actually typed.
        if let parsed = Decimal(string: taxRateText) {
            defaultTaxRate = parsed
        }
        saveStatus = .saving
        do {
            let update = TaxSettingsUpdate(
                defaultTaxRate: defaultTaxRate,
                taxInclusivePricing: taxInclusivePricing
            )
            let updated = try await service.saveTaxSettings(update)
            apply(updated: updated)
            markSaved()
        } catch {
            saveStatus = .failed(message: error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    private func commitNumbering() async {
        saveStatus = .saving
        do {
            let update = NumberingSettingsUpdate(
                estimatePrefix: estimatePrefix,
                invoicePrefix: invoicePrefix,
                nextEstimateNumber: nextEstimateNumber,
                nextInvoiceNumber: nextInvoiceNumber
            )
            let updated = try await service.saveNumberingSettings(update)
            apply(updated: updated)
            markSaved()
        } catch {
            saveStatus = .failed(message: error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Logo Operations (kept explicit — file I/O is naturally event-driven)

    /// Upload the selected logo image and persist the resulting Company
    /// snapshot. The local `companyLogoImage` is kept so the UI shows the
    /// crisp, freshly-picked bytes rather than waiting for `AsyncImage` to
    /// re-download what the server just accepted.
    func uploadCompanyLogo(data: Data, mimeType: String) async {
        isUploadingLogo = true
        errorMessage = nil
        do {
            let updated = try await service.uploadLogo(imageData: data, mimeType: mimeType)
            company = updated
            companyLogoURL = updated.logoURL
            companyLogoImage = UIImage(data: data)
            syncAppState(from: updated)
        } catch {
            errorMessage = error.localizedDescription
        }
        isUploadingLogo = false
    }

    func removeCompanyLogo() async {
        isUploadingLogo = true
        errorMessage = nil
        do {
            let updated = try await service.deleteLogo()
            company = updated
            companyLogoURL = nil
            companyLogoImage = nil
            syncAppState(from: updated)
        } catch {
            errorMessage = error.localizedDescription
        }
        isUploadingLogo = false
    }

    // MARK: - Pricing Profiles

    func savePricingProfile(_ profile: PricingProfile) async {
        saveStatus = .saving
        do {
            let saved = try await service.savePricingProfile(profile)
            if let index = pricingProfiles.firstIndex(where: { $0.id == saved.id }) {
                pricingProfiles[index] = saved
            } else {
                pricingProfiles.append(saved)
            }
            markSaved()
        } catch {
            saveStatus = .failed(message: error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func deletePricingProfile(id: String) async {
        do {
            try await service.deletePricingProfile(id: id)
            pricingProfiles.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Account Deletion

    /// Permanently delete the current user's account.
    /// Required by App Store Review Guideline 5.1.1(v).
    /// On success, callers should sign the user out so the auth gate is shown.
    @discardableResult
    func deleteAccount() async -> Bool {
        do {
            try await APIClient.shared.request(.deleteMe)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Private

    private func apply(updated: Company) {
        company = updated
        syncAppState(from: updated)
        // Reflect any server-side normalization (e.g., trimmed whitespace,
        // canonicalized hex casing, default fallbacks) back into the form
        // without re-triggering autosave.
        isHydrating = true
        defer { isHydrating = false }
        if let mode = updated.appearanceMode, let parsed = AppearanceMode(stringValue: mode) {
            appearanceStore?.applyRemote(mode: parsed)
        }
        if let lang = updated.defaultLanguage, let parsed = AppLanguage(rawValue: lang) {
            selectedLanguage = parsed
            // Mirror to the AppearanceStore so the SwiftUI \.locale is in
            // sync with the saved preference on returning sessions.
            appearanceStore?.applyRemote(language: parsed)
        }
    }

    private func markSaved() {
        saveStatus = .saved(at: Date())
    }

    private func syncAppState(from company: Company) {
        appState?.currentCompany = AppState.CurrentCompany.from(company)
    }

    private func populateFields(from company: Company) {
        isHydrating = true
        defer { isHydrating = false }

        companyName = company.name
        companyPhone = company.phone ?? ""
        companyEmail = company.email ?? ""
        companyAddress = company.address ?? ""
        companyCity = company.city ?? ""
        companyState = company.state ?? ""
        companyZip = company.zip ?? ""
        companyWebsite = company.websiteUrl ?? ""
        companyLogoURL = company.logoURL
        defaultTaxRate = company.defaultTaxRate ?? 8.25
        taxRateText = String(format: "%.2f", NSDecimalNumber(decimal: company.defaultTaxRate ?? 8.25).doubleValue)
        taxInclusivePricing = company.taxInclusivePricing
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

        if let lang = company.defaultLanguage, let parsed = AppLanguage(rawValue: lang) {
            selectedLanguage = parsed
            appearanceStore?.applyRemote(language: parsed)
        }
        if let mode = company.appearanceMode, let parsed = AppearanceMode(stringValue: mode) {
            appearanceStore?.applyRemote(mode: parsed)
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
