import SwiftUI

struct MainTabView: View {
    @Bindable var appState: AppState
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        ZStack(alignment: .top) {
            TabView(selection: $appState.selectedTab) {
                Tab("Dashboard", systemImage: AppTab.dashboard.systemImage, value: AppTab.dashboard) {
                    DashboardView()
                }

                Tab("Projects", systemImage: AppTab.projects.systemImage, value: AppTab.projects) {
                    NavigationStack(path: $router.projectsPath) {
                        ProjectListView()
                            .appNavigationDestinations()
                    }
                }

                Tab("Invoices", systemImage: AppTab.invoices.systemImage, value: AppTab.invoices) {
                    NavigationStack(path: $router.invoicesPath) {
                        InvoiceListView()
                            .appNavigationDestinations()
                    }
                }

                Tab("Clients", systemImage: AppTab.clients.systemImage, value: AppTab.clients) {
                    ClientListView()
                }

                Tab("Settings", systemImage: AppTab.settings.systemImage, value: AppTab.settings) {
                    SettingsView()
                }
            }
            .tabViewStyle(.tabBarOnly)
            .tint(ColorTokens.primaryOrange)

            OfflineBanner()
                .zIndex(1)
        }
    }
}
