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

    // MARK: - Labor Markup Settings Fields

    /// Contractor's margin applied on top of raw labor cost, as a percent.
    /// Mirrors `Company.laborMarkupPercent`; `nil` server-side maps to the
    /// platform default surfaced here. Distinct from materials markup.
    var laborMarkupPercent: Decimal = Decimal(SettingsViewModel.defaultLaborMarkupPercent)
    var laborMarkupText: String = String(SettingsViewModel.defaultLaborMarkupPercent)

    /// Platform default labor markup (percent) — kept in lockstep with the
    /// backend's `DEFAULT_LABOR_MARKUP_PERCENT` so an unset company shows the
    /// same number the server will apply.
    static let defaultLaborMarkupPercent = 25

    // MARK: - Numbering Settings Fields

    var estimatePrefix: String = "EST"
    var invoicePrefix: String = "INV"
    var nextEstimateNumber: Int = 1001
    var nextInvoiceNumber: Int = 2001

    // MARK: - Language Settings

    var selectedLanguage: AppLanguage = .english

    // MARK: - AI Preview Settings

    /// Company-wide default for whether new projects generate an AI design
    /// preview image. Seeds the creation wizard's per-project toggle; service
    /// trades always seed off regardless of this value.
    var defaultAiPreviewEnabled: Bool = true

    // MARK: - Computed

    /// Preview of the next estimate number.
    var nextEstimateDisplay: String {
        "\(estimatePrefix)-\(nextEstimateNumber)"
    }

    /// Preview of the next invoice number.
    var nextInvoiceDisplay: String {
        "\(invoicePrefix)-\(nextInvoiceNumber)"
    }

    /// The labor markup slider's value as a `Double`, bridged from the
    /// canonical `Decimal`. Two-way binding writes back through `laborMarkupText`
    /// so the text field and slider stay in lockstep.
    var laborMarkupSliderValue: Double {
        get { NSDecimalNumber(decimal: laborMarkupPercent).doubleValue }
        set {
            let clamped = clampMarkup(Decimal(newValue))
            // The slider tops out at 100, but the text field accepts up to 999.
            // When the canonical value was typed above the slider's ceiling,
            // a stray drag would otherwise clip it back down to ≤100 and
            // silently discard the contractor's input. Only honor the slider
            // while we're within its range, or when it's genuinely raising the
            // value — high values are edited through the text field.
            guard laborMarkupPercent <= 100 || clamped > laborMarkupPercent else { return }
            laborMarkupPercent = clamped
            laborMarkupText = Self.formatMarkup(clamped)
        }
    }

    /// Format a markup percent for display: whole numbers render without a
    /// decimal point ("25"), fractional values keep up to two trimmed digits
    /// ("27.5"). Keeps the field clean for the common whole-percent case.
    static func formatMarkup(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: number) ?? "\(number.intValue)"
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
    private var laborSaveTask: Task<Void, Never>?
    private var numberingSaveTask: Task<Void, Never>?
    /// Debounce window for text field edits. Long enough that typing doesn't
    /// fire a request per keystroke; short enough that the user perceives
    /// changes as immediately saved when they pause.
    private let debounceNanoseconds: UInt64 = 600_000_000

    /// Debounce tasks may be cancelled while typing; accepted writes must not
    /// be. A single queue preserves server write order, including immediate
    /// toggles and logo changes, even when a caller's task is cancelled.
    private var companySaveTask: Task<Void, Never>?

    private enum SaveSection: Hashable {
        case branding, tax, labor, numbering, language, appearance, aiPreview, logo
    }

    /// A response can acknowledge its own revision without replacing a newer
    /// draft, or fields belonging to another settings section.
    private var saveRevisions: [SaveSection: Int] = [:]
    private var saveSessions: [SaveSection: UUID] = [:]
    private var pendingSaveSections: Set<SaveSection> = []
    private var saveFailures: [SaveSection: String] = [:]
    private var activeSaveSection: SaveSection?
    private var lastSavedAt: Date?

    // MARK: - Init

    init(service: SettingsServiceProtocol = LiveSettingsService()) {
        self.service = service
    }

    // MARK: - Load

    func loadSettings() async {
        // Revisiting Settings must not overwrite a pending or failed draft.
        guard !isLoading, pendingSaveSections.isEmpty, saveFailures.isEmpty else { return }
        let revisionsAtLoad = saveRevisions
        let sessionID = TokenStore.shared.sessionIdentifier
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let loadedCompany = try await service.loadCompanySettings()
            guard TokenStore.shared.sessionIdentifier == sessionID else { return }
            // A user can edit while the GET is in flight. In that case its
            // snapshot predates their edits and must not hydrate the form.
            if saveRevisions == revisionsAtLoad, pendingSaveSections.isEmpty {
                company = loadedCompany
                populateFields(from: loadedCompany)
                syncAppState(from: loadedCompany)
            }

            let loadedProfiles = try await service.loadPricingProfiles()
            guard TokenStore.shared.sessionIdentifier == sessionID else { return }
            pricingProfiles = loadedProfiles
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Auto-save Schedulers

    /// Debounce a branding save. Called from view `.onChange` handlers for
    /// every editable branding field (text inputs and color pickers).
    func scheduleSaveBranding() {
        guard !isHydrating else { return }
        let revision = beginSave(.branding)
        brandingSaveTask?.cancel()
        brandingSaveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.debounceNanoseconds)
            if Task.isCancelled { return }
            // Only the debounce is cancellable. A newer edit must not abort
            // an already accepted write and let the server reorder requests.
            self.brandingSaveTask = nil
            await self.commitBranding(revision: revision)
        }
    }

    /// Debounce a tax save. Called from `.onChange` of the tax rate text
    /// field and slider; the toggle uses the same scheduler since back-to-back
    /// toggle/edit changes should still coalesce.
    func scheduleSaveTax() {
        guard !isHydrating else { return }
        let revision = beginSave(.tax)
        taxSaveTask?.cancel()
        taxSaveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.debounceNanoseconds)
            if Task.isCancelled { return }
            // Only the debounce is cancellable. A newer edit must not abort
            // an already accepted write and let the server reorder requests.
            self.taxSaveTask = nil
            await self.commitTax(revision: revision)
        }
    }

    /// Debounce a labor-markup save. Called from the markup text field and
    /// slider `.onChange` handlers so a drag or fast typing collapses into a
    /// single PATCH.
    func scheduleSaveLabor() {
        guard !isHydrating else { return }
        let revision = beginSave(.labor)
        laborSaveTask?.cancel()
        laborSaveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.debounceNanoseconds)
            if Task.isCancelled { return }
            // Only the debounce is cancellable. A newer edit must not abort
            // an already accepted write and let the server reorder requests.
            self.laborSaveTask = nil
            await self.commitLabor(revision: revision)
        }
    }

    /// Debounce a numbering save. Stepper increments fire many `onChange`
    /// events — debouncing collapses a held-down stepper into one PATCH.
    func scheduleSaveNumbering() {
        guard !isHydrating else { return }
        let revision = beginSave(.numbering)
        numberingSaveTask?.cancel()
        numberingSaveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.debounceNanoseconds)
            if Task.isCancelled { return }
            // Only the debounce is cancellable. A newer edit must not abort
            // an already accepted write and let the server reorder requests.
            self.numberingSaveTask = nil
            await self.commitNumbering(revision: revision)
        }
    }

    /// Save the language preference immediately. Picker selections are a
    /// single, deliberate user action — no need to debounce them.
    func saveLanguageImmediately() async {
        guard !isHydrating else { return }
        let desired = selectedLanguage
        let revision = beginSave(.language)
        // Keep the interface and its launch-time preference responsive even
        // when this write is waiting for an earlier request to finish.
        appearanceStore?.setLanguage(desired)
        await enqueueCompanySave(
            section: .language,
            revision: revision,
            showsError: true,
            operation: { try await self.service.saveLanguagePreference(desired) }
        )
    }

    /// Save the appearance mode immediately on user pick.
    func saveAppearanceImmediately(_ mode: AppearanceMode) async {
        guard !isHydrating else { return }
        let revision = beginSave(.appearance)
        await enqueueCompanySave(
            section: .appearance,
            revision: revision,
            showsError: true,
            operation: { try await self.service.saveAppearanceMode(mode) }
        )
    }

    /// Save the company-wide AI-preview default immediately on toggle. Only
    /// the latest failed choice may roll back, to the last confirmed value.
    func saveDefaultAiPreviewImmediately() async {
        guard !isHydrating else { return }
        let desired = defaultAiPreviewEnabled
        let revision = beginSave(.aiPreview)
        await enqueueCompanySave(
            section: .aiPreview,
            revision: revision,
            showsError: true,
            operation: { try await self.service.saveDefaultAiPreview(desired) },
            onFailure: {
                if self.defaultAiPreviewEnabled == desired {
                    self.defaultAiPreviewEnabled = self.company?.defaultAiPreviewEnabled ?? !desired
                }
            }
        )
    }

    // MARK: - Commit (executed after debounce)

    private func commitBranding(revision: Int) async {
        // Partial emails and URLs remain pending until the form is valid.
        guard saveRevisions[.branding] == revision, isBrandingFormValid else { return }
        let update = CompanyBrandingUpdate(
            name: companyName,
            phone: companyPhone.isEmpty ? nil : companyPhone,
            email: companyEmail.isEmpty ? nil : companyEmail,
            address: companyAddress.isEmpty ? nil : companyAddress,
            city: companyCity.isEmpty ? nil : companyCity,
            state: companyState.isEmpty ? nil : companyState,
            zip: companyZip.isEmpty ? nil : companyZip,
            websiteUrl: normalizedWebsiteForSave,
            primaryColor: primaryColorHex,
            secondaryColor: secondaryColorHex
        )
        // Autosave failures belong in the toolbar. The modal branding alert
        // is reserved for explicit actions such as uploading a logo.
        await enqueueCompanySave(
            section: .branding,
            revision: revision,
            operation: { try await self.service.saveCompanyBranding(update) }
        )
    }

    private func commitTax(revision: Int) async {
        guard saveRevisions[.tax] == revision else { return }
        if let parsed = Decimal(string: taxRateText) {
            defaultTaxRate = parsed
        }
        let update = TaxSettingsUpdate(
            defaultTaxRate: defaultTaxRate,
            taxInclusivePricing: taxInclusivePricing
        )
        await enqueueCompanySave(
            section: .tax,
            revision: revision,
            operation: { try await self.service.saveTaxSettings(update) }
        )
    }

    private func commitLabor(revision: Int) async {
        guard saveRevisions[.labor] == revision else { return }
        if let parsed = Decimal(string: laborMarkupText.trimmingCharacters(in: .whitespaces)) {
            laborMarkupPercent = clampMarkup(parsed)
        }
        // Normalize the captured input before sending, never from a response
        // that may arrive while the user is typing their next value.
        laborMarkupText = Self.formatMarkup(laborMarkupPercent)
        let update = LaborSettingsUpdate(laborMarkupPercent: laborMarkupPercent)
        await enqueueCompanySave(
            section: .labor,
            revision: revision,
            operation: { try await self.service.saveLaborSettings(update) }
        )
    }

    /// Clamp labor markup into the backend validator's accepted band so a
    /// stray edit can't fire a doomed PATCH. Mirrors `z.number().min(0).max(999)`.
    private func clampMarkup(_ value: Decimal) -> Decimal {
        if value < 0 { return 0 }
        if value > 999 { return 999 }
        return value
    }

    private func commitNumbering(revision: Int) async {
        guard saveRevisions[.numbering] == revision else { return }
        let update = NumberingSettingsUpdate(
            estimatePrefix: estimatePrefix,
            invoicePrefix: invoicePrefix,
            nextEstimateNumber: nextEstimateNumber,
            nextInvoiceNumber: nextInvoiceNumber
        )
        await enqueueCompanySave(
            section: .numbering,
            revision: revision,
            operation: { try await self.service.saveNumberingSettings(update) }
        )
    }

    // MARK: - Local Validation (keep autosave from firing doomed PATCHes)

    /// True when the branding form passes the same checks the backend
    /// validator enforces. We mirror only the contract-shaping rules
    /// (presence of name, email format, URL structure) so partial edits
    /// don't trigger 400s while the user is still typing.
    private var isBrandingFormValid: Bool {
        let trimmedName = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        if !companyEmail.isEmpty, !looksLikeEmail(companyEmail) { return false }
        if !companyWebsite.isEmpty, !looksLikeWebsite(companyWebsite) { return false }
        return true
    }

    /// Normalize the website for transit: empty clears it (JSON null), bare
    /// domains get an `https://` scheme so Zod's `.url()` validator accepts
    /// them. Mirrors what most users intuit: typing "acme.com" should save.
    private var normalizedWebsiteForSave: String? {
        let trimmed = companyWebsite.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return trimmed }
        return "https://\(trimmed)"
    }

    private func looksLikeEmail(_ s: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        return s.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func looksLikeWebsite(_ s: String) -> Bool {
        // Accept "https://example.com" or a bare "example.com" with a TLD.
        // Stricter checks are the backend's job; we just want to gate
        // obviously-invalid input from being PATCH'd while the user types.
        let domainPattern = #"^([a-z][a-z0-9+\-.]*://)?[A-Z0-9.-]+\.[A-Z]{2,}([:/].*)?$"#
        return s.range(of: domainPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: - Logo Operations (kept explicit — file I/O is naturally event-driven)

    /// Upload the selected logo image and persist the resulting Company
    /// snapshot. The local `companyLogoImage` is kept so the UI shows the
    /// crisp, freshly-picked bytes rather than waiting for `AsyncImage` to
    /// re-download what the server just accepted.
    func uploadCompanyLogo(data: Data, mimeType: String) async {
        let revision = beginSave(.logo)
        isUploadingLogo = true
        errorMessage = nil
        await enqueueCompanySave(
            section: .logo,
            revision: revision,
            showsError: true,
            operation: { try await self.service.uploadLogo(imageData: data, mimeType: mimeType) },
            onSuccess: { updated in
                self.companyLogoURL = updated.logoURL
                self.companyLogoImage = UIImage(data: data)
            }
        )
        if saveRevisions[.logo] == revision { isUploadingLogo = false }
    }

    func removeCompanyLogo() async {
        let revision = beginSave(.logo)
        isUploadingLogo = true
        errorMessage = nil
        await enqueueCompanySave(
            section: .logo,
            revision: revision,
            showsError: true,
            operation: { try await self.service.deleteLogo() },
            onSuccess: { _ in
                self.companyLogoURL = nil
                self.companyLogoImage = nil
            }
        )
        if saveRevisions[.logo] == revision { isUploadingLogo = false }
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

    @discardableResult
    private func beginSave(_ section: SaveSection) -> Int {
        let revision = (saveRevisions[section] ?? 0) + 1
        saveRevisions[section] = revision
        saveSessions[section] = TokenStore.shared.sessionIdentifier
        pendingSaveSections.insert(section)
        saveFailures[section] = nil
        updateSaveStatus()
        return revision
    }

    private func enqueueCompanySave(
        section: SaveSection,
        revision: Int,
        showsError: Bool = false,
        operation: @escaping @MainActor () async throws -> Company,
        onSuccess: @escaping @MainActor (Company) -> Void = { _ in },
        onFailure: @escaping @MainActor () -> Void = {}
    ) async {
        let precedingTask = companySaveTask
        let sessionID = saveSessions[section]
        let accountID = appState == nil ? nil : (company?.id ?? appState?.currentCompany?.id)
        let task = Task { @MainActor [self] in
            await precedingTask?.value
            // Coalesce superseded writes that have not reached the server.
            guard saveRevisions[section] == revision else { return }
            // A queued save from the previous session must not use a newly
            // signed-in account's credentials or repopulate a signed-out app.
            guard appState?.currentCompany?.id == accountID,
                  TokenStore.shared.sessionIdentifier == sessionID else {
                pendingSaveSections.remove(section)
                updateSaveStatus()
                return
            }
            activeSaveSection = section
            updateSaveStatus()
            defer {
                activeSaveSection = nil
                updateSaveStatus()
            }
            do {
                let updated = try await operation()
                guard appState?.currentCompany?.id == accountID,
                      TokenStore.shared.sessionIdentifier == sessionID else { return }
                // All company writes share this queue, so the full snapshot
                // is the newest confirmed state for app-wide consumers.
                apply(updated: updated)
                guard saveRevisions[section] == revision else { return }
                onSuccess(updated)
                pendingSaveSections.remove(section)
                saveFailures[section] = nil
                lastSavedAt = Date()
            } catch {
                guard appState?.currentCompany?.id == accountID,
                      TokenStore.shared.sessionIdentifier == sessionID,
                      saveRevisions[section] == revision else { return }
                pendingSaveSections.remove(section)
                saveFailures[section] = error.localizedDescription
                onFailure()
                if showsError { errorMessage = error.localizedDescription }
            }
        }
        companySaveTask = task
        await task.value
    }

    private func apply(updated: Company) {
        // PATCH returns a full snapshot. Keep the confirmed company available
        // to app-wide consumers, but never rehydrate editable fields here:
        // even this request's section may already contain a newer draft.
        company = updated
        syncAppState(from: updated)
    }

    private func updateSaveStatus() {
        if let failure = saveFailures.values.first {
            saveStatus = .failed(message: failure)
        } else if activeSaveSection != nil {
            saveStatus = .saving
        } else if !pendingSaveSections.isEmpty {
            saveStatus = .pending
        } else if let lastSavedAt {
            saveStatus = .saved(at: lastSavedAt)
        } else {
            saveStatus = .idle
        }
    }

    private func markSaved() {
        lastSavedAt = Date()
        updateSaveStatus()
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
        let resolvedLaborMarkup = company.laborMarkupPercent ?? Decimal(Self.defaultLaborMarkupPercent)
        laborMarkupPercent = resolvedLaborMarkup
        laborMarkupText = Self.formatMarkup(resolvedLaborMarkup)
        estimatePrefix = company.estimatePrefix ?? "EST"
        invoicePrefix = company.invoicePrefix ?? "INV"
        nextEstimateNumber = company.nextEstimateNumber
        nextInvoiceNumber = company.nextInvoiceNumber
        defaultAiPreviewEnabled = company.defaultAiPreviewEnabled

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
        // Appearance mode is device-local. Pulling
        // it from the server on Settings load was the cause of users seeing
        // the screen flip light↔dark when entering Settings if the server
        // value diverged from the local choice.
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
