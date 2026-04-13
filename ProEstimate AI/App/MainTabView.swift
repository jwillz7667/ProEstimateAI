import SwiftUI

struct MainTabView: View {
    @Bindable var appState: AppState

    var body: some View {
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

            Tab("Invoices", systemImage: AppTab.invoices.systemImage, value: AppTab.invoices) {
                InvoiceListView()
            }

            Tab("Clients", systemImage: AppTab.clients.systemImage, value: AppTab.clients) {
                ClientListView()
            }
        }
        .tabViewStyle(.tabBarOnly)
        .tint(ColorTokens.primaryOrange)
    }
}

private struct PlaceholderTabView: View {
    let tab: AppTab

    var body: some View {
        NavigationStack {
            EmptyStateView(
                icon: tab.systemImage,
                title: tab.title,
                subtitle: "Coming soon"
            )
            .navigationTitle(tab.title)
        }
    }
}
