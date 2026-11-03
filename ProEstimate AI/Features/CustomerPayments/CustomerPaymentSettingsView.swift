import SwiftUI

struct CustomerPaymentSettingsSnapshot: Decodable, Sendable {
    let configured: Bool
    let connected: Bool
    let ready: Bool
    let country: String?
    let mode: String?
    let dashboardURL: URL?
    enum CodingKeys: String, CodingKey { case configured, connected, ready, country, mode; case dashboardURL = "dashboard_url" }
}

struct CustomerPaymentOnboardingRequest: Encodable, Sendable { let country: String }
private struct CustomerPaymentOnboardingResponse: Decodable { let url: URL }

@MainActor @Observable
final class CustomerPaymentSettingsViewModel {
    private(set) var snapshot: CustomerPaymentSettingsSnapshot?
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    private(set) var isStarting = false
    private let api: any APIClientProtocol
    private var scope = ""
    private var revision = 0
    init(api: any APIClientProtocol = APIClient.shared) { self.api = api }
    func load(scope: String) async {
        if self.scope != scope {
            self.scope = scope; revision += 1; snapshot = nil; errorMessage = nil
            isLoading = false; isStarting = false
        }
        guard !isLoading, !isStarting else { return }
        let current = revision
        isLoading = true; errorMessage = nil
        defer { if current == revision { isLoading = false } }
        do {
            let loaded: CustomerPaymentSettingsSnapshot = try await api.request(.getMerchantPaymentSettings)
            guard current == revision, !Task.isCancelled else { return }
            snapshot = loaded
        } catch { if current == revision, !Task.isCancelled { errorMessage = error.localizedDescription } }
    }
    func start(country: String) async -> URL? {
        guard !isStarting, !isLoading, snapshot?.configured == true else { return nil }
        let current = revision
        isStarting = true; errorMessage = nil
        defer { if current == revision { isStarting = false } }
        do {
            let response: CustomerPaymentOnboardingResponse = try await api.request(.startMerchantPaymentOnboarding(body: CustomerPaymentOnboardingRequest(country: country)))
            guard current == revision, !Task.isCancelled else { return nil }
            guard response.url.scheme == "https", let host = response.url.host,
                  host == "stripe.com" || host.hasSuffix(".stripe.com") else {
                throw EstimateEditError.validation("The secure payment setup link couldn't be verified. Refresh and try again.")
            }
            return response.url
        } catch { if current == revision, !Task.isCancelled { errorMessage = error.localizedDescription }; return nil }
    }
}

struct CustomerPaymentSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = CustomerPaymentSettingsViewModel()
    @State private var country = Locale.current.region?.identifier ?? "US"

    var body: some View {
        Form {
            Section {
                Text("Collect deposits and invoice payments for your work through your own Stripe account.")
                    .font(TypographyTokens.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Your ProEstimate subscription is managed separately through Apple.")
                    .font(TypographyTokens.footnote).foregroundStyle(ColorTokens.secondaryText)
            }
            if let snapshot = model.snapshot {
                Section("Payment setup") {
                    if !snapshot.configured {
                        Label("Online invoice payments are not available yet", systemImage: "info.circle")
                        Text("You can still send invoices, share payment instructions and record payments you receive.")
                            .font(TypographyTokens.subheadline).foregroundStyle(ColorTokens.secondaryText)
                    } else {
                        Label(snapshot.ready ? "Ready to accept payments" : "Finish your business setup", systemImage: snapshot.ready ? "checkmark.seal" : "exclamationmark.circle")
                        if snapshot.mode == "sandbox" {
                            Text("Payment setup is in a test environment. Real customer payments are not enabled.")
                                .font(TypographyTokens.footnote).foregroundStyle(ColorTokens.secondaryText)
                        }
                        Picker("Business country", selection: $country) {
                            ForEach(countries, id: \.code) { region in Text(region.name).tag(region.code) }
                        }
                        .disabled(snapshot.country != nil || model.isStarting)
                        Button(snapshot.connected ? "Continue secure setup" : "Set up payment collection") {
                            Task { if let url = await model.start(country: country) { openURL(url) } }
                        }
                        .disabled(model.isStarting || model.isLoading)
                        if let dashboard = snapshot.dashboardURL, dashboard.scheme == "https", dashboard.host == "dashboard.stripe.com" {
                            Link("Open Stripe Dashboard", destination: dashboard)
                        }
                        Text("Stripe collects processing fees. ProEstimate adds no payment processing fee. Complete required business and bank details on Stripe’s secure page.")
                            .font(TypographyTokens.footnote).foregroundStyle(ColorTokens.secondaryText)
                    }
                }
            }
            if model.isLoading || model.isStarting { ProgressView(model.isStarting ? "Preparing secure setup…" : "Checking payment setup…") }
            if let message = model.errorMessage { Section { Text(message).fixedSize(horizontal: false, vertical: true) } }
            Section {
                Button("Refresh payment status") { Task { await refresh() } }.disabled(model.isLoading || model.isStarting)
                Text("Returning from setup does not activate payments by itself. Refresh to check Stripe’s current verification status.")
                    .font(TypographyTokens.footnote).foregroundStyle(ColorTokens.secondaryText)
            }
        }
        .navigationTitle("Customer payments")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(appState.currentUser?.id ?? ""):\(appState.currentCompany?.id ?? "")") { await refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refresh() } } }
        .refreshable { await refresh() }
    }
    private var countries: [(code: String, name: String)] {
        Locale.Region.isoRegions.map(\.identifier).filter { $0.count == 2 }.map { ($0, Locale.current.localizedString(forRegionCode: $0) ?? $0) }
            .sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
    }
    private func refresh() async {
        await model.load(scope: "\(appState.currentUser?.id ?? ""):\(appState.currentCompany?.id ?? "")")
        if let saved = model.snapshot?.country { country = saved }
    }
}
