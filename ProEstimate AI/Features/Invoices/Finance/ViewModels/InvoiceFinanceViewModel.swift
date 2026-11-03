import Foundation
import Observation

@MainActor
@Observable
final class InvoiceFinanceViewModel {
    let invoiceId: String
    private(set) var snapshot: InvoiceFinanceSnapshot?
    private(set) var pendingPayment: PendingInvoicePayment?
    private(set) var isLoading = false
    private(set) var isWorking = false
    private(set) var journalNeedsAttention = false
    private(set) var scheduleNeedsRefresh = false
    private(set) var errorMessage: String?
    private(set) var lastError: (any Error)?
    private(set) var savedRevision = 0
    private var scope: EstimateDraftScope?
    private let service: any InvoiceFinanceServing
    private let journal: any InvoicePaymentJournaling

    init(invoiceId: String, service: any InvoiceFinanceServing, journal: any InvoicePaymentJournaling) {
        self.invoiceId = invoiceId
        self.service = service
        self.journal = journal
    }

    var canRecordNewPayment: Bool {
        guard let invoice = snapshot?.invoice else { return false }
        return !isLoading && !isWorking && !journalNeedsAttention && pendingPayment == nil
            && invoice.status != .draft && invoice.status != .void && invoice.amountDue > 0
            && snapshot?.checkout?.canRecordManualPayment != false
    }

    var canEditSchedule: Bool {
        guard let invoice = snapshot?.invoice else { return false }
        return !isLoading && !isWorking && !scheduleNeedsRefresh && pendingPayment == nil
            && invoice.status == .draft && invoice.amountPaid == 0 && invoice.totalAmount > 0
    }

    func load(userId: String, companyId: String) async {
        guard !isLoading, !isWorking, !userId.isEmpty, !companyId.isEmpty else { return }
        let context = EstimateDraftScope(userId: userId, companyId: companyId)
        if scope != context {
            scope = context
            snapshot = nil
            pendingPayment = nil
            journalNeedsAttention = false
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let saved = try await service.getFinance(invoiceId: invoiceId)
            try validate(saved, scope: context)
            snapshot = saved
            let pending = try await journal.load(scope: context, invoiceId: invoiceId)
            try Task.checkCancellation()
            guard scope == context else { return }
            guard pending == nil || (pending?.scope == context && pending?.invoiceId == invoiceId) else {
                throw InvoiceFinanceError.invalidJournal
            }
            pendingPayment = pending
            journalNeedsAttention = false
            scheduleNeedsRefresh = false
            errorMessage = nil
            if let pending { _ = await reconcile(pending, with: saved) }
        } catch {
            guard !Task.isCancelled else { return }
            lastError = error
            // A corrupt/unavailable journal could contain an accepted POST.
            // Preserve the receipt list but require recovery before new cash.
            journalNeedsAttention = true
            errorMessage = "Payment details couldn't be refreshed safely. Review the receipt history and retry. \(error.localizedDescription)"
        }
    }

    func record(form: InvoiceReceivedPaymentForm, locale: Locale = .current, now: Date = Date()) async -> Bool {
        guard !isLoading, !isWorking, !journalNeedsAttention, let scope, let invoice = snapshot?.invoice else { return false }
        if pendingPayment != nil { return await retryPendingPayment() }
        guard canRecordNewPayment else { return false }
        let request: RecordReceivedPaymentRequest
        do { request = try form.request(invoice: invoice, now: now, locale: locale) }
        catch { errorMessage = error.localizedDescription; return false }
        let pending = PendingInvoicePayment(scope: scope, invoiceId: invoiceId, request: request, savedAt: now)
        isWorking = true
        defer { isWorking = false }
        do {
            // Write the exact UUID, amount, date and references before the POST.
            // Recovery can replay this payload without recording cash twice.
            try await journal.save(pending)
            pendingPayment = pending
        } catch {
            errorMessage = "The payment wasn't sent because its recovery copy couldn't be saved. Check device storage and try again."
            return false
        }
        return await send(pending)
    }

    func retryPendingPayment() async -> Bool {
        guard !isLoading, !isWorking, !journalNeedsAttention, let pendingPayment else { return false }
        isWorking = true
        defer { isWorking = false }
        return await send(pendingPayment)
    }

    func updateSchedule(_ form: InvoicePaymentScheduleForm, locale: Locale = .current) async -> Bool {
        guard canEditSchedule, let invoice = snapshot?.invoice, let scope else { return false }
        let request: UpdateInvoiceScheduleRequest
        do { request = try form.request(invoice: invoice, locale: locale) }
        catch { errorMessage = error.localizedDescription; return false }
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            let saved = try await service.updateSchedule(invoiceId: invoiceId, request: request)
            try validate(saved, scope: scope)
            snapshot = saved
            scheduleNeedsRefresh = false
            errorMessage = nil
            savedRevision &+= 1
            return true
        } catch {
            scheduleNeedsRefresh = true
            lastError = error
            errorMessage = "The schedule couldn't be confirmed. Refresh and review the saved schedule before editing again. \(error.localizedDescription)"
            return false
        }
    }

    func cancelCheckout(canManage: Bool) async -> Bool {
        guard canManage, !isWorking, !isLoading, snapshot?.checkout?.activeAttempt != nil, let scope else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            try await service.cancelCheckout(invoiceId: invoiceId)
            let refreshed = try await service.getFinance(invoiceId: invoiceId)
            try validate(refreshed, scope: scope)
            snapshot = refreshed
            errorMessage = nil
            return true
        } catch {
            lastError = error
            errorMessage = "Checkout cancellation couldn't be confirmed. Refresh before recording another payment. \(error.localizedDescription)"
            return false
        }
    }

    func reviewRefund(canManage: Bool) async -> Bool {
        guard canManage, !isWorking, !isLoading, snapshot?.checkout?.requiresRefundReview == true,
              let invoice = snapshot?.invoice, let scope else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            try await service.reviewRefund(invoiceId: invoiceId, request: ReviewInvoiceRefundRequest(
                expectedAmountPaid: invoice.amountPaid, expectedAmountDue: invoice.amountDue))
            let refreshed = try await service.getFinance(invoiceId: invoiceId)
            try validate(refreshed, scope: scope)
            snapshot = refreshed
            errorMessage = nil
            savedRevision &+= 1
            return true
        } catch {
            lastError = error
            errorMessage = "The refund review couldn't be confirmed. Refresh the balance before reviewing again. \(error.localizedDescription)"
            return false
        }
    }

    private func send(_ pending: PendingInvoicePayment) async -> Bool {
        guard pending.scope == scope, pending.invoiceId == invoiceId else { return false }
        lastError = nil
        errorMessage = nil
        do {
            let saved = try await service.recordPayment(invoiceId: invoiceId, request: pending.request)
            try validate(saved, scope: pending.scope)
            snapshot = saved
            guard await reconcile(pending, with: saved) else {
                errorMessage = "The response didn't confirm this receipt. Refresh the history or retry the same pending payment."
                return false
            }
            return true
        } catch {
            lastError = error
            let unconfirmed = (error as? any EstimateCreationFailureClassifying)?.creationWriteIsUnconfirmed ?? true
            if !unconfirmed {
                do {
                    try await journal.remove(scope: pending.scope, invoiceId: invoiceId)
                    pendingPayment = nil
                    errorMessage = "The payment wasn't recorded. \(error.localizedDescription) Refresh the balance before correcting the details."
                    // A current balance is required after a competing device or
                    // pending online payment rejected the manual record.
                    journalNeedsAttention = true
                } catch {
                    errorMessage = "The server rejected this payment, but its local recovery copy couldn't be cleared. Refresh before continuing."
                }
            } else {
                errorMessage = "We couldn't confirm whether the payment was recorded. Its details are locked; refresh the receipt history or safely retry the same request."
            }
            return false
        }
    }

    private func reconcile(_ pending: PendingInvoicePayment, with saved: InvoiceFinanceSnapshot) async -> Bool {
        guard let receipt = saved.payments.first(where: { $0.requestId.lowercased() == pending.request.requestId.lowercased() }) else { return false }
        guard pending.request.matches(receipt) else {
            journalNeedsAttention = true
            errorMessage = "A saved receipt uses this request with different details. Review the invoice before recording another payment."
            return false
        }
        do {
            try await journal.remove(scope: pending.scope, invoiceId: invoiceId)
            pendingPayment = nil
            errorMessage = nil
            savedRevision &+= 1
            return true
        } catch {
            errorMessage = "The payment is recorded. Its local recovery copy couldn't be cleared; refresh to finish recovery before recording another payment."
            return false
        }
    }

    private func validate(_ value: InvoiceFinanceSnapshot, scope: EstimateDraftScope) throws {
        guard value.invoice.id == invoiceId, value.invoice.companyId == scope.companyId else { throw InvoiceFinanceError.invalidResponse }
    }
}
