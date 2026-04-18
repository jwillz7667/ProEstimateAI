# Contributing to ProEstimate AI

ProEstimate AI is a proprietary codebase. Contributions are restricted to authorized team members and approved contractors. This document captures the engineering standards, workflows, and review expectations that apply to every change.

Outside contributions are not accepted. Do not open pull requests from forks unless you have a signed written agreement with the company.

---

## Table of contents

- [Ground rules](#ground-rules)
- [Local setup](#local-setup)
- [Branching strategy](#branching-strategy)
- [Commit messages](#commit-messages)
- [Pull requests](#pull-requests)
- [Code review](#code-review)
- [iOS engineering standards](#ios-engineering-standards)
- [Backend engineering standards](#backend-engineering-standards)
- [Testing expectations](#testing-expectations)
- [Release process](#release-process)
- [Incident response](#incident-response)

---

## Ground rules

- Production-only code. No placeholders, stubs, or pseudo-code. No mock data shipped in production paths.
- Prefer editing existing files over creating new ones. Do not introduce abstractions that are not required by the current change.
- Do not commit secrets, credentials, `.env` files, customer data, or any Personally Identifiable Information.
- Do not skip pre-commit hooks, CI gates, or code review without an approved emergency exception.
- If a design decision is ambiguous, raise it in the relevant channel before coding. Do not guess.

## Local setup

Refer to the [README](./README.md#getting-started) for per-target setup commands. A one-time pass that every contributor should do:

```bash
# At the repo root
cp backend/.env.example backend/.env            # fill in secrets
cd backend && npm ci && npx prisma generate && npx prisma migrate dev
cd ../web && npm ci
```

Pin Node via `nvm use` (or `fnm use`) at the repo root — the pinned version lives in `.nvmrc`.

## Branching strategy

- `main` is always in a deployable state. CI must pass before merge.
- All work happens on short-lived feature branches cut from `main`. Suggested naming:
  - `feature/<scope>` — new functionality
  - `fix/<scope>` — bug fixes
  - `chore/<scope>` — tooling, dependencies, non-functional changes
  - `refactor/<scope>` — internal cleanup without behavior change
- Rebase onto `main` before opening a pull request. Resolve conflicts locally.
- Delete the branch after merge. Do not reuse branch names.

## Commit messages

Use the imperative mood, present tense, short subject line (<= 72 characters), and an optional body that explains the *why*. Reference tickets or issues where applicable.

```
Add invoice-creation context menu on project estimates

Replaces the standalone InvoiceCreationSheet, which required typing an
estimate ID manually. Creation now flows through the project detail view
and reuses the feature-gate coordinator for paywall enforcement.
```

Group logically related changes into a single commit. Avoid "wip", "misc", or noise commits in history — squash them locally before pushing.

## Pull requests

Every pull request must include:

- A clear title scoped to the change.
- A summary of *what* changed and *why* (the body of `PULL_REQUEST_TEMPLATE.md`).
- Screenshots or screen recordings for user-facing iOS or web changes.
- A manual test plan with steps that a reviewer can follow.
- Links to any related issues, specs, or design docs.

Merge requirements:

- All CI checks green.
- At least one approving review from a code owner.
- No unresolved review comments.
- The branch is rebased on top of `main`.

Use squash merge by default to keep `main` history linear. Merge commits are reserved for release branches.

## Code review

Reviewers are expected to verify:

- Correctness against the description.
- Adherence to the conventions documented below.
- Tests exercise the behavior added or changed.
- No secrets, debug logging, commented-out code, or dead code left behind.
- Localizable strings added to `Localizable.xcstrings` (iOS) when user-facing copy changes.

Authors are expected to:

- Keep pull requests focused. Prefer multiple small PRs over one sprawling one.
- Respond to comments within one business day.
- Push review fixes as new commits (not amends) so reviewers can see what changed.

## iOS engineering standards

- Swift 6 concurrency. `@Observable` for stateful classes; never `ObservableObject` or `@Published`.
- Protocol-first services: `*ServiceProtocol: Sendable` with `Live*Service` and `Mock*Service` implementations. Default-parameter injection, no global DI container.
- Business logic lives in ViewModels. Views are declarative and free of network, persistence, or business code.
- Use design tokens (`ColorTokens`, `SpacingTokens`, `TypographyTokens`, `RadiusTokens`) and shared components (`GlassCard`, `PrimaryCTAButton`, `StatusBadge`, `CurrencyText`). Do not hardcode colors, fonts, radii, or spacing.
- Booleans are named as questions: `isLoading`, `hasCompleted`, `canGenerate`.
- Errors are `enum` types conforming to `LocalizedError`.
- Money is `Decimal`, not `Double`. Format with the shared `CurrencyText` view or the money typography variants.
- SwiftData cached models use `@Attribute(.unique)` for the remote id. Never invent local-only ids.
- Navigation uses the per-tab `AppRouter` paths. Use `.sheet(item:)` for optional-id-driven sheets; `sheet(isPresented:)` is acceptable only when the content has no required identifier.

## Backend engineering standards

- Strict TypeScript. No `any`, no unsafe `as` casts at API boundaries.
- Every module follows `route -> validator -> controller -> service -> dto`. Do not skip layers.
- Validate every request body, query, and URL parameter with Zod via the shared `validate(schema, source)` middleware.
- Throw typed `AppError` subclasses (`NotFoundError`, `ValidationError`, `AuthorizationError`, `PaywallError`, `ConflictError`). Never raw `throw new Error(...)`.
- Wrap multi-table writes in `prisma.$transaction` when atomicity matters (usage consumption, number auto-increment, purchase reconciliation).
- DTO functions are the single place where Prisma models cross into API responses. Convert `Decimal` to `Number`, `DateTime` to ISO string, enums to lowercase.
- snake_case on the wire. camelCase inside TypeScript.
- Respond with `sendSuccess(res, data, meta)` or throw an `AppError` and let the error handler format the envelope.
- Rate limit sensitive routes. Auth endpoints get the stricter `authRateLimit`.

## Testing expectations

- Every bug fix includes a test that would have caught the bug.
- Every new feature includes coverage for the happy path and at least one failure path.
- Backend: integration tests against a real test database, not mocked Prisma. Mocks have drifted from reality before and caused production regressions.
- iOS: unit-test the ViewModel layer using `Mock*Service` implementations. UI tests cover critical user flows (sign-in, project creation, estimate creation, paywall purchase).
- Run the full suite locally before requesting review, even if CI is green.

## Release process

Releases are tagged from `main` using semver (`vMAJOR.MINOR.PATCH`).

1. Update `CHANGELOG.md` under the `Unreleased` section with the changes being shipped.
2. Move the `Unreleased` block to a new version section with today's date.
3. Create an annotated tag: `git tag -a vX.Y.Z -m "vX.Y.Z"`.
4. Push the tag: `git push origin vX.Y.Z`.
5. The backend auto-deploys to Railway on push to `main`. For iOS, archive via Xcode and submit to App Store Connect.

Hotfixes are branched from the previous release tag, tagged as a patch bump, and merged back to `main`.

## Incident response

If a production incident is suspected:

1. Page the on-call engineer via the standard escalation channel.
2. Do not attempt a hotfix without coordination.
3. Capture timestamps, affected scope, and any relevant logs in a shared incident doc.
4. After mitigation, write a blameless post-mortem within 48 hours covering: timeline, root cause, impact, mitigation, follow-up actions.

Never bypass review or CI to ship a fix. An incorrect hotfix that makes the outage worse is the default outcome when shortcuts are taken.
