# Contractor invoice checkout

This optional integration collects payment for contractors’ physical work. Apple StoreKit continues to handle ProEstimate subscriptions and AI access. No invoice payment creates or extends an app entitlement.

## Activation

Online collection defaults off. Select and activate the business's Stripe platform account, complete Connect setup and enable Accounts v2. Configure a restricted backend key for the actual adapter calls: platform Accounts v2 create/read/list and Account Links create; connected-account Checkout Sessions create/read/list/expire, PaymentIntent read for expanded confirmation, and Refund read/list. Stripe's permission reference maps those platform calls to `v2_account_storer_write` and `v2_account_read`, and connected-account calls to `checkout_session_write`, `payment_intent_read` and `charge_read` (the last permission covers refund retrieval). Do not substitute blanket Core write permission or assume similarly named legacy Accounts permissions cover Accounts v2. Validate these exact calls with a restricted key in an isolated sandbox and add only resource permissions identified by Stripe's permission errors. Webhook administration is a provisioning permission, not a runtime requirement. The integration makes no refund-creation, payout, transfer, Billing subscription or application-fee calls. Keep credentials in Railway variables; never place them in the app, website bundle, repository or chat.

- `STRIPE_PAYMENTS_ENABLED=true`
- `STRIPE_API_KEY`: a restricted Stripe API key where available
- `STRIPE_WEBHOOK_SECRET`: the signing secret for the connected-account event destination

Production refuses sandbox keys even if the flag is enabled. Use separate Stripe sandboxes and a disposable development database to test checkout; do not create sandbox receipts in real customer invoices.

`STRIPE_PAYMENTS_ENABLED=false` stops new collection and onboarding. Keep the valid key and signing secret available until existing sessions are fully reconciled: cancellation, verified receipts/refunds and safe erasure still work while new collection is disabled. Removing credentials first blocks safe cancellation and erasure until service access is restored.

Company owners/admins open Settings → Customer payments and explicitly begin hosted onboarding. New Accounts v2 merchants have full Stripe Dashboard access, direct charges, Stripe fee collection and Stripe negative balance responsibility. No application fee is introduced. Company/country/creation inputs and the creation idempotency key are retained for safe retry. Reconciliation searches by company metadata before creating another account once the provider idempotency-retention window may have elapsed.

Before every checkout the backend retrieves `configuration.merchant.capabilities.card_payments.status` afresh. Returning from onboarding does not establish readiness. Expired onboarding links return to an informational page that directs the authenticated owner back to the app to request a new link.

## Webhook destination

Configure a connected-account snapshot event destination at `https://<API-host>/v1/payments/stripe/webhook`, with API version `2026-10-28.endive`. Choose **Connected accounts** as the source for these v1 payment events, even though merchant onboarding uses Accounts v2. Use that destination's signing secret, which is separate from the API key. This route must receive the raw JSON bytes before Express JSON parsing. Signature verification, payment environment, connected account, saved attempt, session, PaymentIntent, currency and exact server amount are checked before a receipt is written.

The currently provisioned Viral Ventures LLC destination instead uses `2026-08-26.dahlia`: Stripe rejected another unique live event version, and unrelated destinations were preserved. The SDK still performs fresh resource reads with `2026-10-28.endive`. Before enabling this deployment, prove the older event envelope against actual sandbox Checkout and refund events pinned to Dahlia; a local signature test or a generic CLI fixture does not establish that compatibility.

Events handled:

- `checkout.session.completed`
- `checkout.session.async_payment_succeeded`
- `checkout.session.async_payment_failed`
- `checkout.session.expired`
- `refund.created`, `refund.updated`, `refund.failed`
- `charge.refunded`
- `charge.dispute.created`

Only a verified webhook with a freshly retrieved paid Checkout Session and succeeded PaymentIntent writes a positive Stripe receipt. Browser returns, cached URLs, onboarding returns and client-submitted prices cannot mark an invoice paid. The webhook returns a retryable error when a paid event arrives before its fresh API confirmation is available.

## Amounts and concurrency

The customer chooses the next unpaid installment or the remaining invoice balance; the server chooses the amount. USD, CAD, EUR, GBP, AUD, NZD and MXN are supported, in their two-decimal minor units. Minimums follow Stripe’s documented currency minimums; collection is capped at 99,999,999 minor units to accommodate dynamic non-card methods. Provider settlement currency and individual methods can impose further limits. Larger work can use an agreed installment schedule or external payment instructions.

One PREPARING/OPEN/PROCESSING attempt per invoice is enforced by an Invoice row lock and a partial unique index. Retried provider requests use the saved attempt ID as an idempotency key and retain the same amount, expiry and integration identifier. An unknown old provider write is reconciled against bounded account session history before another checkout is created. An unconfirmed recent write remains blocked instead of being treated as canceled.

Manual payment recording, legacy balance changes, voiding and financial edits cannot run while checkout is active. Owners/admins can expire an open checkout. Processing payments remain blocked until the provider confirms success or failure. Sent invoice financial headers and line items are read-only; only drafts with no receipt history or contract credit can be deleted through the invoice endpoint.

Project and last-member company erasure expire open provider sessions first. Preparing, processing or unconfirmed cancellation returns an actionable conflict while retaining reconciliation data. An exclusive company payment gate then prevents a new session slipping between the final active-attempt check and deletion. Deleting one member of a shared company retains the company's invoices and payment sessions. No erasure endpoint deletes the contractor's external Stripe financial records.

Estimate conversion returns an existing non-VOID invoice for the same estimate. Conversions in a linked revision family serialize on its ancestor locks and reject another full contract invoice once any related version has been billed. Additional approved scope requires an explicit amendment/delta invoice.

## Receipts and refunds

Provider PaymentIntent/refund identifiers uniquely deduplicate append-only monetary entries. Repeated or out-of-order payment events cannot count the same receipt twice. A verified successful refund adds a negative receipt, recomputes the balance and requires an owner/admin to review refreshed totals before further online collection. Pending/failed refunds do not change the paid balance. Disputes trigger an explicit review hold and are managed in the contractor’s full Stripe Dashboard; they do not automatically rewrite the invoice’s contractual balance.

Contract credits are independent of cash receipts: due is gross invoice total minus net cash paid minus applied credits. A verified refund allocates available approved contract credits under the same contract lock before publishing a collectible balance. Active sessions retain their agreed amounts; deferred credits are reconciled before the next collection. Credits appear separately on schedules, PDFs and public invoices and never generate a cash receipt. Refund/dispute review holds stop both online and new manual collection, and the public page hides external payment instructions until review is complete.

Receipt dates use the signed payment-confirmation event time. If a refund arrives before the original confirmation, the original payment date remains unknown until its signed event arrives; the app does not invent a historical date from webhook arrival time. Public invoices omit internal notes, request UUIDs, processor identifiers and private payment references.

## Verification before activation

The repository exercises the integration against disposable PostgreSQL with a fake external gateway, plus a real Stripe SDK signature/tampering test without network calls. Live onboarding, sandbox card/async checkout and webhook delivery must also be checked in the selected Stripe platform before production activation. No Stripe account, charge or refund is created by these automated tests.

Primary references: [Accounts v2](https://docs.stripe.com/connect/saas/tasks/create), [restricted-key permissions](https://docs.stripe.com/keys/permissions-reference), [direct charges](https://docs.stripe.com/connect/direct-charges?platform=web&ui=stripe-hosted), [Checkout fulfillment](https://docs.stripe.com/checkout/fulfillment), [webhook signatures](https://docs.stripe.com/webhooks#verify-events), [currency limits](https://docs.stripe.com/currencies).
