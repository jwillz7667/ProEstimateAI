import Foundation

@MainActor private var checks = 0
@MainActor private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    checks += 1
    if !condition() { throw Failure.failed(message) }
}
private enum Failure: LocalizedError {
    case failed(String), unavailable
    var errorDescription: String? {
        switch self { case let .failed(message): message; case .unavailable: "Payment setup could not be confirmed" }
    }
}

@MainActor
private final class FakeSettings: CustomerPaymentSettingsServing {
    var current = CustomerPaymentSettingsSnapshot(configured: true, connected: false, ready: false, country: nil, mode: "sandbox", dashboardURL: nil, supportedCountries: ["US", "CA", "DE"])
    var statusFails = false
    var onboardingCalls: [String] = []
    var onboardingAction: (() async throws -> URL)?

    func status() async throws -> CustomerPaymentSettingsSnapshot {
        if statusFails { throw Failure.unavailable }
        return current
    }
    func onboarding(country: String) async throws -> URL {
        onboardingCalls.append(country)
        if let onboardingAction { return try await onboardingAction() }
        return URL(string: "https://connect.stripe.com/setup/test")!
    }
    func reserve(_ country: String?) {
        current = CustomerPaymentSettingsSnapshot(configured: true, connected: false, ready: false, country: country, mode: "sandbox", dashboardURL: nil, supportedCountries: ["US", "CA", "DE"])
    }
}

@main @MainActor
struct CustomerPaymentSettingsRegressionTests {
    static func main() async throws {
        let legacy = try JSONDecoder().decode(CustomerPaymentSettingsSnapshot.self, from: Data(#"{"configured":true,"connected":false,"ready":false,"country":"JP","mode":"sandbox","dashboard_url":null}"#.utf8))
        try expect(legacy.supportedCountries == nil && legacy.country == "JP", "An earlier backend response must still decode its saved country")

        let service = FakeSettings()
        let model = CustomerPaymentSettingsViewModel(service: service)
        await model.load(scope: "user-a:company-a")
        try expect(model.country.isEmpty && !model.canStart, "The device locale must not silently choose a business country")
        model.country = "AQ"
        try expect(!model.canStart, "A country outside the server candidate list must not start setup")
        model.country = "DE"
        try expect(model.canStart, "European candidate countries must remain available")

        service.onboardingAction = { throw Failure.unavailable }
        let rejected = await model.start()
        try expect(rejected == nil && service.onboardingCalls == ["DE"], "A rejected setup must not open a browser")
        try expect(model.snapshot?.country == nil && !model.requiresRefresh, "A released reservation must be reread after failure")
        model.country = "CA"
        service.onboardingAction = nil
        let corrected = await model.start()
        try expect(corrected?.host == "connect.stripe.com" && service.onboardingCalls == ["DE", "CA"], "The user can correct the country after definitive rejection")

        service.onboardingAction = {
            service.reserve("CA")
            throw Failure.unavailable
        }
        _ = await model.start()
        try expect(model.snapshot?.country == "CA" && model.country == "CA", "An ambiguous response must reload and keep the reserved country")
        model.country = "US"
        try expect(!model.canStart, "The UI cannot change an ambiguous reservation's country")

        model.country = "CA"
        service.statusFails = true
        _ = await model.start()
        try expect(model.requiresRefresh && !model.canStart, "Failed authoritative reload must block another setup attempt")
        try expect(model.errorMessage?.contains("Refresh payment status") == true, "Failed reload must explain the available recovery action")
        service.statusFails = false
        await model.load(scope: "user-a:company-a")
        try expect(!model.requiresRefresh && model.canStart, "An explicit successful refresh restores safe same-country retry")

        service.reserve("JP")
        await model.load(scope: "user-a:company-a")
        try expect(model.countryCodes.contains("JP") && model.country == "JP" && model.canStart, "Existing saved countries remain visible and recoverable outside the candidate list")

        service.reserve(nil)
        await model.load(scope: "user-b:company-b")
        try expect(model.country.isEmpty && model.snapshot?.country == nil && !model.canStart, "Changing accounts must discard the previous business country")

        var complete: CheckedContinuation<URL, Error>?
        model.country = "US"
        let beforePending = service.onboardingCalls.count
        service.onboardingAction = { try await withCheckedThrowingContinuation { complete = $0 } }
        let pending = Task { await model.start() }
        while complete == nil { await Task.yield() }
        _ = await model.start()
        try expect(service.onboardingCalls.count == beforePending + 1 && model.isStarting, "A second tap must not launch a second in-flight setup")
        await model.load(scope: "user-c:company-c")
        complete?.resume(returning: URL(string: "https://connect.stripe.com/setup/old-account")!)
        let oldURL = await pending.value
        try expect(oldURL == nil && model.country.isEmpty, "A setup response from a previous account must never open a browser")

        complete = nil
        await model.load(scope: "user-c:company-c")
        model.country = "US"
        let dismissed = Task { await model.start() }
        while complete == nil { await Task.yield() }
        model.invalidate()
        complete?.resume(returning: URL(string: "https://connect.stripe.com/setup/dismissed")!)
        let dismissedURL = await dismissed.value
        try expect(dismissedURL == nil, "A dismissed settings screen must ignore a late setup URL")
        try expect(!model.isStarting && model.snapshot == nil, "Dismissal must clear the screen's previous account state")
        print("PASS: \(checks) customer payment settings checks")
    }
}
