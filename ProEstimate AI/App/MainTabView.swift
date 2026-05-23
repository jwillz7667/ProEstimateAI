import SwiftUI

/// Root tab container — four tabs that match the overhaul screenshots:
/// Projects (home), Studio (AI Remodel Studio), Quotes (unified pipeline),
/// Account (settings + clients + subscription).
struct MainTabView: View {
    @Bindable var appState: AppState

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $appState.selectedTab) {
                Tab(AppTab.projects.title, systemImage: AppTab.projects.systemImage, value: AppTab.projects) {
                    ProjectsHomeView()
                }

                Tab(AppTab.studio.title, systemImage: AppTab.studio.systemImage, value: AppTab.studio) {
                    StudioRootView()
                }

                Tab(AppTab.quotes.title, systemImage: AppTab.quotes.systemImage, value: AppTab.quotes) {
                    QuotesRootView()
                }

                Tab(AppTab.account.title, systemImage: AppTab.account.systemImage, value: AppTab.account) {
                    AccountRootView()
                }
            }
            .tabViewStyle(.tabBarOnly)
            .tint(ColorTokens.primaryOrange)

            OfflineBanner()
                .zIndex(1)
        }
    }
}
