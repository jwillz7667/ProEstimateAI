 import SwiftUI
import SwiftData

@main
struct ProEstimate_AIApp: App {
    @State private var appState = AppState()
    @State private var appRouter = AppRouter()
    @State private var entitlementStore = EntitlementStore()
    @State private var usageMeterStore = UsageMeterStore()
    @State private var featureGateCoordinator = FeatureGateCoordinator()
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

        // Global navigation bar appearance — orange large title text
        let orange = UIColor(red: 255/255, green: 146/255, blue: 48/255, alpha: 1)
        UINavigationBar.appearance().largeTitleTextAttributes = [.foregroundColor: orange]
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
