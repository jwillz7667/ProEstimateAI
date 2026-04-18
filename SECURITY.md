# Security Policy

ProEstimate AI takes the security of its users and their data seriously. This document describes how to report a suspected vulnerability and what to expect from us in return.

---

## Reporting a vulnerability

**Do not open a public GitHub issue, pull request, or discussion post for a security concern.** Public disclosure before a fix is available puts users at risk.

Instead, report the issue privately via one of the following channels:

- **Email:** `security@proestimate.ai`
- **Encrypted channels:** available on request; contact the address above for our PGP key.

Please include, at minimum:

1. A description of the vulnerability and its potential impact.
2. Clear reproduction steps, including the request/response pairs, affected endpoints, or iOS flows.
3. Any proof-of-concept code, screenshots, or network captures that help us confirm the issue.
4. Your name and (optional) handle for credit in the resolution note.

We ask that reporters act in good faith and avoid:

- Accessing, modifying, or deleting data belonging to other users.
- Performing destructive testing (for example, deleting records, triggering rate-limit bans across shared infrastructure).
- Publicly disclosing the vulnerability before we have had a reasonable opportunity to investigate and remediate.

## Our commitments

- **Acknowledgement** within two business days of receipt.
- **Triage** within seven calendar days: severity assessment, affected versions, and an initial remediation plan.
- **Status updates** at least every seven calendar days until resolution.
- **Credit** in the published resolution notes, if you wish to be named.

## Scope

In-scope assets:

- iOS application binary distributed on the App Store under bundle identifier `Res.ProEstimate-AI`.
- Backend API hosted at the production domain belonging to the company.
- The web property hosted at the company's marketing domain (once live).
- Any infrastructure configuration committed to this repository.

Out-of-scope (already known or not actionable):

- Findings derived exclusively from automated scanner reports without a working proof of concept.
- Reports about missing security headers on marketing pages that do not process user data.
- Social engineering of employees or contractors.
- Denial-of-service attacks, volumetric testing, or anything that impacts availability for other users.
- Vulnerabilities in third-party dependencies for which an upstream fix has not yet been released.

## Supported versions

Only the latest published version of each target receives security fixes:

| Target | Supported | Notes |
| :----- | :-------- | :---- |
| iOS app | Current App Store release | Older TestFlight builds are not supported. |
| Backend API | `main` branch and the currently deployed tag | |
| Web | `main` branch | |

## Responsible disclosure safe harbor

We will not pursue legal action against researchers who:

- Report vulnerabilities in good faith through the channels above.
- Act within the scope and restrictions defined in this document.
- Give us a reasonable opportunity to remediate before any public disclosure.

## Hall of fame

We maintain a list of researchers who have responsibly disclosed vulnerabilities that led to a shipped fix. If you would like to be named, let us know when you report the issue.
