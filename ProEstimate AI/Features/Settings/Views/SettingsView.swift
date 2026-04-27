import SwiftUI

struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()
    @Environment(AppState.self) private var appState: AppState
    @Environment(EntitlementStore.self) private var entitlementStore
    @Environment(UsageMeterStore.self) private var usageMeterStore
    @Environment(PaywallPresenter.self) private var paywallPresenter
    @Environment(FeatureGateCoordinator.self) private var featureGateCoordinator
    @Environment(AppRouter.self) private var router
    @Environment(AppearanceStore.self) private var appearanceStore
    @State private var showingSignOutConfirmation = false
    @State private var showingDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.company == nil {
                    LoadingStateView(message: "Loading settings...")
                } else {
                    settingsList
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(for: AppDestination.self) { destination in
                switch destination {
                case .companyBranding:
                    CompanyBrandingView(viewModel: viewModel)
                case .taxSettings:
                    TaxSettingsView(viewModel: viewModel)
                case .numberingSettings:
                    NumberingSettingsView(viewModel: viewModel)
                case .pricingProfiles:
                    PricingProfilesView(viewModel: viewModel)
                case .languageSettings:
                    LanguageSettingsView(viewModel: viewModel)
                case .analytics:
                    AnalyticsView()
                default:
                    EmptyView()
                }
            }
            .task {
                viewModel.appState = appState
                viewModel.appearanceStore = appearanceStore
                await viewModel.loadSettings()
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
            .confirmationDialog(
                "Sign Out",
                isPresented: $showingSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    appState.signOut(
                        entitlementStore: entitlementStore,
                        usageMeterStore: usageMeterStore
                    )
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .confirmationDialog(
                "Delete Account",
                isPresented: $showingDeleteAccountConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Account Permanently", role: .destructive) {
                    Task { await performAccountDeletion() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your account, company, and all related projects, estimates, and invoices. This cannot be undone. Any active subscription must be canceled separately in your Apple ID settings.")
            }
        }
    }

    // MARK: - Pro Badge

    private var proBadge: some View {
        Text("PRO")
            .font(TypographyTokens.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, SpacingTokens.xs)
            .padding(.vertical, 2)
            .background(ColorTokens.primaryOrange, in: Capsule())
    }

    // MARK: - Feature Gates

    private func handleAnalyticsTap() {
        let result = featureGateCoordinator.guardAccessAnalytics()
        switch result {
        case .allowed:
            router.settingsPath.append(AppDestination.analytics)
        case let .blocked(decision):
            paywallPresenter.present(decision)
        }
    }

    // MARK: - Account Deletion

    private func performAccountDeletion() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        let succeeded = await viewModel.deleteAccount()
        if succeeded {
            appState.signOut(
                entitlementStore: entitlementStore,
                usageMeterStore: usageMeterStore
            )
        }
    }

    // MARK: - Settings List

    private var settingsList: some View {
        List {
            // Billing issue banner — surfaces grace-period / billing-retry warnings
            // so users can update their payment method before Pro access lapses.
            if entitlementStore.hasBillingIssue {
                Section {
                    BillingIssueBanner()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            // Account Section
            Section("Account") {
                if let user = appState.currentUser {
                    HStack(spacing: SpacingTokens.sm) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(ColorTokens.primaryOrange.opacity(0.5))

                        VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                            Text(user.fullName)
                                .font(TypographyTokens.headline)
                            Text(user.email)
                                .font(TypographyTokens.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, SpacingTokens.xxs)
                }

                Button(role: .destructive) {
                    showingSignOutConfirmation = true
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }

                Button(role: .destructive) {
                    showingDeleteAccountConfirmation = true
                } label: {
                    HStack {
                        Label("Delete Account", systemImage: "trash")
                        if isDeletingAccount {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isDeletingAccount)
            }

            // Company Section
            Section("Company") {
                NavigationLink(value: AppDestination.companyBranding) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Branding")
                            Text(viewModel.companyName.isEmpty ? "Not configured" : viewModel.companyName)
                                .font(TypographyTokens.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "paintbrush")
                            .foregroundStyle(ColorTokens.primaryOrange)
                    }
                }

                NavigationLink(value: AppDestination.taxSettings) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tax Settings")
                            Text("\(NSDecimalNumber(decimal: viewModel.defaultTaxRate).doubleValue, specifier: "%.2f")%")
                                .font(TypographyTokens.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "building.columns")
                            .foregroundStyle(ColorTokens.accentBlue)
                    }
                }

                NavigationLink(value: AppDestination.numberingSettings) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Document Numbering")
                            Text("\(viewModel.nextEstimateDisplay) / \(viewModel.nextInvoiceDisplay)")
                                .font(TypographyTokens.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "number")
                            .foregroundStyle(ColorTokens.accentPurple)
                    }
                }

                Button {
                    handleAnalyticsTap()
                } label: {
                    Label {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Analytics")
                                    .foregroundStyle(ColorTokens.primaryText)
                                Text("Projects, revenue & estimates")
                                    .font(TypographyTokens.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !entitlementStore.hasProAccess {
                                proBadge
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    } icon: {
                        Image(systemName: "chart.bar.xaxis")
                            .foregroundStyle(ColorTokens.primaryOrange)
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())

                NavigationLink(value: AppDestination.pricingProfiles) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pricing Profiles")
                            Text("\(viewModel.pricingProfiles.count) profile\(viewModel.pricingProfiles.count == 1 ? "" : "s")")
                                .font(TypographyTokens.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "dollarsign.gauge.chart.lefthalf.righthalf")
                            .foregroundStyle(ColorTokens.accentGreen)
                    }
                }
            }

            // App Section
            Section("App") {
                NavigationLink(value: AppDestination.languageSettings) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Language")
                            Text(viewModel.selectedLanguage.displayName)
                                .font(TypographyTokens.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "globe")
                            .foregroundStyle(ColorTokens.accentTeal)
                    }
                }

                Label {
                    Picker(
                        "Appearance",
                        selection: Binding(
                            get: { appearanceStore.mode },
                            set: { newMode in
                                Task { await appearanceStore.setMode(newMode) }
                            }
                        )
                    ) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Label(mode.label, systemImage: mode.icon)
                                .tag(mode)
                        }
                    }
                } icon: {
                    Image(systemName: appearanceStore.mode.icon)
                        .foregroundStyle(ColorTokens.primaryOrange)
                }
            }

            // Subscription Section
            Section("Subscription") {
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Current Plan")
                            subscriptionDetailText
                                .font(TypographyTokens.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: entitlementStore.hasProAccess ? "crown.fill" : "crown")
                            .foregroundStyle(ColorTokens.primaryOrange)
                    }

                    Spacer()

                    if !entitlementStore.hasProAccess {
                        Button("Upgrade") {
                            paywallPresenter.present(.settingsUpgrade)
                        }
                        .font(TypographyTokens.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, SpacingTokens.sm)
                        .padding(.vertical, SpacingTokens.xxs)
                        .background(ColorTokens.primaryOrange, in: Capsule())
                    }
                }
            }

            // About Section
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0 (1)")
                        .foregroundStyle(.secondary)
                }

                Link(destination: AppConstants.termsOfServiceURL) {
                    Label("Terms of Service", systemImage: "doc.text")
                }

                Link(destination: AppConstants.privacyPolicyURL) {
                    Label("Privacy Policy", systemImage: "lock.shield")
                }

                Link(destination: AppConstants.supportEmailURL) {
                    Label("Contact Support", systemImage: "envelope")
                }
            } header: {
                Text("About")
            } footer: {
                VStack(spacing: SpacingTokens.xs) {
                    Image("housd-icon-light")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 32)
                        .opacity(0.6)

                    Text("ProEstimate AI")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, SpacingTokens.lg)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Subscription Detail

    @ViewBuilder
    private var subscriptionDetailText: some View {
        let state = entitlementStore.subscriptionState
        switch state {
        case .trialActive:
            if let days = entitlementStore.trialDaysRemaining {
                Text("\(state.displayLabel) — \(days) day\(days == 1 ? "" : "s") remaining")
            } else {
                Text(state.displayLabel)
            }
        case .gracePeriod, .billingRetry:
            Text("\(state.displayLabel) — Update payment method")
        default:
            Text(entitlementStore.currentPlanCode.displayName)
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environment(AppState())
        .environment(EntitlementStore.preview())
        .environment(UsageMeterStore.preview())
        .environment(PaywallPresenter())
        .environment(AppearanceStore())
}
