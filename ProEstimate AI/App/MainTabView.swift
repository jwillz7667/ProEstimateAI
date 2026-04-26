import SwiftUI

struct MainTabView: View {
    @Bindable var appState: AppState

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $appState.selectedTab) {
                Tab("Dashboard", systemImage: AppTab.dashboard.systemImage, value: AppTab.dashboard) {
                    DashboardView()
                }

                Tab("Projects", systemImage: AppTab.projects.systemImage, value: AppTab.projects) {
                    ProjectListView()
                }

                Tab("Estimates", systemImage: AppTab.estimates.systemImage, value: AppTab.estimates) {
                    EstimateListView()
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
