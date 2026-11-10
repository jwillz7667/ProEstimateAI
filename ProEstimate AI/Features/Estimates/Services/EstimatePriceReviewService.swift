import Foundation

struct EstimatePriceReviewService: EstimatePriceReviewServing {
    let apiClient: any APIClientProtocol
    init(apiClient: any APIClientProtocol = APIClient.shared) { self.apiClient = apiClient }
    func review(itemId: String, request: EstimatePriceReviewRequest) async throws -> EstimateLineItem {
        try await apiClient.request(.reviewEstimatePrice(id: itemId, body: request))
    }
}
