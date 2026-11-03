# Contractor invoice checkout

This optional integration collects payment for contractors’ physical work. Apple StoreKit continues to handle ProEstimate subscriptions and AI access. No invoice payment creates or extends an app entitlement.

## Activation

Online collection defaults off. Configure a Stripe Connect platform and a restricted backend key with the required Accounts v2, Account Links, Checkout Sessions, PaymentIntent and refund read/write permissions. Keep credentials in Railway variables; never place them in the app, website bundle, repository or chat.

- `STRIPE_PAYMENTS_ENABLED=true`
- `STRIPE_API_KEY`: a restricted Stripe API key where available
- `STRIPE_WEBHOOK_SECRET`: the signing secret for the connected-account event destination

Production refuses sandbox keys even if the flag is enabled. Use separate Stripe sandboxes and a disposable development database to test checkout; do not create sandbox receipts in real customer invoices.

Company owners/admins open Settings → Customer payments and explicitly begin hosted onboarding. New Accounts v2 merchants have full Stripe Dashboard access, direct charges, Stripe fee collection and Stripe negative balance responsibility. No application fee is introduced. Company/country/creation inputs and the creation idempotency key are retained for safe retry. Reconciliation searches by company metadata before creating another account once the provider idempotency-retention window may have elapsed.

Before every checkout the backend retrieves `configuration.merchant.capabilities.card_payments.status` afresh. Returning from onboarding does not establish readiness. Expired onboarding links return to an informational page that directs the authenticated owner back to the app to request a new link.

## Webhook destination

Configure connected-account snapshot events to POST to `/v1/payments/stripe/webhook`. This route must receive the raw JSON bytes before Express JSON parsing. Signature verification, payment environment, connected account, saved attempt, session, PaymentIntent, currency and exact server amount are checked before a receipt is written.

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

Manual payment recording, legacy balance changes, voiding and financial edits cannot run while checkout is active. Owners/admins can expire an open checkout. Processing payments remain blocked until the provider confirms success or failure. Sent invoice financial headers and line items are read-only; only drafts with no receipt history can be deleted through the invoice endpoint. Explicit project/account erasure remains a separate privacy operation.

Estimate conversion returns an existing non-VOID invoice for the same estimate. Conversions in a linked revision family serialize on its ancestor locks and reject another full contract invoice once any related version has been billed. Additional approved scope requires an explicit amendment/delta invoice.

## Receipts and refunds

Provider PaymentIntent/refund identifiers uniquely deduplicate append-only monetary entries. Repeated or out-of-order payment events cannot count the same receipt twice. A verified successful refund adds a negative receipt, recomputes the balance and requires an owner/admin to review refreshed totals before further online collection. Pending/failed refunds do not change the paid balance. Disputes trigger an explicit review hold and are managed in the contractor’s full Stripe Dashboard; they do not automatically rewrite the invoice’s contractual balance.

Receipt dates use the signed payment-confirmation event time. If a refund arrives before the original confirmation, the original payment date remains unknown until its signed event arrives; the app does not invent a historical date from webhook arrival time. Public invoices omit internal notes, request UUIDs, processor identifiers and private payment references.

## Verification before activation

The repository exercises the integration against disposable PostgreSQL with a fake external gateway, plus a real Stripe SDK signature/tampering test without network calls. Live onboarding, sandbox card/async checkout and webhook delivery must also be checked in the selected Stripe platform before production activation. No Stripe account, charge or refund is created by these automated tests.

Primary references: [Accounts v2](https://docs.stripe.com/connect/saas/tasks/create), [direct charges](https://docs.stripe.com/connect/direct-charges?platform=web&ui=stripe-hosted), [Checkout fulfillment](https://docs.stripe.com/checkout/fulfillment), [webhook signatures](https://docs.stripe.com/webhooks#verify-events), [currency limits](https://docs.stripe.com/currencies).
