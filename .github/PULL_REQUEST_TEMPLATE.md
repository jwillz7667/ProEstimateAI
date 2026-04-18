<!--
Thanks for opening a pull request. Please fill out the sections below.
PRs missing a clear summary or test plan will be sent back for rework.
-->

## Summary

<!-- What does this change do, and why? One or two paragraphs. -->

## Type of change

- [ ] Feature
- [ ] Bug fix
- [ ] Refactor (no behavior change)
- [ ] Chore / tooling / dependencies
- [ ] Documentation

## Scope

- [ ] iOS app
- [ ] Backend API
- [ ] Web (marketing)
- [ ] Infrastructure / CI

## Related issues / tickets

<!-- Link the issue or spec this PR addresses. -->

Closes #

## Test plan

<!--
Steps a reviewer can follow locally or in simulator to verify the change.
Include both the happy path and at least one failure path.
-->

1.
2.
3.

## Screenshots / recordings

<!-- Required for any user-facing iOS or web change. Remove this section for backend-only PRs. -->

## Checklist

- [ ] Branch is rebased on latest `main`
- [ ] CI is green locally (lint, typecheck, build, tests)
- [ ] New user-facing strings added to `Localizable.xcstrings` (iOS) and translated to Spanish
- [ ] API changes updated on both sides (route + DTO + iOS endpoint case + model + service + ViewModel)
- [ ] Database schema changes include a Prisma migration
- [ ] `CHANGELOG.md` updated under the `Unreleased` section
- [ ] No secrets, debug logging, or commented-out code
- [ ] Documentation (README, CONTRIBUTING, module README) updated where relevant
