import Foundation

private struct CustomerPaymentOnboardingRequest: Encodable, Sendable { let country: String }
private struct CustomerPaymentOnboardingResponse: Decodable { let url: URL }

struct CustomerPaymentSettingsService: CustomerPaymentSettingsServing {
    private let api: any APIClientProtocol
    init(api: any APIClientProtocol = APIClient.shared) { self.api = api }

    func status() async throws -> CustomerPaymentSettingsSnapshot {
        try await api.request(.getMerchantPaymentSettings)
    }

    func onboarding(country: String) async throws -> URL {
        let result: CustomerPaymentOnboardingResponse = try await api.request(.startMerchantPaymentOnboarding(body: CustomerPaymentOnboardingRequest(country: country)))
        return result.url
    }
}
