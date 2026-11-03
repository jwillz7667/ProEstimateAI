import Foundation

@main
@MainActor
struct JobCostRegressionTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static var checks = 0
    static let scope = EstimateDraftScope(userId: "user-a", companyId: "company-a")

    static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard value() else { throw Failure(description: message) }
    }

    static func main() async throws {
        try validationAndDateReplay()
        try await savedCostWithFailedReceipt()
        try await unconfirmedAndRestartedCost()
        try await storageFailureAndReaderRole()
        try await pagingAndHistory()
        try await actualFilesAndProtectedJournal()
        print("PASS: \(checks) job cost checks (currency separation, whole-second idempotency, saved-cost receipt recovery, safe replay, read-only roles, pagination, audit history and private previews).")
    }

    static func draft() -> JobCostDraft {
        var draft = JobCostDraft()
        draft.description = "  Paint for hallway  "
        draft.amount = "33.33"
        draft.recordedAt = Date(timeIntervalSince1970: 1_790_000_000.987654)
        return draft
    }

    static func entry(request: JobCostRequest, id: String = "cost-a", receipt: Bool = false, voided: Bool = false) -> JobCostEntry {
        var original = (request.laborHours ?? 0) * (request.hourlyRate ?? 0)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &original, 2, .plain)
        return JobCostEntry(id: id, projectId: "project-a", requestId: request.requestId, category: request.category,
            description: request.description, amount: request.amount ?? rounded, currencyCode: request.currencyCode,
            laborHours: request.laborHours, hourlyRate: request.hourlyRate, recordedAt: request.recordedAt,
            createdAt: Date(), voidedAt: voided ? Date() : nil, receiptFilename: receipt ? "Receipt.pdf" : nil,
            receiptMimeType: receipt ? "application/pdf" : nil)
    }

    static func summary() -> JobCostSummary {
        JobCostSummary(currencyCode: "USD", estimateNumber: "EST-1", estimateStatus: "approved", quoteBeforeTax: 200,
            estimatedItemCost: 100, recordedCost: Decimal(string: "33.33")!, quoteLessRecordedCost: Decimal(string: "166.67")!,
            costsByCurrency: [JobCostSummary.CurrencyCosts(currencyCode: "USD", materials: Decimal(string: "33.33")!, labor: 0, other: 0, total: Decimal(string: "33.33")!),
                JobCostSummary.CurrencyCosts(currencyCode: "EUR", materials: 10, labor: 0, other: 0, total: 10)])
    }

    static func validationAndDateReplay() throws {
        let id = UUID().uuidString.lowercased()
        let request = draft().request(id: id)!
        try expect(request.description == "Paint for hallway" && request.amount == Decimal(string: "33.33"), "Actual costs must trim descriptions and retain exact money")
        try expect(request.recordedAt.timeIntervalSince1970 == 1_790_000_000, "Normalize dates to whole seconds before journaling and sending")
        let restored = try JSONDecoder().decode(JobCostRequest.self, from: JSONEncoder().encode(request))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let before = try JSONSerialization.jsonObject(with: encoder.encode(request)) as! [String: Any]
        let after = try JSONSerialization.jsonObject(with: encoder.encode(restored)) as! [String: Any]
        try expect(before["recorded_at"] as? String == after["recorded_at"] as? String && restored == request, "Restored request timestamps must produce the same backend payload hash")
        try expect(draft().request(id: "not-a-uuid") == nil, "Cost idempotency keys must be UUIDs")
        for value in ["0", "-1", "1.001", "10000000000", "12 dollars", "NaN"] {
            var invalid = draft(); invalid.amount = value
            try expect(invalid.validationMessage != nil, "Invalid actual costs cannot be recorded: \(value)")
        }
        var labor = draft()
        labor.category = "labor"; labor.useHours = true; labor.laborHours = "2.5"; labor.hourlyRate = "20.01"
        let hours = labor.request(id: id)!
        try expect(hours.amount == nil && hours.laborHours == Decimal(string: "2.5") && hours.hourlyRate == Decimal(string: "20.01"), "Hourly labor sends inputs and leaves its calculated cost to the server")
        labor.laborHours = "100000.01"
        try expect(labor.validationMessage != nil, "Labor hours must stay within server bounds")
        var currency = draft(); currency.currencyCode = "usd"
        try expect(currency.validationMessage != nil, "Currency codes must be explicit uppercase codes")
        currency.currencyCode = "EUR"
        try expect(currency.request(id: id)?.currencyCode == "EUR", "Foreign costs must keep their own currency")
        let invalidFile = JobCostReceiptAttachment(data: Data("not pdf".utf8), mimeType: "application/pdf", filename: "Receipt.pdf")
        try expect(invalidFile.validationMessage != nil, "Receipt file types must match their contents")
    }

    private static func model(_ service: CostFakeService, journal: CostFakeJournal = CostFakeJournal(), canEdit: Bool = true) async -> JobCostViewModel {
        let model = JobCostViewModel(projectId: "project-a", service: service, journal: journal)
        await model.load(scope: scope, canEdit: canEdit)
        return model
    }

    static func savedCostWithFailedReceipt() async throws {
        let service = CostFakeService()
        let journal = CostFakeJournal()
        let model = await model(service, journal: journal)
        let attachment = JobCostReceiptAttachment(data: Data("%PDF-1.4\n%%EOF".utf8), mimeType: "application/pdf", filename: "Receipt.pdf")
        service.failAttachment = true
        let saved = await model.save(draft: draft(), receipt: attachment)
        try expect(saved && model.savedEntry?.id == "cost-1", "A receipt failure must preserve the confirmed saved cost")
        try expect(model.receiptError != nil && service.requests.count == 1 && journal.pending == nil, "Missing attachment must not leave a second cost creation pending")
        service.failAttachment = false
        let attached = await model.attachReceipt(to: model.savedEntry!, attachment: attachment)
        try expect(attached && service.requests.count == 1 && service.attachmentCalls == 2, "Retrying attachment must not create the expense again")
    }

    static func unconfirmedAndRestartedCost() async throws {
        let service = CostFakeService()
        let journal = CostFakeJournal()
        let model = await model(service, journal: journal)
        service.commitThenFail = true
        let first = await model.save(draft: draft(), receipt: nil)
        try expect(!first && model.pending != nil && !model.canAdd, "A lost create response must freeze the persisted cost body")
        let original = journal.pending!.request
        let replay = await model.retryPending()
        try expect(replay && service.requests.count == 2 && service.requests[0] == service.requests[1], "Retrying must retain the original UUID and whole-second date")
        try expect(service.entries.count == 1 && model.pending == nil, "Idempotent replay must not count the cost twice")
        service.failBeforeCreate = true
        _ = await model.save(draft: draft(), receipt: nil)
        let pending = journal.pending!
        let restarted = await self.model(service, journal: journal)
        try expect(restarted.pending?.request == pending.request, "App restart must recover the exact cost request")
        service.failBeforeCreate = false
        let restored = await restarted.retryPending()
        try expect(restored && service.requests.last?.requestId == pending.request.requestId, "Restart recovery must reuse the original key")
        try expect(original.recordedAt.timeIntervalSince1970 == floor(original.recordedAt.timeIntervalSince1970), "Frozen timestamps cannot retain discarded subsecond precision")
    }

    static func storageFailureAndReaderRole() async throws {
        let service = CostFakeService()
        let journal = CostFakeJournal()
        let model = await model(service, journal: journal)
        journal.failSave = true
        let blocked = await model.save(draft: draft(), receipt: nil)
        try expect(!blocked && service.requests.isEmpty, "A failed pending journal must prevent a cost POST")
        let viewer = await self.model(service, canEdit: false)
        let readOnly = await viewer.save(draft: draft(), receipt: nil)
        try expect(!readOnly && !viewer.canAdd && service.requests.isEmpty, "Read-only users must not attempt cost mutations")
        journal.failSave = false
        journal.failLoad = true
        await model.load(scope: scope, canEdit: true)
        try expect(model.journalNeedsAttention && !model.canAdd, "A corrupt journal blocks another potentially duplicate cost")
    }

    static func pagingAndHistory() async throws {
        let service = CostFakeService()
        let request = draft().request(id: UUID().uuidString.lowercased())!
        service.entries = [entry(request: request, id: "1"), entry(request: request, id: "2"), entry(request: request, id: "3", voided: true)]
        service.pageSize = 1
        let model = await model(service)
        try expect(model.entries.count == 1 && model.nextCursor != nil, "Cost history should load incrementally")
        await model.loadMore()
        try expect(model.entries.count == 2 && model.nextCursor == nil, "Pagination preserves all active entries without repeated rows")
        await model.load(scope: scope, canEdit: true, includeVoided: true)
        await model.loadMore(); await model.loadMore()
        try expect(model.entries.count == 3 && model.entries.contains(where: { $0.voidedAt != nil }), "The history toggle must expose retained voided rows")
        try expect(model.summary?.costsByCurrency.count == 2 && model.summary?.recordedCost == Decimal(string: "33.33"), "Per-currency summaries are authoritative and must not sum currencies together")
    }

    static func actualFilesAndProtectedJournal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("proestimate-jobcost-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EstimateDraftStore(directory: directory.appendingPathComponent("journal"))
        let journal = JobCostPendingJournal(store: store)
        let value = JobCostPending(scope: scope, projectId: "project-a", request: draft().request(id: UUID().uuidString.lowercased())!, receiptExpected: true)
        try await journal.save(value)
        let decoded = try await journal.load(scope: scope, projectId: "project-a")
        try expect(decoded?.request == value.request && decoded?.receiptExpected == true, "Protected journals must retain cost identity and attachment intent")
        let bytes = try JSONEncoder().encode(value)
        try expect(bytes.count < 10_000 && String(data: bytes, encoding: .utf8)?.contains("data_base64") == false, "Receipt bytes must never enter the small cost journal")
        let files = JobCostReceiptFiles()
        let pdf = Data("%PDF-1.4\n%%EOF".utf8)
        let source = directory.appendingPathComponent("Receipt.pdf")
        try pdf.write(to: source)
        let imported = try await files.importFile(source)
        try expect(imported.data == pdf && imported.mimeType == "application/pdf", "Private file import must retain valid bounded PDFs")
        let preview = try await files.preview(data: pdf, filename: "../untrusted.pdf", mimeType: "application/pdf")
        try expect(FileManager.default.fileExists(atPath: preview.path) && preview.lastPathComponent == "Receipt.pdf", "Private preview paths must not trust a remote filename")
        let attributes = try FileManager.default.attributesOfItem(atPath: preview.path)
        try expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "Receipt previews must be private local files")
        await files.removePreview(source)
        try expect(FileManager.default.fileExists(atPath: source.path), "Preview cleanup must never remove a user-selected source file")
        await files.removePreview(preview)
        try expect(!FileManager.default.fileExists(atPath: preview.path), "Closing a preview must remove its generated local file")
        let oversized = directory.appendingPathComponent("Large.pdf")
        try Data(repeating: 0x20, count: 5_000_001).write(to: oversized)
        do { _ = try await files.importFile(oversized); throw Failure(description: "Oversize receipt accepted") }
        catch is Failure { throw Failure(description: "Oversize receipt accepted") }
        catch { checks += 1 }
        try await store.purge(userId: scope.userId)
        do { try await journal.save(value); throw Failure(description: "Signed-out view recreated a cost journal") }
        catch is Failure { throw Failure(description: "Signed-out view recreated a cost journal") }
        catch { checks += 1 }
    }
}

private enum CostFakeError: Error, EstimateCreationFailureClassifying {
    case uncertain
    var creationWriteIsUnconfirmed: Bool { true }
}

@MainActor
private final class CostFakeJournal: JobCostJournaling {
    var pending: JobCostPending?
    var failSave = false
    var failLoad = false
    func load(scope: EstimateDraftScope, projectId: String) async throws -> JobCostPending? {
        if failLoad { throw JobCostError.invalidJournal }
        return pending?.scope == scope && pending?.projectId == projectId ? pending : nil
    }
    func save(_ pending: JobCostPending) async throws {
        if failSave { throw CocoaError(.fileWriteOutOfSpace) }
        self.pending = pending
    }
    func remove(scope: EstimateDraftScope, projectId: String) async throws { pending = nil }
}

@MainActor
private final class CostFakeService: JobCostServing {
    var entries: [JobCostEntry] = []
    var requests: [JobCostRequest] = []
    var commitThenFail = false
    var failBeforeCreate = false
    var failAttachment = false
    var attachmentCalls = 0
    var pageSize = 25

    func list(projectId: String, cursor: String?, includeVoided: Bool) async throws -> JobCostPage {
        let values = entries.filter { includeVoided || $0.voidedAt == nil }
        let offset = cursor.flatMap(Int.init) ?? 0
        let slice = Array(values.dropFirst(offset).prefix(pageSize))
        let next = offset + slice.count < values.count ? String(offset + slice.count) : nil
        return JobCostPage(items: slice, nextCursor: next, summary: JobCostRegressionTests.summary())
    }
    func create(projectId: String, request: JobCostRequest) async throws -> JobCostEntry {
        requests.append(request)
        if failBeforeCreate { throw CostFakeError.uncertain }
        if let entry = entries.first(where: { $0.requestId == request.requestId }) { return entry }
        let entry = JobCostRegressionTests.entry(request: request, id: "cost-\(entries.count + 1)")
        entries.insert(entry, at: 0)
        if commitThenFail { commitThenFail = false; throw CostFakeError.uncertain }
        return entry
    }
    func voidEntry(id: String) async throws {}
    func attachReceipt(id: String, data: Data, mimeType: String, filename: String) async throws {
        attachmentCalls += 1
        if failAttachment { throw CostFakeError.uncertain }
    }
    func receipt(id: String) async throws -> Data { Data("%PDF-1.4\n%%EOF".utf8) }
}
