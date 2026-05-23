import SwiftUI

/// Root of the Account tab. Owns the `accountPath` NavigationStack and
/// renders the existing `SettingsView` content (with Clients and Subscription
/// reachable via destinations). Task #8 replaces the body with the merged
/// Account layout (avatar header + grouped sections).
struct AccountRootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.accountPath) {
            SettingsView()
        }
    }
}
