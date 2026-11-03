import Foundation

protocol InvoiceFinanceServing: Sendable {
    func getFinance(invoiceId: String) async throws -> InvoiceFinanceSnapshot
    func recordPayment(invoiceId: String, request: RecordReceivedPaymentRequest) async throws -> InvoiceFinanceSnapshot
    func updateSchedule(invoiceId: String, request: UpdateInvoiceScheduleRequest) async throws -> InvoiceFinanceSnapshot
    func cancelCheckout(invoiceId: String) async throws
    func reviewRefund(invoiceId: String, request: ReviewInvoiceRefundRequest) async throws
}

struct InvoiceFinanceSnapshot: Decodable, Sendable {
    let invoice: Invoice
    let shareURLString: String?
    let payments: [InvoicePaymentReceipt]
    let installments: [InvoiceInstallment]
    var checkout: InvoiceCheckoutStatus? = nil

    enum CodingKeys: String, CodingKey {
        case invoice, payments, installments, checkout
        case shareURLString = "share_url"
    }

    var shareURL: URL? {
        guard invoice.status != .draft, let value = shareURLString, let url = URL(string: value),
              url.scheme == "https", url.host != nil else { return nil }
        return url
    }
}

struct InvoiceCheckoutStatus: Decodable, Sendable {
    let configured: Bool
    let accountConnected: Bool
    let activeAttempt: InvoiceCheckoutAttempt?
    let requiresRefundReview: Bool
    let canRecordManualPayment: Bool
    enum CodingKeys: String, CodingKey {
        case configured
        case accountConnected = "account_connected"
        case activeAttempt = "active_attempt"
        case requiresRefundReview = "requires_refund_review"
        case canRecordManualPayment = "can_record_manual_payment"
    }
}

struct InvoiceCheckoutAttempt: Decodable, Sendable {
    let id: String
    let state: String
    let amount: Decimal
    let currencyCode: String
    let createdAt: Date
    enum CodingKeys: String, CodingKey {
        case id, state, amount
        case currencyCode = "currency_code"
        case createdAt = "created_at"
    }
}

struct ReviewInvoiceRefundRequest: Encodable, Sendable {
    let expectedAmountPaid: Decimal
    let expectedAmountDue: Decimal
    enum CodingKeys: String, CodingKey {
        case expectedAmountPaid = "expected_amount_paid"
        case expectedAmountDue = "expected_amount_due"
    }
}

struct InvoicePaymentReceipt: Decodable, Identifiable, Sendable {
    let id: String
    let requestId: String
    let amount: Decimal
    let method: String
    let reference: String?
    let notes: String?
    let recordedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, amount, method, reference, notes
        case requestId = "request_id"
        case recordedAt = "recorded_at"
        case createdAt = "created_at"
    }

    var methodTitle: String {
        switch method {
        case "cash": "Cash"
        case "check": "Check"
        case "bank_transfer": "Bank transfer"
        case "legacy_manual": "Previously recorded payment"
        case "balance_correction": "Balance adjustment"
        case "card", "stripe", "stripe_card": "Online card payment"
        case "refund", "stripe_refund": "Refund"
        default: method.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

struct InvoiceInstallment: Decodable, Identifiable, Sendable {
    let id: String
    let title: String
    let amount: Decimal
    var creditAmount: Decimal? = nil
    let paidAmount: Decimal
    let amountDue: Decimal
    let dueDate: Date?
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, title, amount
        case creditAmount = "credit_amount"
        case paidAmount = "paid_amount"
        case amountDue = "amount_due"
        case dueDate = "due_date"
        case sortOrder = "sort_order"
    }
}

enum ReceivedPaymentMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case cash, check
    case bankTransfer = "bank_transfer"
    case other

    var id: String { rawValue }
    var title: String {
        switch self {
        case .cash: "Cash"
        case .check: "Check"
        case .bankTransfer: "Bank transfer"
        case .other: "Other"
        }
    }
}

struct InvoiceReceivedPaymentForm: Equatable, Sendable {
    var amount = ""
    var method = ReceivedPaymentMethod.cash
    var reference = ""
    var notes = ""
    var recordedAt = Date()

    init() {}

    init(request: RecordReceivedPaymentRequest, locale: Locale = .current) {
        amount = InvoiceMoneyInput.string(request.amount, locale: locale)
        method = request.method
        reference = request.reference ?? ""
        notes = request.notes ?? ""
        recordedAt = request.recordedAt
    }

    func request(invoice: Invoice, requestId: String = UUID().uuidString.lowercased(), now: Date = Date(), locale: Locale = .current) throws -> RecordReceivedPaymentRequest {
        guard invoice.status != .draft, invoice.status != .void, invoice.amountDue > 0 else {
            throw InvoiceFinanceError.validation("Send an invoice with an outstanding balance before recording a payment.")
        }
        let value = try InvoiceMoneyInput.positive(amount, locale: locale)
        guard value <= invoice.amountDue else { throw InvoiceFinanceError.validation("The payment exceeds the current outstanding balance. Refresh and review the invoice.") }
        guard reference.utf16.count <= 255, notes.utf16.count <= 2000 else {
            throw InvoiceFinanceError.validation("Keep references within 255 characters and notes within 2,000 characters.")
        }
        guard recordedAt.timeIntervalSince1970.isFinite, recordedAt <= now.addingTimeInterval(60) else {
            throw InvoiceFinanceError.validation("A received payment date can't be in the future.")
        }
        guard UUID(uuidString: requestId) != nil else { throw InvoiceFinanceError.invalidResponse }
        return RecordReceivedPaymentRequest(requestId: requestId.lowercased(), amount: value, method: method,
            reference: Self.optional(reference), notes: Self.optional(notes), recordedAt: InvoicePaymentDate.normalize(recordedAt))
    }

    private static func optional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct RecordReceivedPaymentRequest: Codable, Equatable, Sendable {
    let requestId: String
    let amount: Decimal
    let method: ReceivedPaymentMethod
    let reference: String?
    let notes: String?
    let recordedAt: Date

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case amount, method, reference, notes
        case recordedAt = "recorded_at"
    }

    init(requestId: String, amount: Decimal, method: ReceivedPaymentMethod, reference: String?, notes: String?, recordedAt: Date) {
        self.requestId = requestId
        self.amount = amount
        self.method = method
        self.reference = reference
        self.notes = notes
        self.recordedAt = recordedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestId = try container.decode(String.self, forKey: .requestId)
        amount = try container.decode(Decimal.self, forKey: .amount)
        method = try container.decode(ReceivedPaymentMethod.self, forKey: .method)
        reference = try container.decodeIfPresent(String.self, forKey: .reference)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        let value = try container.decode(String.self, forKey: .recordedAt)
        guard let date = InvoicePaymentDate.parse(value) else { throw InvoiceFinanceError.invalidResponse }
        recordedAt = date
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestId, forKey: .requestId)
        try container.encode(amount, forKey: .amount)
        try container.encode(method, forKey: .method)
        try container.encodeIfPresent(reference, forKey: .reference)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(InvoicePaymentDate.string(recordedAt), forKey: .recordedAt)
    }

    func matches(_ receipt: InvoicePaymentReceipt) -> Bool {
        receipt.requestId.lowercased() == requestId.lowercased() && receipt.amount == amount
            && receipt.method == method.rawValue && receipt.reference == reference && receipt.notes == notes
            && receipt.recordedAt.map { abs($0.timeIntervalSince(recordedAt)) < 0.001 } == true
    }
}

struct InvoiceInstallmentDraft: Identifiable, Equatable, Sendable {
    let id = UUID()
    var title = ""
    var amount = ""
    var hasDueDate = false
    var dueDate = Date()
}

struct InvoicePaymentScheduleForm: Equatable, Sendable {
    var installments: [InvoiceInstallmentDraft]
    let expectedTotal: Decimal

    init(snapshot: InvoiceFinanceSnapshot, locale: Locale = .current) {
        expectedTotal = snapshot.invoice.totalAmount
        installments = snapshot.installments.map {
            InvoiceInstallmentDraft(title: $0.title, amount: InvoiceMoneyInput.string($0.amount, locale: locale),
                hasDueDate: $0.dueDate != nil, dueDate: $0.dueDate ?? Date())
        }
        if installments.isEmpty { installments = [InvoiceInstallmentDraft(title: "Payment", amount: InvoiceMoneyInput.string(expectedTotal, locale: locale))] }
    }

    mutating func useDeposit(percent: Int, locale: Locale = .current) {
        guard percent > 0, percent < 100, expectedTotal >= Decimal(string: "0.02")! else { return }
        var value = expectedTotal * Decimal(percent) / 100
        var deposit = Decimal()
        NSDecimalRound(&deposit, &value, 2, .plain)
        guard deposit > 0, deposit < expectedTotal else { return }
        installments = [InvoiceInstallmentDraft(title: "Deposit", amount: InvoiceMoneyInput.string(deposit, locale: locale)),
            InvoiceInstallmentDraft(title: "Final payment", amount: InvoiceMoneyInput.string(expectedTotal - deposit, locale: locale))]
    }

    func request(invoice: Invoice, locale: Locale = .current) throws -> UpdateInvoiceScheduleRequest {
        guard invoice.status == .draft, invoice.amountPaid == 0, invoice.totalAmount == expectedTotal else {
            throw InvoiceFinanceError.validation("Refresh this draft before changing its payment schedule.")
        }
        guard !installments.isEmpty, installments.count <= 24 else { throw InvoiceFinanceError.validation("Use between one and 24 scheduled payments.") }
        let values = try installments.map { draft -> InvoiceScheduleInstallmentRequest in
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.utf16.count <= 120 else { throw InvoiceFinanceError.validation("Name every payment using 120 characters or fewer.") }
            let amount = try InvoiceMoneyInput.positive(draft.amount, locale: locale)
            return InvoiceScheduleInstallmentRequest(title: title, amount: amount, dueDate: draft.hasDueDate ? draft.dueDate : nil)
        }
        guard values.reduce(Decimal(0), { $0 + $1.amount }) == expectedTotal else {
            throw InvoiceFinanceError.validation("Scheduled payments must add up exactly to the invoice total.")
        }
        return UpdateInvoiceScheduleRequest(expectedTotal: expectedTotal, installments: values)
    }
}

struct UpdateInvoiceScheduleRequest: Encodable, Sendable {
    let expectedTotal: Decimal
    let installments: [InvoiceScheduleInstallmentRequest]
    enum CodingKeys: String, CodingKey { case expectedTotal = "expected_total"; case installments }
}

struct InvoiceScheduleInstallmentRequest: Encodable, Sendable {
    let title: String
    let amount: Decimal
    let dueDate: Date?
    enum CodingKeys: String, CodingKey { case title, amount; case dueDate = "due_date" }
}

enum InvoiceFinanceError: LocalizedError {
    case validation(String)
    case invalidResponse
    case invalidJournal

    nonisolated var errorDescription: String? {
        switch self {
        case let .validation(message): message
        case .invalidResponse: "The saved payment details couldn't be matched to this invoice."
        case .invalidJournal: "The pending payment couldn't be recovered safely. Review the saved receipts before recording another payment."
        }
    }
}

enum InvoiceMoneyInput {
    static func positive(_ text: String, locale: Locale) throws -> Decimal {
        guard let value = DecimalFormInput.parse(text, locale: locale), value > 0,
              value <= Decimal(string: "9999999999.99")! else { throw InvoiceFinanceError.validation("Enter a positive payment amount.") }
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 2, .plain)
        guard rounded == value else { throw InvoiceFinanceError.validation("Use no more than two decimal places.") }
        return value
    }

    static func string(_ value: Decimal, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? value.description
    }
}

enum InvoicePaymentDate {
    static func string(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func parse(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }

    static func normalize(_ date: Date) -> Date { parse(string(date)) ?? date }
}
