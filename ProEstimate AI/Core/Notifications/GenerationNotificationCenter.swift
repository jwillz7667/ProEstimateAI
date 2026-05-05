import Foundation
@preconcurrency import UserNotifications

/// User-facing notifications for the AI generation lifecycle.
///
/// Why a wrapper instead of using `UNUserNotificationCenter.current()`
/// directly from view models? Two reasons:
///
///   1. **Permission ergonomics.** We want to ask exactly once and track
///      the answer locally so subsequent calls don't re-request from a
///      decided user. The wrapper memoizes the resolved status so a
///      cold launch followed by a generation start doesn't re-prompt.
///
///   2. **Tap routing.** We expose the tap as an `AsyncStream` that the
///      App-level scene can subscribe to and translate into a navigation
///      action. The delegate runs on the system actor — the stream
///      hands the payload to MainActor land.
///
/// Notification taxonomy:
///
///   - **Identifier** = generation ID (CUID). Lets us cancel a pending
///     scheduled notification when the foreground poll wins, and replace
///     a "still processing" placeholder with a "ready now" trigger.
///   - **categoryIdentifier** = `"generation-ready"`. Reserved for
///     future actionable notifications (e.g., "View preview" inline).
///   - **userInfo** carries `projectId`, `generationId`, and `projectTitle`
///     so the tap handler can deep-link to the right project.
@MainActor
final class GenerationNotificationCenter: NSObject {
    static let shared = GenerationNotificationCenter()

    /// The category every generation notification ships under. Reserved
    /// for actionable extensions (View / Dismiss buttons) without
    /// requiring identifier refactors.
    static let categoryIdentifier = "generation-ready"

    /// userInfo keys — kept as constants so the notification producer
    /// and the tap consumer can't disagree on spelling.
    enum InfoKey {
        static let projectId = "project_id"
        static let generationId = "generation_id"
        static let projectTitle = "project_title"
    }

    /// Payload delivered when the user taps a notification. Consumed by
    /// the App-level scene which translates it into an AppRouter push.
    struct TapPayload: Sendable {
        let projectId: String
        let generationId: String
        let projectTitle: String?
    }

    private let center = UNUserNotificationCenter.current()
    private var taps = AsyncStream<TapPayload>.makeStream()
    private var permissionResolved: UNAuthorizationStatus?

    /// Stream of taps. The App scene awaits this in a long-running task
    /// and dispatches navigations on each emit. Survives across App
    /// lifecycle transitions because the singleton outlives the scene.
    nonisolated var tapStream: AsyncStream<TapPayload> {
        // Re-enter the actor only to read the iVar; the stream itself
        // is `Sendable` so handing it out from a nonisolated reader is
        // safe.
        MainActor.assumeIsolated { taps.stream }
    }

    override init() {
        super.init()
    }

    /// Wire the system-level delegate so taps and foreground
    /// presentation route through us. Must be called from `App.init()`
    /// — Apple docs require the delegate be set before
    /// `applicationDidFinishLaunching`, otherwise launch-from-tap is
    /// silently dropped.
    func bootstrap() {
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.categoryIdentifier,
                actions: [],
                intentIdentifiers: [],
                options: []
            )
        ])
    }

    /// Idempotent permission request. Resolves to `true` if the user
    /// has authorized any visible / sound / badge alert, `false`
    /// otherwise. Repeat calls don't re-prompt — once iOS records a
    /// `.denied` or `.authorized`, we just read the cached state.
    ///
    /// Side effect: on `.authorized`-class outcomes we also kick off
    /// remote-notification registration via `ApnsRegistrar`, so the
    /// device starts producing an APNs token the moment the user grants
    /// alerts. APNs registration must follow user authorization, never
    /// precede it — registering a device that hasn't authorized alerts
    /// is technically allowed but nets us nothing because the backend
    /// will only ever try to deliver visible alert payloads.
    @discardableResult
    func requestPermissionIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        permissionResolved = settings.authorizationStatus
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            await ApnsRegistrar.bootstrapIfPermitted()
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [
                    .alert, .sound, .badge,
                ])
                permissionResolved = granted ? .authorized : .denied
                if granted {
                    await ApnsRegistrar.bootstrapIfPermitted()
                }
                return granted
            } catch {
                permissionResolved = .denied
                return false
            }
        @unknown default:
            return false
        }
    }

    /// Schedule (or replace) a "your AI preview is ready" notification
    /// for `generationId`. Uses the generation ID as the request
    /// identifier so a subsequent call replaces the prior schedule
    /// instead of stacking duplicates.
    ///
    /// `delay` lets the lifecycle coordinator pick the right cadence:
    /// at generation start, schedule a fallback ~3 minutes out so the
    /// user sees something even if the foreground poll dies. When the
    /// background poll detects completion, replace with `delay = 1` so
    /// the notification fires immediately.
    func scheduleReady(
        generationId: String,
        projectId: String,
        projectTitle: String?,
        delay: TimeInterval
    ) async {
        guard await requestPermissionIfNeeded() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Preview ready"
        content.body =
            projectTitle.map { "Your \($0) AI preview is ready to review." }
                ?? "Your AI preview is ready to review."
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [
            InfoKey.projectId: projectId,
            InfoKey.generationId: generationId,
            InfoKey.projectTitle: projectTitle ?? "",
        ]
        // `threadIdentifier` groups notifications per project so a user
        // running multiple in-flight generations sees them clustered in
        // Notification Center instead of as a flat stream.
        content.threadIdentifier = "project:\(projectId)"

        // UNTimeIntervalNotificationTrigger requires > 0; clamp to 1s
        // for "fire now" callers without an extra branch in the API.
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(delay, 1),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: generationId,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
        } catch {
            // Permission revoked between settings read and add; nothing
            // we can do, the user will see the in-app UI when they
            // return.
        }
    }

    /// Cancel any pending and delivered notification for this gen.
    /// Called when the foreground poll wins so the user doesn't get a
    /// "ready now" toast 30 seconds after they already saw it.
    func cancel(generationId: String) {
        center.removePendingNotificationRequests(withIdentifiers: [generationId])
        center.removeDeliveredNotifications(withIdentifiers: [generationId])
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension GenerationNotificationCenter: UNUserNotificationCenterDelegate {
    /// In-foreground presentation: suppress the system banner — the
    /// in-app UI is already live and showing the completion state, so a
    /// banner over top would be redundant noise.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (
            UNNotificationPresentationOptions
        ) -> Void
    ) {
        completionHandler([])
    }

    /// User tapped the notification: extract userInfo, push onto the
    /// tap stream so the App scene can navigate.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let projectId = info[InfoKey.projectId] as? String
        let generationId = info[InfoKey.generationId] as? String
        let projectTitle = info[InfoKey.projectTitle] as? String

        if let projectId, let generationId {
            let payload = TapPayload(
                projectId: projectId,
                generationId: generationId,
                projectTitle: (projectTitle?.isEmpty == false) ? projectTitle : nil
            )
            // Delegate runs off-actor; bounce to the singleton's
            // continuation on MainActor so consumers don't have to
            // reason about concurrency.
            Task { @MainActor in
                GenerationNotificationCenter.shared.taps.continuation.yield(payload)
            }
        }
        completionHandler()
    }
}
