import Foundation

/// Mock API client for SwiftUI previews and unit tests.
/// Returns hardcoded sample data with a configurable delay to simulate
/// network latency. Conforms to `APIClientProtocol` so it can be
/// injected anywhere the real `APIClient` is used.
final class MockAPIClient: APIClientProtocol {
    /// Simulated network delay in nanoseconds. Defaults to 500ms.
    var delayNanoseconds: UInt64

    /// When set, all requests will throw this error instead of returning data.
    var forcedError: APIError?

    init(delayNanoseconds: UInt64 = 500_000_000) {
        self.delayNanoseconds = delayNanoseconds
        self.forcedError = nil
    }

    // MARK: - APIClientProtocol

    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        try await simulateDelay()

        if let error = forcedError {
            throw error
        }

        // Attempt to return sample data for the requested type.
        if let result = sampleData(for: T.self) {
            return result
        }

        throw APIError.unknown("MockAPIClient has no sample data for \(T.self)")
    }

    func request(_ endpoint: APIEndpoint) async throws {
        try await simulateDelay()

        if let error = forcedError {
            throw error
        }
        // Void endpoints succeed silently.
    }

    // MARK: - Delay Simulation

    private func simulateDelay() async throws {
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
    }

    // MARK: - Sample Data Registry

    /// Returns sample data for known types. Extend this function as new models are added.
    private func sampleData<T: Decodable>(for type: T.Type) -> T? {
        switch type {
        // Domain Models
        case is Company.Type:
            return Company.sample as? T
        case is User.Type:
            return User.sample as? T
        case is Client.Type:
            return Client.sample as? T
        case is [Client].Type:
            return [Client.sample] as? T
        case is Project.Type:
            return Project.sample as? T
        case is [Project].Type:
            return [Project.sample] as? T
        case is Asset.Type:
            return Asset.sample as? T
        case is [Asset].Type:
            return [Asset.sample] as? T
        case is AIGeneration.Type:
            return AIGeneration.sample as? T
        case is [AIGeneration].Type:
            return [AIGeneration.sample] as? T
        case is MaterialSuggestion.Type:
            return MaterialSuggestion.sample as? T
        case is [MaterialSuggestion].Type:
            return [MaterialSuggestion.sample] as? T
        case is Estimate.Type:
            return Estimate.sample as? T
        case is [Estimate].Type:
            return [Estimate.sample] as? T
        case is EstimateLineItem.Type:
            return EstimateLineItem.sample as? T
        case is [EstimateLineItem].Type:
            return [EstimateLineItem.sample] as? T
        case is Proposal.Type:
            return Proposal.sample as? T
        case is [Proposal].Type:
            return [Proposal.sample] as? T
        case is PricingProfile.Type:
            return PricingProfile.sample as? T
        case is [PricingProfile].Type:
            return [PricingProfile.sample] as? T
        case is LaborRateRule.Type:
            return LaborRateRule.sample as? T
        case is [LaborRateRule].Type:
            return [LaborRateRule.sample] as? T
        case is ActivityLogEntry.Type:
            return ActivityLogEntry.sample as? T
        case is [ActivityLogEntry].Type:
            return [ActivityLogEntry.sample] as? T

        // Commerce Models
        case is EntitlementSnapshot.Type:
            return EntitlementSnapshot.sampleFree as? T
        case is [StoreProductModel].Type:
            return [StoreProductModel.sampleMonthly, StoreProductModel.sampleAnnual] as? T
        case is PaywallDecision.Type:
            return PaywallDecision.sampleSoftGate as? T
        case is [UsageBucket].Type:
            return EntitlementSnapshot.sampleFree.usage as? T

        // Usage Check Response
        case is UsageCheckResponse.Type:
            return UsageCheckResponse(
                allowed: true,
                reason: nil,
                entitlement: .sampleFree,
                paywall: nil
            ) as? T

        default:
            return nil
        }
    }
}

// MARK: - Usage Check Response

/// Response from the `POST /v1/usage/check` endpoint.
/// Used by feature-gate coordinators to determine whether an action is allowed.
struct UsageCheckResponse: Codable, Sendable {
    let allowed: Bool
    let reason: String?
    let entitlement: EntitlementSnapshot
    let paywall: PaywallDecision?
}
