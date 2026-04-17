import Foundation
import Network
import Observation

/// Observes device network reachability and exposes it to SwiftUI views.
///
/// Wraps `NWPathMonitor` so that the rest of the app can distinguish a true offline
/// state from backend failures without importing the `Network` framework at every
/// call site. A single shared instance is injected into the environment at app root.
@MainActor
@Observable
final class NetworkMonitor {
    // MARK: - Shared Instance

    static let shared = NetworkMonitor()

    // MARK: - State

    private(set) var isOnline: Bool = true
    private(set) var connectionType: String?

    // MARK: - Private

    private let monitor: NWPathMonitor
    private let queue: DispatchQueue

    // MARK: - Init

    private init() {
        self.monitor = NWPathMonitor()
        self.queue = DispatchQueue(label: "NetworkMonitor")

        // NWPathMonitor invokes its handler on the dedicated background queue.
        // We hop back to the MainActor before mutating @Observable state so that
        // SwiftUI view updates always happen on the main thread.
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            // Inlined to avoid actor-isolation warnings on a shared helper —
            // NWPath itself is Sendable and these property reads are pure.
            let type: String?
            if path.usesInterfaceType(.wifi) {
                type = "wifi"
            } else if path.usesInterfaceType(.cellular) {
                type = "cellular"
            } else if path.usesInterfaceType(.wiredEthernet) {
                type = "wired"
            } else if path.status == .satisfied {
                type = "other"
            } else {
                type = nil
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isOnline = online
                self.connectionType = type
            }
        }

        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
