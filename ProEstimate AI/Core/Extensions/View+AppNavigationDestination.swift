import SwiftUI

extension View {
    /// Registers the app's shared `AppDestination` navigation routes on the
    /// nearest enclosing `NavigationStack`. Applied at each tab root so that
    /// any `router.<tab>Path.append(destination)` resolves to the same screen
    /// regardless of which tab pushed it. Unhandled destinations resolve to an
    /// empty view rather than crashing.
    func appNavigationDestinations() -> some View {
        navigationDestination(for: AppDestination.self) { destination in
            switch destination {
            case let .projectDetail(id, autoGenerate):
                ProjectDetailView(projectId: id, autoGenerateOnOpen: autoGenerate)
            default:
                EmptyView()
            }
        }
    }
}
