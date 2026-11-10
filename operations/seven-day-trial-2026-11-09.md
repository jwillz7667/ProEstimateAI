# Seven-day account trial and dismissible login offer

Every active account receives one seven-day Pro trial, starting at its first authenticated entitlement refresh after this rollout. Existing unpaid, expired and previously trialled accounts are included. Existing paid subscriptions and signed Apple trial dates retain priority and are not modified. The account trial requires no purchase and never auto-renews.

The grant is recorded separately from Apple subscription state in `UserEntitlement.accountTrialStartedAt` and `accountTrialEndsAt`. A database constraint requires both dates or neither and exactly seven days between them. The commerce account lock serializes first grants with subscription reconciliation; the stored dates are not reset by login, restore, webhook delivery, or reinstall. Existing users are granted lazily, so deployment does not consume their seven days before they return.

A derived access record overlays the Pro monthly plan only while the account trial is active and no stronger entitlement exists. AI reservations, feature middleware, invoices, PDF watermark rules, reminders and usage snapshots read the same effective access. Pro's rolling daily, weekly and monthly limits continue to apply. Expiry closes Pro actions while preserving manual projects, manual estimates and saved work.

The native login offer appears once per authenticated session after onboarding and authoritative entitlement loading. It has an immediately visible Continue button, a close button and swipe dismissal. Foreground refreshes do not reopen it. Paid subscribers and active Apple subscription trials skip this sales offer. Purchase and restore success require a subscription entitlement rather than merely finding the complimentary account trial.

The separate Apple introductory offer is changed to one week for both Pro products wherever available. Apple still determines eligibility for those subscription offers. The app displays Apple's actual selected offer and localized renewal price; the no-payment account trial is described separately. Existing Apple subscription periods are never extended or rewritten.

Validation and deployment results are recorded below after completion. Simulators remain closed.
