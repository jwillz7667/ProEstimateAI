import SwiftUI

struct CustomerPaymentSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = CustomerPaymentSettingsViewModel(service: CustomerPaymentSettingsService())
    @State private var onboardingRequestId: UUID?
    @State private var canPresentOnboarding = false

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
                        Picker("Business country", selection: $model.country) {
                            Text("Choose your business country").tag("")
                            ForEach(countries, id: \.code) { region in Text(region.name).tag(region.code) }
                        }
                        .disabled(snapshot.country != nil || model.isStarting)
                        Text("Available countries are subject to Stripe’s platform and business eligibility checks. Select the country where your business is legally based.")
                            .font(TypographyTokens.footnote).foregroundStyle(ColorTokens.secondaryText)
                        if model.countryCodes.isEmpty {
                            Text("Business country choices are currently unavailable. Contact support before starting payment setup.")
                                .font(TypographyTokens.footnote)
                        }
                        Button(snapshot.connected ? "Continue secure setup" : "Set up payment collection") {
                            onboardingRequestId = UUID()
                        }
                        .disabled(!model.canStart || onboardingRequestId != nil || !canPresentOnboarding)
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
        .task(id: onboardingRequestId) {
            guard let requestId = onboardingRequestId else { return }
            defer { if onboardingRequestId == requestId { onboardingRequestId = nil } }
            if let url = await model.start(), !Task.isCancelled, canPresentOnboarding { openURL(url) }
        }
        .onAppear { canPresentOnboarding = scenePhase == .active }
        .onDisappear {
            canPresentOnboarding = false; onboardingRequestId = nil
            model.invalidate()
        }
        .onChange(of: scenePhase) { _, phase in
            canPresentOnboarding = phase == .active
            if phase == .active { Task { await refresh() } }
            else { onboardingRequestId = nil }
        }
        .refreshable { await refresh() }
    }
    private var countries: [(code: String, name: String)] {
        model.countryCodes.map { ($0, Locale.current.localizedString(forRegionCode: $0) ?? $0) }
            .sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
    }
    private func refresh() async {
        await model.load(scope: "\(appState.currentUser?.id ?? ""):\(appState.currentCompany?.id ?? "")")
    }
}
