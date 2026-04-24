import AVFoundation
import Foundation
import Observation

/// Drives the 3-page onboarding flow. Owns the current page index and the
/// camera-permission request on the final page. The flow itself is
/// single-use — completion is persisted via `OnboardingStore`.
@MainActor
@Observable
final class OnboardingViewModel {
    // MARK: - Page Definitions

    /// The ordered pages of the onboarding flow.
    enum Page: Int, CaseIterable, Identifiable {
        case welcome
        case valueProp
        case permissions
        case offer // Subscription trial offer — last step before reaching the app.

        var id: Int { rawValue }

        /// Zero-based index of the next page, or `nil` if this is the last page.
        var next: Page? {
            Page(rawValue: rawValue + 1)
        }

        /// Whether this page is the final page in the flow.
        var isLast: Bool {
            next == nil
        }
    }

    // MARK: - State

    var currentPage: Page = .welcome
    private(set) var isRequestingPermission: Bool = false

    // MARK: - Navigation

    /// Advance to the next page if one exists. Callers should check
    /// `currentPage.isLast` when they need to branch on terminal state
    /// (e.g. the permission page's Continue button advances to the offer).
    func advance() {
        guard let next = currentPage.next else { return }
        currentPage = next
    }

    // MARK: - Camera Permission

    /// Trigger the iOS camera permission system prompt. Resolves regardless
    /// of the user's decision — the caller is expected to mark onboarding
    /// complete after this returns, per product requirements.
    func requestCameraAccess() async {
        // If the user has already answered, AVFoundation resolves immediately
        // without showing a prompt, which is exactly the behavior we want.
        guard !isRequestingPermission else { return }
        isRequestingPermission = true
        _ = await AVCaptureDevice.requestAccess(for: .video)
        isRequestingPermission = false
    }
}
