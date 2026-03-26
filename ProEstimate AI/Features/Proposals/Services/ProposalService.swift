import Foundation

// MARK: - Protocol

protocol ProposalServiceProtocol: Sendable {
    func listProposals() async throws -> [Proposal]
    func getProposal(id: String) async throws -> Proposal
    func getProposalEstimate(proposalId: String) async throws -> Estimate
    func getProposalLineItems(estimateId: String) async throws -> [EstimateLineItem]
    func getProposalProject(projectId: String) async throws -> Project
    func getProposalClient(clientId: String) async throws -> Client
    func getProposalCompany(companyId: String) async throws -> Company
    func generateFromEstimate(estimateId: String) async throws -> Proposal
    func createProposal(_ proposal: Proposal) async throws -> Proposal
    func updateProposal(_ proposal: Proposal) async throws -> Proposal
    func deleteProposal(id: String) async throws
    func sendProposal(id: String) async throws -> Proposal
}

// MARK: - Mock Implementation

final class MockProposalService: ProposalServiceProtocol {
    private let simulatedDelay: UInt64 = 500_000_000

    func listProposals() async throws -> [Proposal] {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return Self.sampleProposals
    }

    func getProposal(id: String) async throws -> Proposal {
        try await Task.sleep(nanoseconds: simulatedDelay)
        guard let proposal = Self.sampleProposals.first(where: { $0.id == id }) else {
            throw ProposalServiceError.notFound
        }
        return proposal
    }

    func getProposalEstimate(proposalId: String) async throws -> Estimate {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return Estimate.sample
    }

    func getProposalLineItems(estimateId: String) async throws -> [EstimateLineItem] {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return MockEstimateService.sampleLineItems.filter { $0.estimateId == estimateId }
    }

    func getProposalProject(projectId: String) async throws -> Project {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return Project.sample
    }

    func getProposalClient(clientId: String) async throws -> Client {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return Client.sample
    }

    func getProposalCompany(companyId: String) async throws -> Company {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return Company.sample
    }

    func generateFromEstimate(estimateId: String) async throws -> Proposal {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return Self.sampleProposals[0]
    }

    func createProposal(_ proposal: Proposal) async throws -> Proposal {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return proposal
    }

    func updateProposal(_ proposal: Proposal) async throws -> Proposal {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return proposal
    }

    func deleteProposal(id: String) async throws {
        try await Task.sleep(nanoseconds: simulatedDelay)
    }

    func sendProposal(id: String) async throws -> Proposal {
        try await Task.sleep(nanoseconds: simulatedDelay)
        return Proposal(
            id: id,
            estimateId: "e-001",
            projectId: "p-001",
            companyId: "c-001",
            status: .sent,
            shareToken: "abc123def456",
            heroImageURL: URL(string: "https://cdn.proestimate.ai/gen/gen-001.jpg"),
            termsAndConditions: "50% deposit required. Balance due upon completion.",
            clientMessage: "Hi Sarah, here is your kitchen remodel proposal.",
            sentAt: Date(),
            viewedAt: nil,
            respondedAt: nil,
            expiresAt: Calendar.current.date(byAdding: .day, value: 30, to: Date()),
            createdAt: Date()
        )
    }
}

// MARK: - Errors

enum ProposalServiceError: LocalizedError {
    case notFound
    case sendFailed
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .notFound: "Proposal not found."
        case .sendFailed: "Failed to send proposal. Please try again."
        case .generationFailed: "Failed to generate proposal from estimate."
        }
    }
}

// MARK: - Sample Data

extension MockProposalService {
    static let sampleProposals: [Proposal] = [
        Proposal(
            id: "prop-001",
            estimateId: "e-001",
            projectId: "p-001",
            companyId: "c-001",
            status: .draft,
            shareToken: "abc123def456",
            heroImageURL: URL(string: "https://cdn.proestimate.ai/gen/gen-001.jpg"),
            termsAndConditions: "50% deposit required upon approval. Balance due upon completion. Work guaranteed for 1 year. Changes to scope may affect pricing and timeline.",
            clientMessage: "Hi Sarah, here is your kitchen remodel proposal. We're excited to transform your space!",
            sentAt: nil,
            viewedAt: nil,
            respondedAt: nil,
            expiresAt: Calendar.current.date(byAdding: .day, value: 30, to: Date()),
            createdAt: Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        ),
        Proposal(
            id: "prop-002",
            estimateId: "e-002",
            projectId: "p-002",
            companyId: "c-001",
            status: .sent,
            shareToken: "xyz789ghi012",
            heroImageURL: URL(string: "https://cdn.proestimate.ai/gen/gen-002.jpg"),
            termsAndConditions: "50% deposit required. Balance due upon completion.",
            clientMessage: "Hello, please review the attached proposal for your bathroom remodel.",
            sentAt: Calendar.current.date(byAdding: .day, value: -1, to: Date()),
            viewedAt: nil,
            respondedAt: nil,
            expiresAt: Calendar.current.date(byAdding: .day, value: 14, to: Date()),
            createdAt: Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        ),
        Proposal(
            id: "prop-003",
            estimateId: "e-003",
            projectId: "p-003",
            companyId: "c-001",
            status: .approved,
            shareToken: "lmn345opq678",
            heroImageURL: nil,
            termsAndConditions: "Standard terms apply.",
            clientMessage: nil,
            sentAt: Calendar.current.date(byAdding: .day, value: -10, to: Date()),
            viewedAt: Calendar.current.date(byAdding: .day, value: -8, to: Date()),
            respondedAt: Calendar.current.date(byAdding: .day, value: -5, to: Date()),
            expiresAt: Calendar.current.date(byAdding: .day, value: 20, to: Date()),
            createdAt: Calendar.current.date(byAdding: .day, value: -12, to: Date())!
        ),
    ]
}
