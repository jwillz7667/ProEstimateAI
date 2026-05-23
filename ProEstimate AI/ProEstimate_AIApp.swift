import SwiftData
import SwiftUI

@main
struct ProEstimate_AIApp: App {
    /// Tiny UIApplicationDelegate that captures the APNs device token
    /// so the backend can deliver real-time "preview ready" pushes when
    /// the app is killed. SwiftUI does not surface
    /// `didRegisterForRemoteNotificationsWithDeviceToken` on its own —
    /// the AppDelegate adaptor is the supported bridge. Everything else
    /// stays SwiftUI-native.
    @UIApplicationDelegateAdaptor(ApnsAppDelegate.self) private var apnsDelegate

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

    /// App-level coordinator that owns AI generation polling so a
    /// closed-detail-screen / backgrounded / killed app still
    /// reconciles completions and surfaces notifications.
    @State private var generationLifecycle = GenerationLifecycleCoordinator.shared

    @Environment(\.scenePhase) private var scenePhase

    let modelContainer: ModelContainer

    init() {
        // Lift URLCache.shared well above the URLSession default
        // (~512 KB memory, ~10 MB disk). AsyncImage rides URLSession.shared,
        // so once a thumbnail is fetched, every subsequent render of the
        // same URL — pull-to-refresh, tab switches, scroll-back — must hit
        // this cache or it'll re-download. 50 MB / 250 MB comfortably
        // covers the dashboard carousel, recent assets, and a few
        // projects' worth of generation previews without bloating disk
        // beyond what a contractor working out of the app expects.
        URLCache.shared = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 250 * 1024 * 1024,
            directory: nil
        )

        // Apple docs require the UNUserNotificationCenter delegate to be
        // set before applicationDidFinishLaunching, otherwise a
        // launch-from-notification-tap is silently dropped on cold start.
        GenerationNotificationCenter.shared.bootstrap()

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
                    generationLifecycle.handleScenePhase(newPhase)
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
                    if !wasAuthed, isAuthed {
                        Task {
                            await entitlementStore.refresh()
                            await usageMeterStore.refresh()
                            await featureGateCoordinator.loadProducts()
                            await generationLifecycle.resumeAll()
                        }
                    } else if wasAuthed, !isAuthed {
                        // Sign-out: drop any pending generations so a
                        // different account on the same device doesn't
                        // see a stranger's in-flight work or get a stale
                        // notification scheduled before sign-out.
                        generationLifecycle.clearAll()
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

        // Cold-launch resume: if the user had a generation running when
        // the app was killed, the App-level coordinator picks it up here
        // so the UI shows correct in-flight state without waiting for
        // the user to navigate to the project.
        if appState.isAuthenticated {
            await generationLifecycle.resumeAll()
            // Refresh APNs registration on every authed cold launch.
            // Apple recommends calling `registerForRemoteNotifications()`
            // each launch so a token rotation (rare, but happens after
            // restore-from-backup or iCloud account changes) is captured
            // and posted to the backend without waiting for the user to
            // start their next generation.
            await ApnsRegistrar.bootstrapIfPermitted()
        }

        // Long-running tap-stream consumer. Translates a notification
        // tap into a tab-switch + push so the user lands on the right
        // project's detail screen. Survives App lifecycle transitions
        // because the singleton outlives the scene's task.
        Task { @MainActor in
            for await payload in GenerationNotificationCenter.shared.tapStream {
                appState.selectedTab = .projects
                appRouter.projectsPath.append(
                    AppDestination.projectDetail(id: payload.projectId, autoGenerate: false)
                )
            }
        }
    }
}
