import SwiftData
import SwiftUI

@main
struct ProEstimate_AIApp: App {
    @State private var appState = AppState()
    @State private var appRouter = AppRouter()
    // Anchor the App's @State to the canonical singletons so that any
    // collaborator that defaults to `.shared` (e.g. PaywallHostViewModel,
    // StoreKitPurchaseCoordinator, DashboardSubscriptionCardViewModel) ends
    // up mutating the very same instance that the SwiftUI environment
    // observes. Allocating fresh instances here would create a split-brain
    // where purchases update one store and the UI reads from another.
    @State private var entitlementStore = EntitlementStore.shared
    @State private var usageMeterStore = UsageMeterStore.shared
    @State private var featureGateCoordinator = FeatureGateCoordinator.shared
    @State private var paywallPresenter = PaywallPresenter()
    @State private var appearanceStore = AppearanceStore()
    @State private var onboardingStore = OnboardingStore.shared
    @State private var networkMonitor = NetworkMonitor.shared

    @Environment(\.scenePhase) private var scenePhase

    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(
                for: CachedProject.self, CachedEstimate.self, CachedClient.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        // Global navigation bar appearance.
        //
        // Title text uses a dynamic UIColor: dark slate (#2A323A) in light
        // mode for AAA contrast against the white page background, and the
        // system label color in dark mode (white-ish) which already passes
        // AAA on the dark page background. White-on-#2A323A and
        // #2A323A-on-white both score ~12.7:1 — comfortably above the 7:1
        // threshold for normal text.
        //
        // Tint color stays brand-orange so navigation chevrons, action
        // items, and back buttons read as primary actions.
        let slate = UIColor(red: 0x2A / 255, green: 0x32 / 255, blue: 0x3A / 255, alpha: 1)
        let orange = UIColor(red: 0xFF / 255, green: 0x92 / 255, blue: 0x30 / 255, alpha: 1)
        let titleColor = UIColor { traits in
            traits.userInterfaceStyle == .dark ? .label : slate
        }

        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.titleTextAttributes = [.foregroundColor: titleColor]
        appearance.largeTitleTextAttributes = [.foregroundColor: titleColor]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = orange
    }

    var body: some Scene {
        WindowGroup {
            AuthGateView()
                .environment(appState)
                .environment(appRouter)
                .environment(entitlementStore)
                .environment(usageMeterStore)
                .environment(featureGateCoordinator)
                .environment(paywallPresenter)
                .environment(appearanceStore)
                .environment(onboardingStore)
                .environment(networkMonitor)
                .preferredColorScheme(appearanceStore.colorScheme)
                // Push the user's chosen interface language into the
                // environment so all `String(localized:)`-resolved copy
                // (English / Espa\u{00F1}ol / future) updates live without
                // a relaunch or a trip to iOS Settings.
                .environment(\.locale, appearanceStore.locale)
                .tint(ColorTokens.primaryOrange)
                .task {
                    await bootstrap()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task {
                            await entitlementStore.refresh()
                            await usageMeterStore.refresh()
                        }
                    }
                }
                // Refresh commerce state immediately on auth transitions.
                // `bootstrap()` only runs once when the WindowGroup's task
                // first fires, which happens before sign-in for cold-start
                // unauthenticated users. Without this hook, a fresh signup
                // or login would leave the entitlement snapshot stuck on
                // whatever (or nothing) the pre-auth refresh produced —
                // until the next foreground transition. We mirror the same
                // refreshes here so subscription state, usage credits, and
                // the store catalog are all up-to-date the moment the
                // user lands on the dashboard.
                //
                // Sign-out is already handled inside `AppState.signOut`,
                // which calls `reset()` on both stores, so we only act on
                // the false → true transition.
                .onChange(of: appState.isAuthenticated) { wasAuthed, isAuthed in
                    guard !wasAuthed, isAuthed else { return }
                    Task {
                        await entitlementStore.refresh()
                        await usageMeterStore.refresh()
                        await featureGateCoordinator.loadProducts()
                    }
                }
                .sheet(item: $paywallPresenter.activeDecision) { decision in
                    PaywallHostView(decision: decision) {
                        paywallPresenter.dismiss()
                        Task {
                            await entitlementStore.refresh()
                            await usageMeterStore.refresh()
                        }
                    }
                }
        }
        .modelContainer(modelContainer)
    }

    private func bootstrap() async {
        let commerceAPI = CommerceAPIClient()
        entitlementStore.configure(commerceAPI: commerceAPI)
        usageMeterStore.configure(commerceAPI: commerceAPI, entitlementStore: entitlementStore)
        featureGateCoordinator.configure(entitlementStore: entitlementStore, usageMeterStore: usageMeterStore)
        // Defensive net: PaywallPresenter silently drops `present(_:)` calls
        // for users who already have Pro access, so legacy / future call
        // sites cannot surface a paywall to a paying subscriber.
        paywallPresenter.configure(entitlementStore: entitlementStore)

        // Wire the unauthorized callback so a failed token refresh signs the user out
        // instead of leaving them stuck in a half-authenticated state.
        let appState = self.appState
        let entitlementStore = self.entitlementStore
        let usageMeterStore = self.usageMeterStore
        APIClient.shared.onUnauthorized = {
            Task { @MainActor in
                appState.signOut(
                    entitlementStore: entitlementStore,
                    usageMeterStore: usageMeterStore
                )
            }
        }

        // Start the StoreKit Transaction.updates listener so renewals, refunds,
        // and revocations from outside the app are reconciled in the background.
        let purchaseCoordinator = StoreKitPurchaseCoordinator(
            commerceAPI: commerceAPI,
            entitlementStore: entitlementStore
        )
        Task.detached(priority: .background) {
            await purchaseCoordinator.listenForTransactions()
        }

        await entitlementStore.refresh()
        await usageMeterStore.refresh()
        await featureGateCoordinator.loadProducts()
    }
}
