import Foundation
import UIKit
@preconcurrency import UserNotifications
import os.log

/// Coordinates Apple Push Notification service registration so the
/// backend can deliver "your AI preview is ready" alerts even when the
/// app is killed.
///
/// Why an AppDelegate at all in a SwiftUI app? Because UNUserNotificationCenter
/// can fire a notification tap without an AppDelegate, but
/// `registerForRemoteNotifications()` callbacks (`didRegister...DeviceToken`
/// and `didFailToRegisterForRemoteNotificationsWithError`) only land on a
/// classic UIApplicationDelegate. SwiftUI's `UIApplicationDelegateAdaptor`
/// is the supported bridge — a tiny NSObject delegate keeps the rest of
/// the app SwiftUI-native.
///
/// Registration is intentionally cheap to call on every launch:
///
///   - APNs returns the same token for a given (device, app) install
///     until the user reinstalls or migrates devices, so reposting an
///     unchanged token is a server-side no-op (the backend `upsert` keyed
///     on `token`).
///   - Calling `registerForRemoteNotifications()` early gives APNs time
///     to refresh the token before the user triggers their first
///     generation, which is the only place we strictly need it.
///
/// This file does NOT request notification permission. That's
/// `GenerationNotificationCenter.requestPermissionIfNeeded()` — we want
/// the prompt tied to a generation start, not the cold-launch splash.
/// Once permission has been granted, `bootstrapIfPermitted()` flips on
/// remote registration; `registerForRemoteNotifications()` itself does
/// not surface a UI prompt, so it's safe to call any time.
enum ApnsRegistrar {
    private static let logger = Logger(
        subsystem: AppConstants.bundleID,
        category: "apns"
    )

    /// Inspect notification settings; if the user has authorized alerts,
    /// kick the system into asking APNs for a fresh token. The system
    /// then dispatches `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`
    /// on `ApnsAppDelegate` (see below).
    ///
    /// Idempotent: calling this when permission is denied or
    /// not-yet-determined is a no-op. The notification permission flow
    /// owns the prompt.
    @MainActor
    static func bootstrapIfPermitted() async {
        let settings = await UNUserNotificationCenter.current()
            .notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
        case .denied, .notDetermined:
            return
        @unknown default:
            return
        }
    }

    /// Convert the raw `Data` device token APNs hands back into the
    /// 64-character hex string the backend expects. Apple's reference
    /// formatter; lowercased to keep the string canonical so the
    /// backend's unique index doesn't see two rows for the same device.
    static func hexString(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// Post the freshly minted token to the backend. Best-effort —
    /// failures are logged but do not surface to the user, since the
    /// in-app polling path remains the canonical delivery channel and
    /// APNs is a reliability layer on top.
    static func register(token: String) {
        Task {
            do {
                try await APIClient.shared.request(
                    .registerApnsToken(
                        token: token,
                        bundleId: AppConstants.bundleID
                    )
                )
                logger.info("APNs token registered with backend")
            } catch {
                logger.error(
                    "APNs token registration failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    /// Best-effort deregister on sign-out. Backend treats missing rows
    /// as a no-op so this is safe to fire even when the device never
    /// successfully registered (e.g., user denied permission). Sign-out
    /// flows should call this *before* clearing the auth token — the
    /// endpoint is auth-required, so running it after `signOut()` would
    /// 401.
    static func deregister(token: String) {
        Task {
            do {
                try await APIClient.shared.request(
                    .deregisterApnsToken(token: token)
                )
                logger.info("APNs token deregistered")
            } catch {
                logger.warning(
                    "APNs token deregister failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }
}

/// Minimal UIApplicationDelegate that exists solely to capture the APNs
/// device token. SwiftUI wires this in via `@UIApplicationDelegateAdaptor`
/// from the `App` body.
final class ApnsAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let hex = ApnsRegistrar.hexString(from: deviceToken)
        ApnsRegistrar.register(token: hex)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Common in the simulator (no APNs sandbox) and on devices
        // without internet at launch. The next call to
        // `registerForRemoteNotifications()` — e.g., when the user
        // grants permission for a generation — will retry transparently.
        Logger(subsystem: AppConstants.bundleID, category: "apns").warning(
            "APNs registration failed: \(error.localizedDescription, privacy: .public)"
        )
    }
}
