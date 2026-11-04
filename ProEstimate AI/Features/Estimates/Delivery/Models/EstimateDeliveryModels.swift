import Foundation

protocol EstimateDeliveryServing: Sendable {
    func getProject(id: String) async throws -> Project
    func getClient(id: String) async throws -> Client
    func assignClient(projectId: String, clientId: String) async throws -> Project
    func listProposals(projectId: String) async throws -> [Proposal]
    func createProposal(estimateId: String) async throws -> Proposal
    func reviseEstimate(estimateId: String, requestId: String) async throws -> Estimate
    func listInvoices(projectId: String) async throws -> [Invoice]
    func convertToInvoice(estimateId: String) async throws -> Invoice
}

struct EstimateRevisionRequest: Encodable, Sendable {
    let requestId: String
    enum CodingKeys: String, CodingKey { case requestId = "request_id" }
}
