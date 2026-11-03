import Foundation

protocol EstimateEditing: Sendable {
    func getEstimate(id: String) async throws -> Estimate
    func getLineItems(estimateId: String) async throws -> [EstimateLineItem]
    func addLineItem(estimateId: String, request: EstimateLineItemEditRequest) async throws
    func updateLineItem(id: String, request: EstimateLineItemEditRequest) async throws
    func removeLineItem(id: String) async throws
}
