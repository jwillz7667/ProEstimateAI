import Foundation
import Observation

/// Tracks whether the authenticated user has completed the one-time onboarding flow.
///
/// The flag is persisted in `UserDefaults` under `Keys.completedV1`, scoped by version
/// so that future onboarding revisions can re-run for existing users by bumping the key.
/// It is read synchronously at app launch from `AuthGateView` to decide whether to show
/// `OnboardingFlowView` before the main tab interface.
@MainActor
@Observable
final class OnboardingStore {
    // MARK: - Shared Instance

    static let shared = OnboardingStore()

    // MARK: - Persistence Keys

    private enum Keys {
        static let completedV1 = "onboarding.completed.v1"
    }

    // MARK: - State

    private(set) var hasCompletedOnboarding: Bool

    // MARK: - Dependencies

    private let defaults: UserDefaults

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.completedV1)
    }

    // MARK: - Actions

    /// Persist completion of the onboarding flow. Called from the last page
    /// (or the Skip button) via the flow's `onComplete` closure.
    func markCompleted() {
        hasCompletedOnboarding = true
        defaults.set(true, forKey: Keys.completedV1)
    }

    /// Reset the completion flag. Intended for debug / QA flows only.
    func reset() {
        hasCompletedOnboarding = false
        defaults.removeObject(forKey: Keys.completedV1)
    }
}
