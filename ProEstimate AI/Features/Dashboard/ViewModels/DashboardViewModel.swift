import Foundation
import Observation

protocol DashboardDataProviding: Sendable {
    func fetchSummary() async throws -> DashboardSummary
    func fetchProjects() async throws -> [Project]
    func fetchAttention() async throws -> DashboardAttention
}

@MainActor
@Observable
final class DashboardViewModel {
    private(set) var summary: DashboardSummary?
    private(set) var attention: DashboardAttention?
    private(set) var recentProjects: [Project] = []
    private(set) var isLoadingSummary = false
    private(set) var isLoadingProjects = false
    private(set) var hasLoadedProjects = false
    private(set) var summaryErrorMessage: String?
    private(set) var projectsErrorMessage: String?
    private(set) var attentionErrorMessage: String?
    private(set) var isLoadingAttention = false

    var isLoading: Bool { isLoadingSummary || isLoadingProjects || isLoadingAttention }

    private let service: any DashboardDataProviding
    private var currentScope: String?
    private var requestRevision = 0

    init(service: any DashboardDataProviding = DashboardService()) {
        self.service = service
    }

    func greeting(for name: String, at date: Date = Date(), calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let greeting: String
        switch hour {
        case 0 ..< 12: greeting = "Good morning"
        case 12 ..< 17: greeting = "Good afternoon"
        default: greeting = "Good evening"
        }
        guard let firstName = name.split(whereSeparator: \.isWhitespace).first else { return greeting }
        return "\(greeting), \(firstName)"
    }

    var formattedRevenue: String {
        guard let amounts = summary?.settledInvoiceAmounts else { return "—" }
        return amounts.isEmpty ? DashboardMoney(currencyCode: "USD", amount: 0).formatted
            : amounts.map(\.formatted).joined(separator: " + ")
    }

    /// Loads each section independently. A slow or failed summary never hides
    /// projects, and a refresh failure preserves the last successful content.
    func loadDashboard(scope: String) async {
        if currentScope != scope {
            currentScope = scope
            requestRevision &+= 1
            summary = nil
            attention = nil
            recentProjects = []
            hasLoadedProjects = false
            isLoadingSummary = false
            isLoadingProjects = false
            isLoadingAttention = false
            summaryErrorMessage = nil
            projectsErrorMessage = nil
            attentionErrorMessage = nil
        }
        guard !isLoading else { return }
        requestRevision &+= 1
        let revision = requestRevision
        isLoadingSummary = true
        isLoadingProjects = true
        isLoadingAttention = true
        summaryErrorMessage = nil
        projectsErrorMessage = nil
        attentionErrorMessage = nil
        defer {
            if revision == requestRevision {
                isLoadingSummary = false
                isLoadingProjects = false
                isLoadingAttention = false
            }
        }

        let service = service
        await withTaskGroup(of: SectionResult.self) { group in
            group.addTask {
                do { return .summary(.success(try await service.fetchSummary())) }
                catch { return .summary(.failure(LoadFailure(error))) }
            }
            group.addTask {
                do { return .projects(.success(try await service.fetchProjects())) }
                catch { return .projects(.failure(LoadFailure(error))) }
            }
            group.addTask {
                do { return .attention(.success(try await service.fetchAttention())) }
                catch { return .attention(.failure(LoadFailure(error))) }
            }
            for await result in group {
                // An account/workspace change supersedes every earlier result,
                // even if its transport ignores Swift task cancellation.
                guard revision == requestRevision, !Task.isCancelled else { continue }
                switch result {
                case let .attention(.success(value)):
                    attention = value
                    isLoadingAttention = false
                case .attention(.failure(.cancelled)):
                    isLoadingAttention = false
                case .attention(.failure(.unavailable)):
                    attentionErrorMessage = "Next actions couldn't be refreshed. Refresh before acting on saved information."
                    isLoadingAttention = false
                case let .summary(.success(value)):
                    summary = value
                    isLoadingSummary = false
                case .summary(.failure(.cancelled)):
                    isLoadingSummary = false
                case .summary(.failure(.unavailable)):
                    summaryErrorMessage = "Business totals couldn't be refreshed."
                    isLoadingSummary = false
                case let .projects(.success(values)):
                    recentProjects = Self.recentWork(from: values)
                    hasLoadedProjects = true
                    isLoadingProjects = false
                case .projects(.failure(.cancelled)):
                    isLoadingProjects = false
                case .projects(.failure(.unavailable)):
                    projectsErrorMessage = "Your projects couldn't be refreshed. Try again when you're connected."
                    isLoadingProjects = false
                }
            }
        }
    }

    /// Keep Home small and predictable. Archived work remains in Projects;
    /// duplicate API rows cannot create duplicate NavigationLink identities.
    static func recentWork(from projects: [Project]) -> [Project] {
        let sorted = projects.filter { $0.status != .archived }.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id < $1.id
        }
        var seen: Set<String> = []
        return Array(sorted.filter { seen.insert($0.id).inserted }.prefix(3))
    }

    private enum SectionResult: Sendable {
        case summary(Result<DashboardSummary, LoadFailure>)
        case projects(Result<[Project], LoadFailure>)
        case attention(Result<DashboardAttention, LoadFailure>)
    }

    private enum LoadFailure: Error, Sendable {
        case cancelled
        case unavailable

        init(_ error: Error) {
            self = error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled
                ? .cancelled : .unavailable
        }
    }
}
