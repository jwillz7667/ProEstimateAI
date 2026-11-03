import Foundation
import Observation

@MainActor
@Observable
final class FollowUpHistoryModel {
    private(set) var history: FollowUpHistory?
    private(set) var isLoading = false
    private(set) var isWorking = false
    private(set) var errorMessage: String?
    private(set) var queuedReceipt: FollowUpRecord?
    private var scope = ""
    private var revision = 0
    private var requestId: String?
    private let service: any FollowUpServing
    let kind: FollowUpKind
    let entityId: String

    init(kind: FollowUpKind, entityId: String, service: any FollowUpServing) {
        self.kind = kind; self.entityId = entityId; self.service = service
    }

    var canSend: Bool {
        history?.eligible == true && history?.deliveryAvailable == true && !isLoading && !isWorking && queuedReceipt?.isPending != true
    }

    func load(scope nextScope: String) async {
        if scope != nextScope {
            revision += 1; scope = nextScope; history = nil; requestId = nil; queuedReceipt = nil; errorMessage = nil
            isLoading = false; isWorking = false
        }
        guard !isLoading, !isWorking else { return }
        isLoading = true
        let current = revision
        defer { if current == revision { isLoading = false } }
        do {
            let result = try await service.history(kind: kind, entityId: entityId)
            guard current == revision, !Task.isCancelled else { return }
            history = result; queuedReceipt = nil; errorMessage = nil
        } catch {
            if current == revision, !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }

    func send() async {
        guard canSend else { return }
        let key = requestId ?? UUID().uuidString
        requestId = key
        isWorking = true
        let current = revision
        defer { if current == revision { isWorking = false } }
        do {
            let receipt = try await service.queue(QueueFollowUpRequest(entityKind: kind, entityId: entityId, requestId: key))
            guard current == revision, !Task.isCancelled else { return }
            queuedReceipt = receipt
            requestId = nil
            errorMessage = nil
            do {
                let refreshed = try await service.history(kind: kind, entityId: entityId)
                guard current == revision, !Task.isCancelled else { return }
                history = refreshed; queuedReceipt = nil
            } catch {
                if current == revision { errorMessage = "The follow-up was queued. Refresh to check its progress." }
            }
        } catch {
            if current == revision, !Task.isCancelled {
                errorMessage = "The follow-up couldn't be confirmed. Retrying uses the same request. \(error.localizedDescription)"
            }
        }
    }
}

@MainActor
@Observable
final class FollowUpSettingsModel {
    var enabled = false
    var quoteDays = 3
    var invoiceDays = 7
    private(set) var saved: FollowUpSettings?
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var didSave = false
    private(set) var requiresRefresh = false
    private let service: any FollowUpServing
    private var scope = ""
    private var revision = 0

    init(service: any FollowUpServing) { self.service = service }
    var canSave: Bool {
        saved?.canManage == true && !isLoading && !isSaving && !requiresRefresh && (saved?.deliveryAvailable == true || !enabled)
            && (saved?.enabled != enabled || saved?.quoteDays != quoteDays || saved?.invoiceDays != invoiceDays)
    }

    func load(scope nextScope: String) async {
        if scope != nextScope {
            revision += 1; scope = nextScope; saved = nil; enabled = false; quoteDays = 3; invoiceDays = 7
            isLoading = false; isSaving = false; errorMessage = nil; didSave = false; requiresRefresh = false
        }
        guard !isLoading, !isSaving else { return }
        isLoading = true
        let current = revision
        defer { if current == revision { isLoading = false } }
        do {
            let value = try await service.settings()
            guard current == revision, !Task.isCancelled else { return }
            apply(value); errorMessage = nil; requiresRefresh = false
        } catch { if current == revision, !Task.isCancelled { errorMessage = error.localizedDescription } }
    }

    func save() async {
        guard canSave, (1...30).contains(quoteDays), (1...30).contains(invoiceDays) else { return }
        isSaving = true
        let current = revision
        defer { if current == revision { isSaving = false } }
        do {
            let value = try await service.updateSettings(UpdateFollowUpSettings(enabled: enabled, quoteDays: quoteDays, invoiceDays: invoiceDays))
            guard current == revision, !Task.isCancelled else { return }
            apply(value); errorMessage = nil; didSave = true; requiresRefresh = false
        } catch {
            if current == revision, !Task.isCancelled {
                requiresRefresh = true
                errorMessage = "The reminder settings couldn't be confirmed. Refresh to check the saved settings. \(error.localizedDescription)"
            }
        }
    }

    private func apply(_ value: FollowUpSettings) {
        saved = value; enabled = value.enabled; quoteDays = value.quoteDays; invoiceDays = value.invoiceDays
    }
}
