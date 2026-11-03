import Foundation

/// Exercises actual Home state without opening Simulator or making requests.
@main
@MainActor
struct DashboardRegressionTests {
    enum Failure: Error, CustomStringConvertible {
        case check(String)
        var description: String {
            switch self { case let .check(message): return message }
        }
    }

    static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else { throw Failure.check(message) }
    }

    static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0 ..< 1000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw Failure.check("Timed out waiting for a dashboard section")
    }

    static func main() async throws {
        try await projectsDoNotWaitForBusinessTotals()
        try await summarySurvivesProjectFailure()
        try await refreshPreservesSavedContent()
        try await cancelledLoadsCanBeRetried()
        try await staleWorkspaceResultsAreDiscarded()
        try await simultaneousLoadsAreCoalesced()
        try recentWorkIsDeterministic()
        try greetingHandlesMissingNames()
        print("PASS: \(checks) dashboard checks (independent sections, retry, cancellation, workspace changes, deterministic recent work).")
    }

    static func projectsDoNotWaitForBusinessTotals() async throws {
        let service = ControlledDashboardService()
        let model = DashboardViewModel(service: service)
        let load = Task { await model.loadDashboard(scope: "account-a:company-a") }
        try await service.waitForRequests(1)
        await service.finishProjects(0, .success([project("ready")]))
        try await waitUntil { model.hasLoadedProjects }
        try expect(model.recentProjects.map(\.id) == ["ready"], "Saved projects must appear before summary finishes")
        try expect(model.isLoadingSummary && !model.isLoadingProjects, "Section loading must be independent")
        await service.finishSummary(0, .failure(URLError(.notConnectedToInternet)))
        await load.value
        try expect(model.summaryErrorMessage != nil && model.projectsErrorMessage == nil, "Summary failure must stay in its own section")
        try expect(model.recentProjects.count == 1 && !model.isLoading, "Summary failure must never hide saved work")
    }

    static func summarySurvivesProjectFailure() async throws {
        let service = ControlledDashboardService()
        let model = DashboardViewModel(service: service)
        let load = Task { await model.loadDashboard(scope: "workspace") }
        try await service.waitForRequests(1)
        await service.finishSummary(0, .success(.sample))
        try await waitUntil { model.summary != nil }
        try expect(model.isLoadingProjects && !model.isLoadingSummary, "Business totals must render while projects are still loading")
        await service.finishProjects(0, .failure(URLError(.timedOut)))
        await load.value
        try expect(model.summary?.activeProjectsCount == DashboardSummary.sample.activeProjectsCount, "Project failure must preserve successful business totals")
        try expect(model.projectsErrorMessage != nil && !model.hasLoadedProjects, "Failed first load must not masquerade as an empty workspace")
    }

    static func refreshPreservesSavedContent() async throws {
        let service = ControlledDashboardService()
        let model = DashboardViewModel(service: service)
        let initial = Task { await model.loadDashboard(scope: "workspace") }
        try await service.waitForRequests(1)
        await service.finishSummary(0, .success(.sample))
        await service.finishProjects(0, .success([project("saved")]))
        await initial.value
        let refresh = Task { await model.loadDashboard(scope: "workspace") }
        try await service.waitForRequests(2)
        try expect(model.summary != nil && model.recentProjects.first?.id == "saved", "Refresh must keep existing content visible")
        await service.finishSummary(1, .failure(URLError(.notConnectedToInternet)))
        await service.finishProjects(1, .failure(URLError(.notConnectedToInternet)))
        await refresh.value
        try expect(model.summary != nil && model.recentProjects.first?.id == "saved", "Offline refresh must preserve the last successful content")
        try expect(model.summaryErrorMessage != nil && model.projectsErrorMessage != nil && model.hasLoadedProjects, "Stale content needs section-specific retry feedback")
    }

    static func cancelledLoadsCanBeRetried() async throws {
        let service = ControlledDashboardService()
        let model = DashboardViewModel(service: service)
        let cancelled = Task { await model.loadDashboard(scope: "workspace") }
        try await service.waitForRequests(1)
        cancelled.cancel()
        // The fake transport deliberately ignores task cancellation.
        await service.finishSummary(0, .success(.sample))
        await service.finishProjects(0, .success([project("cancelled-result")]))
        await cancelled.value
        try expect(!model.isLoading && model.summary == nil && model.recentProjects.isEmpty, "Cancelled results must not publish, and loading must settle")
        try expect(model.summaryErrorMessage == nil && model.projectsErrorMessage == nil, "Cancellation must not create a network error")
        let retry = Task { await model.loadDashboard(scope: "workspace") }
        try await service.waitForRequests(2)
        await service.finishSummary(1, .success(.empty))
        await service.finishProjects(1, .success([]))
        await retry.value
        try expect(model.hasLoadedProjects && model.summary != nil && !model.isLoading, "A cancelled first load must be retryable")

        let transportCancelled = Task { await model.loadDashboard(scope: "workspace") }
        try await service.waitForRequests(3)
        await service.finishSummary(2, .failure(CancellationError()))
        await service.finishProjects(2, .failure(URLError(.cancelled)))
        await transportCancelled.value
        try expect(model.summaryErrorMessage == nil && model.projectsErrorMessage == nil, "URLSession and Swift cancellation must both stay quiet")
    }

    static func staleWorkspaceResultsAreDiscarded() async throws {
        let service = ControlledDashboardService()
        let model = DashboardViewModel(service: service)
        let old = Task { await model.loadDashboard(scope: "account-a:company-a") }
        try await service.waitForRequests(1)
        await service.finishProjects(0, .success([project("private-a")]))
        try await waitUntil { model.hasLoadedProjects }
        let current = Task { await model.loadDashboard(scope: "account-b:company-b") }
        try await service.waitForRequests(2)
        try expect(model.recentProjects.isEmpty && model.summary == nil && !model.hasLoadedProjects, "Changing workspace must immediately clear the previous account's content")
        await service.finishSummary(1, .success(.empty))
        try await waitUntil { model.summary != nil }
        await service.finishSummary(0, .success(.sample))
        await old.value
        try expect(model.summary?.activeProjectsCount == 0 && model.isLoadingProjects, "Old completion and defer must not overwrite current data or stop its spinner")
        await service.finishProjects(1, .success([project("private-b")]))
        await current.value
        try expect(model.recentProjects.map(\.id) == ["private-b"] && !model.isLoading, "Only the current workspace's result may be displayed")
    }

    static func simultaneousLoadsAreCoalesced() async throws {
        let service = ControlledDashboardService()
        let model = DashboardViewModel(service: service)
        let initial = Task { await model.loadDashboard(scope: "workspace") }
        try await service.waitForRequests(1)
        await model.loadDashboard(scope: "workspace")
        let counts = await service.requestCounts
        try expect(counts.summary == 1 && counts.projects == 1, "Tab, event and pull-to-refresh triggers must not fan out duplicate requests")
        await service.finishSummary(0, .success(.empty))
        await service.finishProjects(0, .success([]))
        await initial.value
    }

    static func recentWorkIsDeterministic() throws {
        let values = [
            project("archived", updated: 100, status: .archived),
            project("b", updated: 50, created: 10),
            project("a", updated: 50, created: 10),
            project("newest", updated: 80),
            project("older", updated: 20),
            project("newest", updated: 30)
        ]
        let sorted = DashboardViewModel.recentWork(from: values)
        try expect(sorted.map(\.id) == ["newest", "a", "b"], "Recent work must sort by modification, then creation and stable ID, exclude archived work, deduplicate and cap at three")
        try expect(DashboardViewModel.recentWork(from: values.reversed()).map(\.id) == sorted.map(\.id), "API ordering must not affect tied rows")
        try expect(DashboardViewModel.recentWork(from: []).isEmpty, "An empty response must remain genuinely empty")
    }

    static func greetingHandlesMissingNames() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let morning = Date(timeIntervalSince1970: 8 * 3600)
        let model = DashboardViewModel(service: ControlledDashboardService())
        try expect(model.greeting(for: " \n ", at: morning, calendar: calendar) == "Good morning", "A missing name must not leave a dangling comma")
        try expect(model.greeting(for: "  Maria José ", at: morning, calendar: calendar) == "Good morning, Maria", "Names should trim surrounding whitespace")
        try expect(model.formattedRevenue == "—", "Unloaded revenue must not claim a zero balance")
    }

    static func project(_ id: String, updated: TimeInterval = 1, created: TimeInterval = 1, status: Project.Status = .draft) -> Project {
        Project(id: id, companyId: "company", clientId: nil, title: id, description: nil,
                projectType: .kitchen, status: status, budgetMin: nil, budgetMax: nil,
                squareFootage: nil, dimensions: nil, language: nil,
                createdAt: Date(timeIntervalSince1970: created), updatedAt: Date(timeIntervalSince1970: updated))
    }
}

actor ControlledDashboardService: DashboardDataProviding {
    private var summaryRequests: [Int: CheckedContinuation<DashboardSummary, Error>] = [:]
    private var projectRequests: [Int: CheckedContinuation<[Project], Error>] = [:]
    private var summaryCount = 0
    private var projectsCount = 0
    var requestCounts: (summary: Int, projects: Int) { (summaryCount, projectsCount) }

    func fetchSummary() async throws -> DashboardSummary {
        let id = summaryCount
        summaryCount += 1
        return try await withCheckedThrowingContinuation { summaryRequests[id] = $0 }
    }

    func fetchProjects() async throws -> [Project] {
        let id = projectsCount
        projectsCount += 1
        return try await withCheckedThrowingContinuation { projectRequests[id] = $0 }
    }

    func waitForRequests(_ count: Int) async throws {
        for _ in 0 ..< 1000 {
            if summaryCount >= count && projectsCount >= count { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw DashboardRegressionTests.Failure.check("Timed out waiting for fake requests")
    }

    func finishSummary(_ id: Int, _ result: Result<DashboardSummary, Error>) {
        summaryRequests.removeValue(forKey: id)?.resume(with: result)
    }

    func finishProjects(_ id: Int, _ result: Result<[Project], Error>) {
        projectRequests.removeValue(forKey: id)?.resume(with: result)
    }
}

// Resolve the unused production default while compiling only actual Home
// models/state. Every test above explicitly injects its controlled service.
struct DashboardService: DashboardDataProviding {
    func fetchSummary() async throws -> DashboardSummary { throw CancellationError() }
    func fetchProjects() async throws -> [Project] { throw CancellationError() }
}
