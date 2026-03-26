import SwiftUI

@main
struct ProEstimate_AIApp: App {
    @State private var appState = AppState()
    @State private var appRouter = AppRouter()

    var body: some Scene {
        WindowGroup {
            AuthGateView()
                .environment(appState)
                .environment(appRouter)
                .tint(ColorTokens.primaryOrange)
        }
    }
}
