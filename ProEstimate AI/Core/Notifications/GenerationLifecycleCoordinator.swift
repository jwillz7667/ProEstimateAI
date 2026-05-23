import Foundation
import SwiftUI
import UIKit

/// Single source of truth for the lifecycle of in-flight AI generations
/// across the app's foreground / background / killed transitions.
///
/// Why a separate coordinator instead of per-VM polling?
///
/// The original `ProjectDetailViewModel` held its polling Task and tore
/// it down on `.onDisappear`. That worked while the user stayed on the
/// detail screen but failed in three real-world scenarios:
///
///   1. **Navigation away.** User taps "Generate", then navigates back to
///      the project list while waiting. VM is destroyed, the Task is
///      cancelled, the generation continues server-side, the client
///      never observes the completion until the next manual refresh.
///   2. **App backgrounded.** SwiftUI may tear down view models when the
///      scene goes inactive. Same outcome — server completes, client
///      misses.
///   3. **App killed.** Force-quit kills the in-process Task entirely.
///      No persistence means no resume on next launch.
///
/// The coordinator is App-level: it outlives every view, persists
/// in-flight state to UserDefaults via `InFlightGenerationStore`, and
/// re-hydrates polling on cold launch via `resumeAll()`. It also wraps
/// background polling in a `UIBackgroundTask` grace window so a brief
/// background trip catches completion and schedules a local "ready"
/// notification, and broadcasts lifecycle events so VMs can refresh
/// their own state without owning the polling.
@MainActor
@Observable
final class GenerationLifecycleCoordinator {
    static let shared = GenerationLifecycleCoordinator()

    /// Lifecycle events broadcast to any VM that wants to react.
    /// Subscribers re-fetch from the server rather than receiving the
    /// full payload — avoids stale-write races against the canonical
    /// backend, and keeps the coordinator's surface area tiny.
    enum Event: Sendable {
        case completed(generationId: String, projectId: String)
        case failed(generationId: String, projectId: String, message: String?)

        var projectId: String {
            switch self {
            case let .completed(_, projectId), let .failed(_, projectId, _):
                return projectId
            }
        }
    }

    // MARK: - Dependencies

    private let generationService: GenerationServiceProtocol
    private let store: InFlightGenerationStore
    private let notifications: GenerationNotificationCenter

    // MARK: - State

    private var pollingTasks: [String: Task<Void, Never>] = [:]
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var currentScenePhase: ScenePhase = .active

    /// Notifications scheduled while the app was backgrounded so we can
    /// cancel any that have not yet fired when the user returns to the
    /// foreground (the in-app UI now shows the completed state and a
    /// banner over top would be redundant noise).
    private var scheduledNotificationIDs: Set<String> = []

    private let eventsStream = AsyncStream<Event>.makeStream()

    /// Stream of generation lifecycle events. The stream never
    /// terminates so callers can subscribe long-running tasks against
    /// it; cancellation comes from the consumer side.
    nonisolated var events: AsyncStream<Event> {
        MainActor.assumeIsolated { eventsStream.stream }
    }

    // MARK: - Init

    init(
        generationService: GenerationServiceProtocol = LiveGenerationService(),
        store: InFlightGenerationStore = .shared,
        notifications: GenerationNotificationCenter = .shared
    ) {
        self.generationService = generationService
        self.store = store
        self.notifications = notifications
    }

    // MARK: - Public API

    /// Whether any generation is currently being polled. Drives
    /// dashboard-level "still processing" indicators.
    var hasInFlightGenerations: Bool {
        !pollingTasks.isEmpty
    }

    /// Registers a freshly-created generation: persists for cold-launch
    /// resume, requests notification permission once if needed, and
    /// kicks off polling. Idempotent — a second call for the same
    /// `generationId` is a no-op while the first poll is still alive.
    func registerStart(generationId: String, projectId: String, projectTitle: String?) {
        guard pollingTasks[generationId] == nil else { return }
        store.add(PendingGeneration(
            id: generationId,
            projectId: projectId,
            projectTitle: projectTitle,
            startedAt: Date()
        ))
        // Permission ask is async + idempotent. Do it eagerly the first
        // time a generation kicks off so the prompt lands in the natural
        // flow rather than at a surprise moment.
        Task { await notifications.requestPermissionIfNeeded() }
        startPolling(generationId: generationId, projectId: projectId, projectTitle: projectTitle)
    }

    /// Re-starts polling for every persisted in-flight generation.
    /// Called from `App.bootstrap()` after auth is confirmed so a cold
    /// launch silently catches completions that landed while the app
    /// was killed. Idempotent against repeat calls.
    func resumeAll() async {
        for entry in store.list() {
            guard pollingTasks[entry.id] == nil else { continue }
            startPolling(
                generationId: entry.id,
                projectId: entry.projectId,
                projectTitle: entry.projectTitle
            )
        }
    }

    /// Hook from the App-level `.onChange(of: scenePhase)`. Drives the
    /// `UIBackgroundTask` window and clears stale notifications on
    /// resume so the user doesn't see a "ready" banner for something
    /// they're already looking at.
    func handleScenePhase(_ phase: ScenePhase) {
        let previous = currentScenePhase
        currentScenePhase = phase
        switch phase {
        case .active:
            endBackgroundTaskIfNeeded()
            if previous != .active {
                cancelStaleScheduledNotifications()
            }
        case .background:
            beginBackgroundTaskIfNeeded()
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    /// Cancel polling and notifications for a generation. Used when the
    /// user explicitly tears down a project or signs out. Does NOT clear
    /// the entire store — that is `clearAll()`.
    func cancel(generationId: String) {
        pollingTasks[generationId]?.cancel()
        pollingTasks.removeValue(forKey: generationId)
        store.remove(generationId: generationId)
        notifications.cancel(generationId: generationId)
        scheduledNotificationIDs.remove(generationId)
        if pollingTasks.isEmpty {
            endBackgroundTaskIfNeeded()
        }
    }

    /// Tear down everything. Called on sign-out so a different user
    /// signing in on the same device doesn't see a stranger's pending
    /// generations.
    func clearAll() {
        for (_, task) in pollingTasks {
            task.cancel()
        }
        pollingTasks.removeAll()
        for id in scheduledNotificationIDs {
            notifications.cancel(generationId: id)
        }
        scheduledNotificationIDs.removeAll()
        store.clear()
        endBackgroundTaskIfNeeded()
    }

    // MARK: - Polling

    private func startPolling(generationId: String, projectId: String, projectTitle: String?) {
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.pollUntilFinished(
                generationId: generationId,
                projectId: projectId,
                projectTitle: projectTitle
            )
        }
        pollingTasks[generationId] = task
    }

    private func pollUntilFinished(
        generationId: String,
        projectId: String,
        projectTitle: String?
    ) async {
        // Always tidy up on exit, regardless of how the loop ends. The
        // backend startup-sweep cleanup catches anything truly stuck so
        // it's safe to drop client-side state on any terminal path.
        defer {
            pollingTasks.removeValue(forKey: generationId)
            store.remove(generationId: generationId)
            if pollingTasks.isEmpty {
                endBackgroundTaskIfNeeded()
            }
        }

        // 6 minutes covers the 60–130s typical PiAPI run plus the
        // GoogleGenAI fallback path with comfortable headroom. Beyond
        // that we hand off to the backend cleanup sweep that marks the
        // record FAILED so polling on a future cold launch terminates.
        let maxAttempts = 120
        let pollInterval: Double = 3
        var transientFailures = 0

        for _ in 0..<maxAttempts {
            if Task.isCancelled { return }
            try? await Task.sleep(for: .seconds(pollInterval))
            if Task.isCancelled { return }

            let snapshot: AIGeneration
            do {
                snapshot = try await generationService.getGenerationStatus(id: generationId)
                transientFailures = 0
            } catch is CancellationError {
                return
            } catch {
                // A blip shouldn't take down the run. Soft-fail up to a
                // streak of 5 (~15s of network trouble) before giving up.
                transientFailures += 1
                if transientFailures >= 5 { return }
                continue
            }

            switch snapshot.status {
            case .completed:
                handleCompletion(
                    generationId: generationId,
                    projectId: projectId,
                    projectTitle: projectTitle
                )
                return
            case .failed:
                handleFailure(
                    generationId: generationId,
                    projectId: projectId,
                    message: snapshot.errorMessage
                )
                return
            case .queued, .processing:
                continue
            }
        }
        // Loop exhausted without a terminal state. Drop silently — the
        // backend sweep is the safety net, and the user's next
        // navigation back into the project will hydrate fresh state.
    }

    private func handleCompletion(generationId: String, projectId: String, projectTitle: String?) {
        if currentScenePhase != .active {
            // Schedule with a 1s delay so the imminent foreground
            // transition (which might be milliseconds away if the user
            // is just tapping back into the app) has a window to cancel
            // a redundant notification before iOS delivers it.
            scheduledNotificationIDs.insert(generationId)
            Task {
                await notifications.scheduleReady(
                    generationId: generationId,
                    projectId: projectId,
                    projectTitle: projectTitle,
                    delay: 1
                )
            }
        } else {
            // Defensive: a previous run that ended in background may
            // have scheduled a still-pending notification under this
            // ID. Clear it so a delayed delivery doesn't surprise the
            // user later.
            notifications.cancel(generationId: generationId)
            scheduledNotificationIDs.remove(generationId)
        }
        eventsStream.continuation.yield(.completed(
            generationId: generationId,
            projectId: projectId
        ))
    }

    private func handleFailure(generationId: String, projectId: String, message: String?) {
        notifications.cancel(generationId: generationId)
        scheduledNotificationIDs.remove(generationId)
        eventsStream.continuation.yield(.failed(
            generationId: generationId,
            projectId: projectId,
            message: message
        ))
    }

    // MARK: - Background Task

    private func beginBackgroundTaskIfNeeded() {
        guard backgroundTaskID == .invalid, !pollingTasks.isEmpty else { return }
        // iOS grants ~30s of grace before suspending the process.
        // That's enough to catch an in-flight gen that's about to
        // complete; longer waits hand off to the (future) APNs path or
        // to the cold-launch resume.
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(
            withName: "GenerationPoll"
        ) { [weak self] in
            Task { @MainActor [weak self] in
                self?.endBackgroundTaskIfNeeded()
            }
        }
    }

    private func endBackgroundTaskIfNeeded() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    private func cancelStaleScheduledNotifications() {
        guard !scheduledNotificationIDs.isEmpty else { return }
        for id in scheduledNotificationIDs {
            notifications.cancel(generationId: id)
        }
        scheduledNotificationIDs.removeAll()
    }
}
