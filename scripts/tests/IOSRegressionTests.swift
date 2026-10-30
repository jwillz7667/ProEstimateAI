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
        try commerceContracts()
        try await transactionDelivery()
        try await paidUsageLimits()
        try authFormValidation()
        try oauthProofEncoding()
        print("PASS: \(checks) iOS regression checks (numeric validation, nullable edits, invoice payments, pagination, commerce contracts, purchase recovery, paid usage limits).")
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

    static func commerceContracts() throws {
        try expect(!SubscriptionState.billingRetry.hasProAccess, "Billing retry without a current grace period must not unlock paid features")
        let legacyAnnual = try JSONDecoder().decode(PlanCode.self, from: Data(#""PREMIUM_ANNUAL""#.utf8))
        try expect(legacyAnnual == .proAnnual, "Grandfathered annual Premium must retain its annual billing period")
        let unknown = try JSONDecoder().decode(PlanCode.self, from: Data(#""UNKNOWN_PLAN""#.utf8))
        try expect(unknown == .freeStarter, "An unknown plan must not be represented as a paid plan")
        let metrics = try JSONDecoder().decode([UsageMetricCode].self, from: Data(#"["AI_GENERATION","QUOTE_EXPORT","PROJECT_CREATED","ESTIMATE_GENERATED"]"#.utf8))
        try expect(metrics.count == 4, "All metrics in the canonical backend snapshot must decode")
        try expect(StoreProductModel.sampleMonthly.purchaseButtonTitle(fallback: "Start Free Trial") == "Start Free Trial", "Eligible monthly buyers should see the trial CTA")
        try expect(StoreProductModel.sampleAnnual.purchaseButtonTitle(fallback: "Start Free Trial") == "Subscribe Now", "Annual without an introductory offer must not advertise a trial")
        try expect(StoreProductModel.canonicalFallback(tier: .pro, isAnnual: false).purchaseButtonTitle(fallback: "Start Free Trial") == "Subscribe Now", "Unknown eligibility must not promise a trial")
        try expect(StoreProductModel.annualSavingsText(monthlyPrice: Decimal(string: "29.99")!, annualPrice: Decimal(string: "249.99")!) == "Save 30%", "Savings must match actual StoreKit prices")
        try expect(StoreProductModel.annualSavingsText(monthlyPrice: 10, annualPrice: 120) == nil, "Equal annual pricing must not advertise savings")
        try expect(StoreProductModel.annualSavingsText(monthlyPrice: 0, annualPrice: 120) == nil, "Missing monthly pricing must not produce invalid savings")

        for raw in ["TRIAL_OFFER", "SUBSCRIBE_NO_TRIAL", "USAGE_LIMIT_DAILY", "USAGE_LIMIT_WEEKLY", "USAGE_LIMIT_MONTHLY"] {
            let json = """
            {"ok":false,"error":{"code":"PAYWALL","message":"Limit reached","paywall":{"placement":"\(raw)","trigger_reason":"cap","blocking":true,"headline":"Limit reached","subheadline":"Try again tomorrow","primary_cta_title":"OK","secondary_cta_title":null,"show_continue_free":false,"show_restore_purchases":false,"recommended_product_id":null,"available_products":null}}}
            """
            let response = try JSONDecoder().decode(APIErrorEnvelope.self, from: Data(json.utf8))
            guard let decision = response.error.paywall else { throw Failure(description: "Paywall payload must decode") }
            try expect(decision.placement.rawValue == raw, "Server placement \(raw) must preserve the server's error")
            if decision.placement.isUsageLimit {
                let presenter = PaywallPresenter()
                presenter.configure(entitlementStore: .preview(snapshot: .samplePro))
                presenter.present(decision)
                try expect(presenter.activeLimitNotice != nil && presenter.activeDecision == nil, "Paid usage limits must show a notice instead of disappearing or offering a second subscription")
            }
        }
    }

    static func transactionDelivery() async throws {
        let api = MockCommerceAPIClient(delayNanoseconds: 0)
        let store = EntitlementStore()
        let delivery = CommerceTransactionDelivery(commerceAPI: api, entitlementStore: store)
        let request = SyncTransactionRequest(purchaseAttemptId: "attempt", storeProductId: AppConstants.proMonthlyProductID,
            transactionId: "transaction", originalTransactionId: "original", appAccountToken: UUID().uuidString,
            environment: "sandbox", signedTransaction: "fixture")
        var finishes = 0
        for error in [APIError.network("Offline"), .server(code: "INTERNAL_ERROR", message: "Unavailable"), .unauthorized] {
            api.forcedError = error
            do {
                try await delivery.sync(request) { finishes += 1 }
                throw Failure(description: "Unacknowledged transaction must fail delivery")
            } catch let caught as APIError {
                try expect(caught == error, "Delivery errors must propagate for retry")
            }
            try expect(finishes == 0 && store.snapshot == nil, "A failed delivery must leave the transaction unfinished and avoid granting access")
        }
        api.forcedError = nil
        var accessVisibleBeforeFinish = false
        try await delivery.sync(request) {
            accessVisibleBeforeFinish = store.hasProAccess
            finishes += 1
        }
        try expect(accessVisibleBeforeFinish, "The entitlement must be available before finishing")
        try expect(finishes == 1 && store.hasProAccess, "Retry must deliver paid access and then finish exactly once")

        let item = RestoreTransactionItem(storeProductId: request.storeProductId, transactionId: request.transactionId,
            originalTransactionId: request.originalTransactionId, appAccountToken: nil, environment: request.environment, signedTransaction: "fixture")
        api.forcedError = APIError.network("Offline")
        do {
            try await delivery.restore([item]) { finishes += 1 }
            throw Failure(description: "Failed restore must remain unfinished")
        } catch is APIError {}
        try expect(finishes == 1, "Restore must not finish receipts before the backend acknowledges them")
        api.forcedError = nil
        try await delivery.restore([item]) { finishes += 1 }
        try expect(finishes == 2, "Recovered restore must finish only after successful sync")

        let migratedAPI = MockCommerceAPIClient(delayNanoseconds: 0)
        let migratedStore = EntitlementStore()
        let migratedDelivery = CommerceTransactionDelivery(commerceAPI: migratedAPI, entitlementStore: migratedStore)
        var recoveredFinishes = 0
        for error in [APIError.server(code: "NOT_FOUND", message: "SubscriptionProduct not found"),
                      .server(code: "ACCOUNT_MISMATCH", message: "PurchaseAttempt belongs to another account"),
                      .server(code: "SUBSCRIPTION_BOUND_TO_OTHER_USER", message: "PurchaseAttempt belongs to another user")] {
            migratedAPI.syncForcedError = error
            do {
                try await migratedDelivery.sync(request) { recoveredFinishes += 1 }
                throw Failure(description: "Unrelated missing records and ownership failures must not restore")
            } catch let caught as APIError {
                try expect(caught == error, "Migration recovery must preserve ownership and product errors")
            }
            try expect(migratedAPI.restoreTransactionCallCount == 0 && recoveredFinishes == 0,
                       "Only a missing purchase attempt may enter restore recovery")
        }
        migratedAPI.syncForcedError = APIError.server(code: "NOT_FOUND", message: "PurchaseAttempt not found")
        migratedAPI.forcedError = APIError.network("Restore offline")
        do {
            try await migratedDelivery.sync(request) { recoveredFinishes += 1 }
            throw Failure(description: "Migration restore failure must remain unfinished")
        } catch is APIError {}
        try expect(recoveredFinishes == 0 && migratedStore.snapshot == nil,
                   "Migration recovery must wait for restore acknowledgement")
        migratedAPI.forcedError = nil
        var recoveredAccessBeforeFinish = false
        try await migratedDelivery.sync(request) {
            recoveredAccessBeforeFinish = migratedStore.hasProAccess
            recoveredFinishes += 1
        }
        try expect(recoveredFinishes == 1 && recoveredAccessBeforeFinish && migratedAPI.restoreTransactionCallCount == 2,
                   "A historical signed token must recover through restore and finish once")
    }

    static func paidUsageLimits() async throws {
        let snapshot = EntitlementSnapshot(subscriptionState: .proActive, currentPlanCode: .proMonthly,
            featureFlags: EntitlementSnapshot.samplePro.featureFlags,
            usage: [UsageBucket(metricCode: .aiGeneration, includedQuantity: 20, consumedQuantity: 20, remainingQuantity: 0, source: "PRO_SUBSCRIPTION"),
                    UsageBucket(metricCode: .quoteExport, includedQuantity: 50, consumedQuantity: 49, remainingQuantity: 1, source: "PRO_SUBSCRIPTION")],
            renewalDate: nil, trialEndsAt: nil, gracePeriodEndsAt: nil, isAutoRenewEnabled: true, billingWarning: nil)
        let store = EntitlementStore.preview(snapshot: snapshot)
        let api = MockCommerceAPIClient(delayNanoseconds: 0, entitlementSnapshot: snapshot)
        let meter = UsageMeterStore()
        meter.configure(commerceAPI: api, entitlementStore: store)
        await meter.refresh()
        try expect(meter.generationsTotal == 20 && !meter.canGenerate, "Pro generation usage must honor the backend's finite allowance")
        try expect(meter.quotesTotal == 50 && meter.quotesRemaining == 1, "Pro export usage must honor the backend's remaining allowance")
        try await meter.consumeQuoteExport()
        try expect(api.lastConsumedMetric == .quoteExport && !meter.canExportQuote, "Export authorization must consume the final paid quote credit")
        let revoked = EntitlementSnapshot(subscriptionState: .revoked, currentPlanCode: .proMonthly,
            featureFlags: snapshot.featureFlags, usage: [], renewalDate: nil, trialEndsAt: nil,
            gracePeriodEndsAt: nil, isAutoRenewEnabled: false, billingWarning: nil)
        try expect(!revoked.hasFeature(.canUseBranding) && !revoked.hasFeature(.canCreateInvoice), "Terminal subscriptions must not trust stale paid feature flags")
    }

    static func authFormValidation() throws {
        try expect(AuthFormValidation.isValidEmail("  O'Neil+work@example.com \n"), "Email validation must support backend-accepted addresses and surrounding whitespace")
        for email in ["not-an-email", "a..b@example.com", ".a@example.com", "a@example", "a@example..com"] {
            try expect(!AuthFormValidation.isValidEmail(email), "Malformed email \(email) must be blocked before submission")
        }
        try expect(!AuthFormValidation.isValidFullName("A") && AuthFormValidation.isValidFullName(" A B "), "Full-name validation must match server trim/minimum rules")
        try expect(!AuthFormValidation.isValidFullName(String(repeating: "a", count: 101)), "Oversized names must be rejected before the backend")
        for password in ["abcdefgh", "ABCDEFGH", "Abcdefgh", "Aa1", "Aa1" + String(repeating: "x", count: 70), "Aa1" + String(repeating: "💡", count: 18)] {
            try expect(AuthFormValidation.passwordMessage(password) != nil, "A password rejected by the backend must have inline guidance")
        }
        try expect(AuthFormValidation.passwordMessage("Aa1" + String(repeating: "x", count: 69)) == nil, "The bcrypt 72-byte boundary must remain accepted")
    }

    static func oauthProofEncoding() throws {
        try expect(OAuthRequestSecurity.nonceHash("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                   "The identity-provider nonce must use the backend's SHA256 hexadecimal proof format")
        let first = try OAuthRequestSecurity.randomToken()
        let second = try OAuthRequestSecurity.randomToken()
        try expect(first.count == 43 && first != second && first.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil,
                   "Each attempt needs an independent URL-safe 256-bit nonce")
        let apple = AppleSignInRequest(identityToken: "identity", authorizationCode: "code", fullName: nil, email: nil, rawNonce: first)
        let google = GoogleSignInRequest(identityToken: "identity", fullName: nil, email: nil, rawNonce: second)
        for (data, nonce) in [(try JSONEncoder().encode(apple), first), (try JSONEncoder().encode(google), second)] {
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            try expect(json["raw_nonce"] as? String == nonce && json["identity_token"] as? String == "identity",
                       "Both OAuth requests must carry the nonce proof using the server's snake-case contract")
        }
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
