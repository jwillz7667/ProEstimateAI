import Foundation
import Observation

struct CustomerPaymentSettingsSnapshot: Decodable, Sendable {
    let configured: Bool
    let connected: Bool
    let ready: Bool
    let country: String?
    let mode: String?
    let dashboardURL: URL?
    /// Optional so the app can read responses from an earlier backend.
    let supportedCountries: [String]?

    enum CodingKeys: String, CodingKey {
        case configured, connected, ready, country, mode
        case dashboardURL = "dashboard_url"
        case supportedCountries = "supported_countries"
    }
}

protocol CustomerPaymentSettingsServing: Sendable {
    func status() async throws -> CustomerPaymentSettingsSnapshot
    func onboarding(country: String) async throws -> URL
}

@MainActor @Observable
final class CustomerPaymentSettingsViewModel {
    private(set) var snapshot: CustomerPaymentSettingsSnapshot?
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    private(set) var isStarting = false
    private(set) var requiresRefresh = false
    var country = ""
    private let service: any CustomerPaymentSettingsServing
    private var scope = ""
    private var revision = 0

    init(service: any CustomerPaymentSettingsServing) { self.service = service }

    func invalidate() {
        revision += 1; scope = ""; snapshot = nil; country = ""; errorMessage = nil
        isLoading = false; isStarting = false; requiresRefresh = false
    }

    var countryCodes: [String] {
        var countries = Set(snapshot?.supportedCountries ?? [])
        // A prior reservation can require reconciliation even if eligibility
        // changed. Never silently replace its actual business country.
        if let saved = snapshot?.country { countries.insert(saved) }
        return countries.sorted()
    }

    var canStart: Bool {
        guard snapshot?.configured == true, !isStarting, !isLoading, !requiresRefresh, !country.isEmpty else { return false }
        if let saved = snapshot?.country { return country == saved }
        return snapshot?.supportedCountries?.contains(country) == true
    }

    func load(scope: String) async {
        if self.scope != scope {
            self.scope = scope; revision += 1; snapshot = nil; errorMessage = nil; country = ""
            isLoading = false; isStarting = false; requiresRefresh = false
        }
        guard !isLoading, !isStarting else { return }
        let current = revision
        isLoading = true; errorMessage = nil
        defer { if current == revision { isLoading = false } }
        do {
            let loaded = try await service.status()
            guard current == revision, !Task.isCancelled else { return }
            apply(loaded)
        } catch {
            if current == revision, !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }

    func start() async -> URL? {
        guard canStart else { return nil }
        let current = revision
        isStarting = true; errorMessage = nil
        defer { if current == revision { isStarting = false } }
        do {
            let url = try await service.onboarding(country: country)
            guard current == revision, !Task.isCancelled else { return nil }
            guard url.scheme == "https", let host = url.host, host == "stripe.com" || host.hasSuffix(".stripe.com") else {
                throw PaymentSettingsError.unverifiedURL
            }
            return url
        } catch {
            guard current == revision, !Task.isCancelled else { return nil }
            let message = error.localizedDescription
            requiresRefresh = true
            // A definitive rejection may have released the reservation, while
            // an ambiguous write must keep its original country locked. Read
            // the server's decision instead of retaining the pre-submit state.
            do {
                let loaded = try await service.status()
                guard current == revision, !Task.isCancelled else { return nil }
                apply(loaded)
            } catch { /* The explicit refresh action remains available. */ }
            guard current == revision, !Task.isCancelled else { return nil }
            errorMessage = requiresRefresh ? "\(message) Refresh payment status before trying again." : message
            return nil
        }
    }

    private func apply(_ loaded: CustomerPaymentSettingsSnapshot) {
        snapshot = loaded
        requiresRefresh = false
        if let saved = loaded.country { country = saved }
        else if loaded.supportedCountries?.contains(country) != true { country = "" }
    }
}

private enum PaymentSettingsError: LocalizedError {
    case unverifiedURL
    var errorDescription: String? { "The secure payment setup link couldn't be verified. Refresh and try again." }
}
