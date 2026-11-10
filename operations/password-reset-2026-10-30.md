# Password recovery repair — October 30, 2026

The previous email linked to an API URL without a reset page. Recovery now uses the public website's dedicated `/reset-password` page and the existing password-reset API.

## Behavior

- `PUBLIC_WEB_BASE_URL` defaults to `https://proestimateai.com`; it accepts HTTP(S) URLs without embedded credentials. The API's own origin is no longer used for reset links.
- New email links carry the token in `#token=…`, keeping it out of HTTP request targets and access logs. The form reads the fragment only in the browser, removes it from the address bar, and retains the proof only in memory. Legacy query links are accepted, although their initial request necessarily contains the query.
- The reset form validates the server's password-strength/72-byte rules and confirmation, prevents duplicate submissions, and handles network/rate-limit/expired-link failures. Missing or expired links can request a new email through the normal generic forgot-password response. Tokens and passwords are never stored in browser storage.
- The page and requests use `no-referrer`; the response is private/no-store and noindex/nofollow/noarchive. The root layout contains no analytics scripts. New fragment links therefore never enter the server-rendered HTML or URL logs.
- The reset page has its own centered responsive card with the actual app icon and orange/charcoal palette. Explicit `max-w-[440px]` avoids a repository theme collision where `max-w-md` resolves to 16 pixels because of `--spacing-md`.
- Updated stale homepage provider names, conflicting category counts and iOS-version copy to match the current product without hardcoded provider implementation details.

## Verification

- Backend production build, targeted lint, and all **226 unit tests** passed, including five reset-link cases. The existing PostgreSQL single-use/concurrent password-reset regression also passed on disposable local PostgreSQL at `127.0.0.1:55439`.
- Web production build and all **20 unit tests** passed. Lint has zero errors and two existing warnings (homepage image optimization and an unused WebGL import).
- A real browser against a local production Next server and synthetic API verified password mismatch handling, successful reset, show/hide controls, expired-link recovery, generic email confirmation, and a later fragment-only email link reinitializing the form. The synthetic API saw no proof in request URLs and no `Referer` header. No real email or production password change was performed.
- Actual HTTP response: 200; `Cache-Control: private, no-store, max-age=0`; `Referrer-Policy: no-referrer`; `X-Robots-Tag: noindex, nofollow, noarchive`. Robots metadata matches.
- Visual inspection at 390 × 844 and 1440 × 1000 confirmed a 350-pixel mobile card, a centered 440-pixel desktop card and no horizontal overflow. Mobile request, expired and success states were captured separately.

Final screenshots are under `validation-2026-10-30/password-reset-{mobile,desktop,request-mobile,expired-mobile,success-mobile}.png`. The local browser used an explicitly overridden fixture API base; deploy from the tracked source so Railway rebuilds with its production API variables.

Receiving a real reset email and completing a password change with a controlled real account remain delivery checks after domain/key configuration. The browser fixtures are not evidence of email delivery.
