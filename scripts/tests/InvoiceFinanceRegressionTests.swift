import Foundation

@main
@MainActor
struct InvoiceFinanceRegressionTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static var checks = 0
    static let us = Locale(identifier: "en_US")

    static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard value() else { throw Failure(description: message) }
    }

    static func main() async throws {
        try paymentValidation()
        try paymentScheduleValidation()
        try await confirmedAndAmbiguousPayments()
        try await restartRecovery()
        try await journalFailureAndTenantIsolation()
        try await scheduleRecoveryAndGatewayGuards()
        try await realPaymentJournal()
        print("PASS: \(checks) invoice finance checks (exact money, payment dates, persisted UUIDs, crash recovery, receipt reconciliation, deposits, gateway guards and historical adjustments).")
    }

    static func invoice(status: Invoice.Status = .sent, total: Decimal = Decimal(string: "201.01")!, paid: Decimal = 0) -> Invoice {
        let s = Invoice.sample
        return Invoice(id: s.id, estimateId: s.estimateId, proposalId: s.proposalId, projectId: s.projectId,
            companyId: s.companyId, clientId: s.clientId, invoiceNumber: s.invoiceNumber, status: status,
            subtotal: total, taxAmount: 0, discountAmount: 0, totalAmount: total, amountPaid: paid,
            amountDue: total - paid, issuedDate: s.issuedDate, dueDate: s.dueDate, paidAt: nil, sentAt: s.sentAt,
            notes: s.notes, paymentInstructions: s.paymentInstructions, currencyCode: "USD", createdAt: s.createdAt, updatedAt: s.updatedAt)
    }

    static func snapshot(invoice: Invoice = invoice(), payments: [InvoicePaymentReceipt] = [], installments: [InvoiceInstallment] = [], checkout: InvoiceCheckoutStatus? = nil) -> InvoiceFinanceSnapshot {
        InvoiceFinanceSnapshot(invoice: invoice, shareURLString: "https://example.invalid/invoice/token", payments: payments, installments: installments, checkout: checkout)
    }

    static func form(amount: String = "50.25") -> InvoiceReceivedPaymentForm {
        var form = InvoiceReceivedPaymentForm()
        form.amount = amount
        form.method = .check
        form.reference = "  Check 123  "
        form.notes = "Deposit received"
        form.recordedAt = Date(timeIntervalSince1970: 1_790_000_000.123)
        return form
    }

    static func paymentValidation() throws {
        let request = try form().request(invoice: invoice(), locale: us)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any]
        try expect(request.amount == Decimal(string: "50.25") && request.reference == "Check 123", "Money must be exact and references trimmed")
        try expect(UUID(uuidString: request.requestId) != nil, "Every payment attempt requires a stable UUID")
        try expect(object["method"] as? String == "check", "Payment methods use canonical backend values")
        try expect((object["recorded_at"] as? String)?.hasSuffix(".123Z") == true, "Payment timestamps must preserve millisecond precision")
        let restored = try JSONDecoder().decode(RecordReceivedPaymentRequest.self, from: JSONEncoder().encode(request))
        try expect(restored == request, "The exact request body must survive local journaling")
        for amount in ["0", "-1", "1.001", "202", "NaN", "1e2", "50 dollars"] {
            do { _ = try form(amount: amount).request(invoice: invoice(), locale: us); throw Failure(description: "Invalid payment accepted: \(amount)") }
            catch is InvoiceFinanceError { checks += 1 }
        }
        var invalid = form()
        invalid.reference = String(repeating: "😀", count: 128)
        do { _ = try invalid.request(invoice: invoice(), locale: us); throw Failure(description: "Oversized reference accepted") }
        catch is InvoiceFinanceError { checks += 1 }
        invalid = form()
        invalid.recordedAt = Date().addingTimeInterval(120)
        do { _ = try invalid.request(invoice: invoice(), locale: us); throw Failure(description: "Future payment date accepted") }
        catch is InvoiceFinanceError { checks += 1 }
        for state in [Invoice.Status.draft, .void, .paid] {
            let current = invoice(status: state, paid: state == .paid ? Decimal(string: "201.01")! : 0)
            do { _ = try form().request(invoice: current, locale: us); throw Failure(description: "Invalid invoice state accepted") }
            catch is InvoiceFinanceError { checks += 1 }
        }
        let localized = try form(amount: "50,25").request(invoice: invoice(), locale: Locale(identifier: "de_DE"))
        try expect(localized.amount == request.amount, "Localized decimal input must preserve money")
    }

    static func paymentScheduleValidation() throws {
        let current = invoice(status: .draft)
        var schedule = InvoicePaymentScheduleForm(snapshot: snapshot(invoice: current), locale: us)
        let initial = try schedule.request(invoice: current, locale: us)
        try expect(initial.installments.count == 1, "A full-balance schedule is valid initially")
        schedule.useDeposit(percent: 30, locale: us)
        let request = try schedule.request(invoice: current, locale: us)
        try expect(request.installments[0].amount == Decimal(string: "60.30") && request.installments[1].amount == Decimal(string: "140.71"), "Deposit rounding must leave an exact remaining balance")
        try expect(request.installments.reduce(Decimal(0), { $0 + $1.amount }) == current.totalAmount, "Scheduled amounts must equal the invoice to the cent")
        schedule.installments[1].amount = "140.70"
        do { _ = try schedule.request(invoice: current, locale: us); throw Failure(description: "Incomplete payment schedule accepted") }
        catch is InvoiceFinanceError { checks += 1 }
        schedule.installments[1].amount = "140.71"
        schedule.installments[0].title = " "
        do { _ = try schedule.request(invoice: current, locale: us); throw Failure(description: "Unnamed milestone accepted") }
        catch is InvoiceFinanceError { checks += 1 }
        schedule.installments[0].title = "Deposit"
        do { _ = try schedule.request(invoice: invoice(), locale: us); throw Failure(description: "Sent schedule was editable") }
        catch is InvoiceFinanceError { checks += 1 }
    }

    private static func model(_ service: FakeFinanceService, _ journal: FakePaymentJournal) async -> InvoiceFinanceViewModel {
        let model = InvoiceFinanceViewModel(invoiceId: Invoice.sample.id, service: service, journal: journal)
        await model.load(userId: "user-a", companyId: Invoice.sample.companyId)
        return model
    }

    static func confirmedAndAmbiguousPayments() async throws {
        let service = FakeFinanceService()
        let journal = FakePaymentJournal()
        let model = await model(service, journal)
        service.commitThenLoseResponse = true
        let first = await model.record(form: form(), locale: us)
        try expect(!first && model.pendingPayment != nil && !model.canRecordNewPayment, "A lost response must freeze a persisted pending receipt")
        try expect(journal.pending?.request == service.requests.first, "The journal must contain the same body sent over the network")
        let second = await model.record(form: form(amount: "199"), locale: us)
        try expect(second && service.requests.count == 2 && service.requests[0] == service.requests[1], "Retry ignores changed form input and reuses the exact pending request")
        try expect(service.current.payments.count == 1 && model.pendingPayment == nil && journal.pending == nil, "An idempotent retry cannot record the same cash twice")
        try expect(model.snapshot?.invoice.amountPaid == Decimal(string: "50.25") && model.savedRevision == 1, "Canonical receipt and balance must replace local arithmetic")
        try expect(model.canRecordNewPayment, "After confirmed recovery another separate received payment can be recorded")
    }

    static func restartRecovery() async throws {
        let service = FakeFinanceService()
        let journal = FakePaymentJournal()
        let first = await model(service, journal)
        service.failBeforeWrite = .uncertain
        _ = await first.record(form: form(), locale: us)
        let original = journal.pending!.request
        let restarted = await model(service, journal)
        try expect(restarted.pendingPayment?.request == original && !restarted.canRecordNewPayment, "App restart must recover the exact UUID and frozen payload")
        service.failBeforeWrite = nil
        let recovered = await restarted.retryPendingPayment()
        try expect(recovered && service.current.payments.count == 1, "A recovered request can be replayed safely")
        try expect(service.requests.last == original, "Restart recovery must not generate a different payment UUID")
        service.commitThenLoseResponse = true
        _ = await restarted.record(form: form(amount: "10"), locale: us)
        let before = service.requests.count
        let readRecovered = await model(service, journal)
        try expect(readRecovered.pendingPayment == nil && service.requests.count == before, "Reading an already accepted receipt can finish recovery without a POST")
    }

    static func journalFailureAndTenantIsolation() async throws {
        let service = FakeFinanceService()
        let journal = FakePaymentJournal()
        let model = await model(service, journal)
        journal.failSave = true
        let blocked = await model.record(form: form(), locale: us)
        try expect(!blocked && service.requests.isEmpty, "A failed pending journal must prevent a payment POST")
        journal.failSave = false
        service.failBeforeWrite = .rejected
        _ = await model.record(form: form(), locale: us)
        try expect(model.pendingPayment == nil && journal.pending == nil && model.journalNeedsAttention, "A known server rejection clears the attempted receipt but requires a current balance")
        service.failBeforeWrite = nil
        await model.load(userId: "user-a", companyId: Invoice.sample.companyId)
        try expect(model.canRecordNewPayment, "A canonical reload resolves the rejected attempt")
        journal.failLoad = true
        await model.load(userId: "user-a", companyId: Invoice.sample.companyId)
        try expect(model.snapshot != nil && model.journalNeedsAttention && !model.canRecordNewPayment, "Corrupt recovery data must preserve readable history and block another cash record")
        journal.failLoad = false
        await model.load(userId: "other-user", companyId: "other-company")
        try expect(model.snapshot == nil && model.pendingPayment == nil, "A different tenant must not inherit prior invoice data")
        let old = InvoicePaymentReceipt(id: "historic", requestId: UUID().uuidString, amount: -10, method: "balance_correction", reference: nil, notes: nil, recordedAt: nil, createdAt: Date())
        service.current = snapshot(payments: [old])
        let history = await self.model(service, journal)
        try expect(history.savedRevision == 0 && history.snapshot?.payments[0].recordedAt == nil, "Historical adjustments are not new cash events and keep unknown original dates")
    }

    static func scheduleRecoveryAndGatewayGuards() async throws {
        let service = FakeFinanceService()
        service.current = snapshot(invoice: invoice(status: .draft))
        let journal = FakePaymentJournal()
        let model = await model(service, journal)
        let form = InvoicePaymentScheduleForm(snapshot: service.current, locale: us)
        service.failSchedule = true
        let failed = await model.updateSchedule(form, locale: us)
        try expect(!failed && model.scheduleNeedsRefresh && !model.canEditSchedule, "A lost schedule response requires a canonical reload")
        _ = await model.updateSchedule(form, locale: us)
        try expect(service.scheduleCalls == 1, "An unconfirmed schedule cannot be blindly replaced again")
        await model.load(userId: "user-a", companyId: Invoice.sample.companyId)
        try expect(model.canEditSchedule, "Refreshing restores schedule editing on a current draft")
        let attempt = InvoiceCheckoutAttempt(id: "attempt-a", state: "OPEN", amount: 100, currencyCode: "USD", createdAt: Date())
        service.current = snapshot(checkout: InvoiceCheckoutStatus(configured: true, accountConnected: true, activeAttempt: attempt, requiresRefundReview: true, canRecordManualPayment: false))
        await model.load(userId: "user-a", companyId: Invoice.sample.companyId)
        try expect(!model.canRecordNewPayment, "An active checkout blocks competing manual receipts")
        let denied = await model.cancelCheckout(canManage: false)
        try expect(!denied && service.cancelCalls == 0, "Non-admin UI actions must not attempt checkout cancellation")
        let cancelled = await model.cancelCheckout(canManage: true)
        try expect(cancelled && service.cancelCalls == 1 && model.canRecordNewPayment, "Confirmed cancellation reloads authoritative manual-payment eligibility")
        let reviewDenied = await model.reviewRefund(canManage: false)
        try expect(!reviewDenied && service.reviewCalls == 0, "Refund acknowledgement is an owner/admin action")
        let reviewed = await model.reviewRefund(canManage: true)
        try expect(reviewed && service.reviewCalls == 1, "Explicit refund review must use the current balance and reload its state")
    }

    static func realPaymentJournal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("proestimate-payment-journal-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EstimateDraftStore(directory: directory)
        let journal = InvoicePaymentJournal(store: store)
        let scope = EstimateDraftScope(userId: "user-a", companyId: Invoice.sample.companyId)
        let request = try form().request(invoice: invoice(), locale: us)
        let pending = PendingInvoicePayment(scope: scope, invoiceId: Invoice.sample.id, request: request, savedAt: Date())
        try await journal.save(pending)
        let read = try await journal.load(scope: scope, invoiceId: Invoice.sample.id)
        try expect(read?.request == request, "The protected journal must round-trip the exact payment request")
        let other = try await journal.load(scope: scope, invoiceId: "another-invoice")
        try expect(other == nil, "Pending payment bodies cannot cross invoice identities")
        try await store.purge(userId: scope.userId)
        do { try await journal.save(pending); throw Failure(description: "Logged-out writer recreated a receipt journal") }
        catch is Failure { throw Failure(description: "Logged-out writer recreated a receipt journal") }
        catch { checks += 1 }
        let freshJournal = InvoicePaymentJournal(store: store)
        let empty = try await freshJournal.load(scope: scope, invoiceId: Invoice.sample.id)
        try expect(empty == nil, "Sign-out purges pending payment data along with estimate drafts")
    }
}

enum StatusBadge { enum Style { case neutral, info, success, warning, error } }

private enum FinanceFailure: Error, EstimateCreationFailureClassifying {
    case uncertain, rejected
    var creationWriteIsUnconfirmed: Bool { self == .uncertain }
}

@MainActor
private final class FakePaymentJournal: InvoicePaymentJournaling {
    var pending: PendingInvoicePayment?
    var failSave = false
    var failLoad = false
    func load(scope: EstimateDraftScope, invoiceId: String) async throws -> PendingInvoicePayment? {
        if failLoad { throw InvoiceFinanceError.invalidJournal }
        return pending?.scope == scope && pending?.invoiceId == invoiceId ? pending : nil
    }
    func save(_ payment: PendingInvoicePayment) async throws {
        if failSave { throw CocoaError(.fileWriteOutOfSpace) }
        pending = payment
    }
    func remove(scope: EstimateDraftScope, invoiceId: String) async throws { pending = nil }
}

@MainActor
private final class FakeFinanceService: InvoiceFinanceServing {
    var current = InvoiceFinanceRegressionTests.snapshot()
    var requests: [RecordReceivedPaymentRequest] = []
    var commitThenLoseResponse = false
    var failBeforeWrite: FinanceFailure?
    var failSchedule = false
    var scheduleCalls = 0
    var cancelCalls = 0
    var reviewCalls = 0

    func getFinance(invoiceId: String) async throws -> InvoiceFinanceSnapshot { current }
    func recordPayment(invoiceId: String, request: RecordReceivedPaymentRequest) async throws -> InvoiceFinanceSnapshot {
        requests.append(request)
        if let failBeforeWrite { throw failBeforeWrite }
        if current.payments.contains(where: { $0.requestId == request.requestId }) { return current }
        let receipt = InvoicePaymentReceipt(id: UUID().uuidString, requestId: request.requestId, amount: request.amount,
            method: request.method.rawValue, reference: request.reference, notes: request.notes, recordedAt: request.recordedAt, createdAt: Date())
        let total = current.invoice.totalAmount
        let paid = current.invoice.amountPaid + request.amount
        current = InvoiceFinanceRegressionTests.snapshot(invoice: InvoiceFinanceRegressionTests.invoice(status: paid == total ? .paid : .partiallyPaid,
            total: total, paid: paid), payments: current.payments + [receipt])
        if commitThenLoseResponse { commitThenLoseResponse = false; throw FinanceFailure.uncertain }
        return current
    }
    func updateSchedule(invoiceId: String, request: UpdateInvoiceScheduleRequest) async throws -> InvoiceFinanceSnapshot {
        scheduleCalls += 1
        if failSchedule { throw FinanceFailure.uncertain }
        return current
    }
    func cancelCheckout(invoiceId: String) async throws {
        cancelCalls += 1
        current.checkout = InvoiceCheckoutStatus(configured: true, accountConnected: true, activeAttempt: nil, requiresRefundReview: true, canRecordManualPayment: true)
    }
    func reviewRefund(invoiceId: String, request: ReviewInvoiceRefundRequest) async throws {
        reviewCalls += 1
        current.checkout = InvoiceCheckoutStatus(configured: true, accountConnected: true, activeAttempt: nil, requiresRefundReview: false, canRecordManualPayment: true)
    }
}
