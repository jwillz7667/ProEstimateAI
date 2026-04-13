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

        await entitlementStore.refresh()
        await usageMeterStore.refresh()
        await featureGateCoordinator.loadProducts()
    }
}
