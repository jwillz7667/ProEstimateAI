import Foundation

/// Persists the set of generation IDs the app is "watching" across cold
/// launches and force-quits.
///
/// Why bother? The backend completes generations independent of client
/// connectivity (see backend/src/modules/generations/generations.service.ts:760
/// — `processGeneration` is fire-and-forget on a background tick). But
/// our iOS poll runs in-process, so a force-quit kills the polling Task
/// and any pending local notification scheduling that would otherwise
/// have told the user "ready". This store gives a cold launch the
/// minimum it needs to resume polling and reconcile completion.
///
/// Storage choice — `UserDefaults` over a SwiftData model: the payload
/// is tiny (≤10 entries × ~200 bytes), reads happen exactly once at
/// launch, and we want a synchronous read with no model-container
/// dependency for the App-level coordinator that sits above SwiftData
/// wiring. UserDefaults is the textbook fit.
struct PendingGeneration: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let projectId: String
    let projectTitle: String?
    let startedAt: Date
}

@MainActor
final class InFlightGenerationStore {
    static let shared = InFlightGenerationStore()

    private let defaults: UserDefaults
    private let key = "pendingGenerations.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Replace the persisted list. Trimming happens here — entries
    /// older than 30 minutes are evicted on every write so a runaway
    /// generation that never completed (server-side bug, abandoned
    /// project) doesn't permanently anchor the app into "polling
    /// forever" mode on every launch.
    private func persist(_ entries: [PendingGeneration]) {
        let cutoff = Date().addingTimeInterval(-30 * 60)
        let trimmed = entries.filter { $0.startedAt > cutoff }
        do {
            let data = try JSONEncoder().encode(trimmed)
            defaults.set(data, forKey: key)
        } catch {
            // Swallow: a corrupted encode shouldn't take down the user
            // session. Worst case: the next launch can't resume polling
            // and the in-app state catches up on first refresh.
        }
    }

    /// Snapshot of all currently-watched generations. Returns oldest
    /// first so the resume path polls in roughly start order, which is
    /// the order the user would expect to see results land.
    func list() -> [PendingGeneration] {
        guard let data = defaults.data(forKey: key) else { return [] }
        let decoded = (try? JSONDecoder().decode([PendingGeneration].self, from: data)) ?? []
        return decoded.sorted { $0.startedAt < $1.startedAt }
    }

    func add(_ entry: PendingGeneration) {
        var current = list()
        current.removeAll { $0.id == entry.id }
        current.append(entry)
        persist(current)
    }

    func remove(generationId: String) {
        var current = list()
        current.removeAll { $0.id == generationId }
        persist(current)
    }

    func contains(generationId: String) -> Bool {
        list().contains { $0.id == generationId }
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
