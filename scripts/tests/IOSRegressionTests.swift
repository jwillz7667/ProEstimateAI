import Foundation

/// Compiles actual Foundation-only app sources without launching the app,
/// accessing Keychain, or making network requests.
@main
@MainActor
struct IOSRegressionTests {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    struct Row: Decodable, Identifiable {
        let id: String
    }

    static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else { throw Failure(description: message) }
    }

    static func main() async throws {
        try numericInput()
        try nullClearing()
        try cursorMetadata()
        try paymentExpectationEncoding()
        try await paymentRecovery()
        try await pagination()
        print("PASS: \(checks) iOS regression checks (numeric validation, nullable edits, payment expectations, cursor metadata, multi-page lists).")
    }

    static func numericInput() throws {
        let us = Locale(identifier: "en_US")
        let german = Locale(identifier: "de_DE")
        try expect(DecimalFormInput.parse(" 250.75 \n", locale: us) == Decimal(string: "250.75"), "Trimmed decimal input must retain cents")
        try expect(DecimalFormInput.parse("250,75", locale: german) == Decimal(string: "250.75"), "Localized decimal keyboard input must retain cents")
        try expect(DecimalFormInput.parse(".5", locale: us) == Decimal(string: "0.5"), "Fractional input must be accepted")
        try expect(DecimalFormInput.parse("0", locale: us) == 0, "Zero must be accepted")
        for invalid in ["", "-2", "NaN", "Infinity", "12 sq ft", "250abc", "2.3.4", "1e3", "1,250"] {
            try expect(DecimalFormInput.parse(invalid, locale: us) == nil, "Input '\(invalid)' must not be silently truncated")
        }
        try expect(DecimalFormInput.validationMessage(for: "  ", field: "area") == nil, "Blank optional fields must remain valid")
        try expect(DecimalFormInput.budgetValidationMessage(minimum: "250", maximum: "100") != nil, "Reversed budgets must be rejected")
        try expect(DecimalFormInput.budgetValidationMessage(minimum: "100", maximum: "250") == nil, "Ordered budgets must be accepted")
    }

    static func nullClearing() throws {
        let request = ProjectCreationRequest(
            title: "Updated project", projectType: .kitchen, clientId: nil,
            description: nil, budgetMin: nil, budgetMax: nil, qualityTier: nil,
            squareFootage: nil, dimensions: nil, language: nil, aiPreviewEnabled: nil,
            isRecurring: nil, recurrenceFrequency: nil, visitsPerMonth: nil,
            contractMonths: nil, recurrenceStartDate: nil
        )
        guard let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any] else {
            throw Failure(description: "Project request must encode as an object")
        }
        for key in ["client_id", "description", "budget_min", "budget_max", "quality_tier", "square_footage", "dimensions", "language", "recurrence_frequency", "visits_per_month", "contract_months", "recurrence_start_date"] {
            try expect(object[key] is NSNull, "Clearing '\(key)' must explicitly send JSON null")
        }
        try expect(object["ai_preview_enabled"] == nil, "Unset preview choice must preserve the server's creation default")
        try expect(object["is_recurring"] == nil, "Unset recurrence flag must preserve the server's creation default")
    }

    static func cursorMetadata() throws {
        let data = Data(#"{"ok":true,"data":[{"id":"first"}],"meta":{"pagination":{"next_cursor":"second-page"}}}"#.utf8)
        let envelope = try JSONDecoder().decode(APISuccessEnvelope<[Row]>.self, from: data)
        try expect(envelope.meta?.pagination?.nextCursor == "second-page", "Cursor metadata must decode its snake_case key")
        let last = try JSONDecoder().decode(APISuccessEnvelope<[Row]>.self, from: Data(#"{"ok":true,"data":[],"meta":{"pagination":{"next_cursor":null}}}"#.utf8))
        try expect(last.meta?.pagination?.nextCursor == nil, "A null cursor must terminate pagination")
        let noMeta = try JSONDecoder().decode(APISuccessEnvelope<[Row]>.self, from: Data(#"{"ok":true,"data":[]}"#.utf8))
        try expect(noMeta.meta == nil, "Single-page responses without metadata must stay compatible")
    }

    static func paymentExpectationEncoding() throws {
        let request = UpdateInvoiceRequest(status: .partiallyPaid, amountPaid: 125, expectedAmountPaid: 100)
        guard let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any] else {
            throw Failure(description: "Invoice request must encode as an object")
        }
        try expect((object["amount_paid"] as? NSNumber)?.decimalValue == 125, "The cumulative payment amount must encode as a number")
        try expect((object["expected_amount_paid"] as? NSNumber)?.decimalValue == 100, "Payment updates must encode the previously viewed balance")
        try expect(object["status"] as? String == "partially_paid", "Partial payments must use the server's status spelling")
        try expect(object["due_date"] == nil, "Payments must leave unrelated invoice terms unchanged")
        let terms = UpdateInvoiceRequest(notes: "Updated terms")
        guard let termsObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(terms)) as? [String: Any] else {
            throw Failure(description: "Invoice terms must encode as an object")
        }
        try expect(termsObject["expected_amount_paid"] == nil, "Nonpayment callers must stay compatible without an expectation")
    }

    static func paymentRecovery() async throws {
        let service = PaymentTestService()
        let viewModel = InvoiceDetailViewModel(invoiceService: service)
        await viewModel.load(id: Invoice.sample.id)
        let invalidSaved = await viewModel.recordPayment(amount: 0)
        try expect(!invalidSaved, "Zero payments must fail without contacting the server")
        let initialUpdateCount = await service.updateCount()
        try expect(initialUpdateCount == 0, "Invalid payments must not submit an update")

        await service.failUpdates(with: .server(code: "CONFLICT", message: "Refresh the invoice before recording this payment."))
        let saved = await viewModel.recordPayment(amount: 100)
        try expect(!saved && viewModel.paymentNeedsRefresh, "A concurrent payment must require a refreshed invoice")
        let request = await service.latestRequest()
        try expect(request?.amountPaid == 100 && request?.expectedAmountPaid == 0, "Payment must send a cumulative amount and the viewed balance")
        let repeated = await viewModel.recordPayment(amount: 100)
        try expect(!repeated, "A stale invoice must block another payment request")
        let staleUpdateCount = await service.updateCount()
        try expect(staleUpdateCount == 1, "Blocked stale retries must not reach the server")

        await viewModel.refreshPaymentState()
        try expect(!viewModel.paymentNeedsRefresh && viewModel.actionError == nil, "Successful refresh must restore payment entry")
        await service.failUpdates(with: .network("Connection dropped"))
        let uncertain = await viewModel.recordPayment(amount: 100)
        try expect(!uncertain && viewModel.paymentNeedsRefresh, "An uncertain network outcome must require refresh and review")
        try expect(viewModel.actionError?.contains("whether the payment was saved") == true, "An uncertain result must explain the need to review")
    }

    static func pagination() async throws {
        var cursors: [String?] = []
        let rows: [Row] = try await APIPageCollector.collect { cursor in
            cursors.append(cursor)
            switch cursor {
            case nil: return APIPage(items: [Row(id: "one"), Row(id: "two")], nextCursor: "page-two")
            case "page-two": return APIPage(items: [Row(id: "two"), Row(id: "three")], nextCursor: "page-three")
            case "page-three": return APIPage(items: [Row(id: "four")], nextCursor: nil)
            default: throw Failure(description: "Unexpected pagination cursor")
            }
        }
        try expect(rows.map(\.id) == ["one", "two", "three", "four"], "All pages must load in order without duplicate rows")
        try expect(cursors == [nil, "page-two", "page-three"], "Pages must fetch sequentially using server cursors")

        var repeatedCursorCalls = 0
        do {
            let _: [Row] = try await APIPageCollector.collect { _ in
                repeatedCursorCalls += 1
                return APIPage(items: [], nextCursor: "same")
            }
            throw Failure(description: "A repeated cursor must fail")
        } catch APIError.decoding {
            try expect(repeatedCursorCalls == 2, "Repeated cursor protection must stop immediately")
        }

        let empty: [Row] = try await APIPageCollector.collect { _ in APIPage(items: [], nextCursor: nil) }
        try expect(empty.isEmpty, "An empty account must load correctly")
    }
}

/// A deterministic failure-only service for actual view-model recovery tests.
/// Responses are local fixtures and no credentials or HTTP stack are involved.
actor PaymentTestService: InvoiceServiceProtocol {
    private var error: APIError = .network("No success response configured")
    private var request: UpdateInvoiceRequest?
    private var updates = 0

    func failUpdates(with error: APIError) { self.error = error }
    func updateCount() -> Int { updates }
    func latestRequest() -> UpdateInvoiceRequest? { request }
    func listInvoices() async throws -> [Invoice] { [Invoice.sample] }
    func getInvoice(id: String) async throws -> Invoice { Invoice.sample }
    func getLineItems(invoiceId: String) async throws -> [InvoiceLineItem] { [] }
    func updateInvoice(id: String, request: UpdateInvoiceRequest) async throws -> Invoice {
        self.request = request
        updates += 1
        throw error
    }
    func sendInvoice(id: String) async throws -> Invoice { throw error }
    func deleteInvoice(id: String) async throws { throw error }
    func convertEstimate(estimateId: String, request: ConvertEstimateRequest) async throws -> Invoice { throw error }
    func exportPDF(id: String) async throws -> Data { throw error }
}
