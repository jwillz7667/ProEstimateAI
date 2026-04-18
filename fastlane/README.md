# Fastlane

Automation for building, uploading to TestFlight, and pushing App Store Connect metadata for **ProEstimate AI**.

Everything authenticates with an App Store Connect API key — never an Apple ID password — so CI runs don't hit two-factor prompts.

---

## Lanes

| Lane | What it does |
| :--- | :--- |
| `bundle exec fastlane beta` | Bumps the build number to `latest_testflight + 1`, archives the app for release, uploads the build to TestFlight (no external distribution). |
| `bundle exec fastlane metadata` | Pushes `fastlane/metadata/**` (localized copy + URLs + review info) to App Store Connect. No binary. Does not submit. |
| `bundle exec fastlane submit` | Uploads metadata and submits the most recent build for App Store review (manual release). Does not auto-release. |

---

## One-time setup

### 1. Generate an App Store Connect API key

1. Open https://appstoreconnect.apple.com → **Users and Access** → **Integrations** → **App Store Connect API**.
2. Click **Generate API Key** (or **+**). Give it access level **App Manager** (or higher — **Admin** is fine for solo teams).
3. Download the `.p8` file when prompted. Apple **only lets you download it once** — save it somewhere safe.
4. Note the **Key ID** (10-char string under the name) and the **Issuer ID** (UUID shown above the keys list).

### 2. Local environment

Drop the key into the conventional location and export the three env vars. Add to `~/.zshrc`:

```bash
# fastlane / App Store Connect
export APP_STORE_CONNECT_API_KEY_ID="YOUR_KEY_ID"
export APP_STORE_CONNECT_API_KEY_ISSUER_ID="YOUR_ISSUER_UUID"
# Base64-encode the .p8 so the content can live in one line:
export APP_STORE_CONNECT_API_KEY_CONTENT="$(base64 -i ~/Downloads/AuthKey_YOUR_KEY_ID.p8)"
```

Move the downloaded `.p8` to `~/.appstoreconnect/private_keys/AuthKey_YOUR_KEY_ID.p8` for tools that read it directly.

### 3. Install Fastlane

```bash
bundle install
```

### 4. Smoke test

```bash
bundle exec fastlane metadata
```

If the command prints something like "Ready to upload" before any network call, your key is wired correctly.

---

## GitHub Actions — `TestFlight` workflow

`.github/workflows/testflight.yml` runs the `beta` lane on:
- any push of a tag matching `v*.*.*` (e.g. `git tag v1.0.1 && git push origin v1.0.1`), or
- manual dispatch from the Actions tab.

Required repository secrets (Repo → Settings → Secrets and variables → Actions → New repository secret):

| Secret name | Value |
| :--- | :--- |
| `APP_STORE_CONNECT_API_KEY_ID` | The 10-char Key ID. |
| `APP_STORE_CONNECT_API_KEY_ISSUER_ID` | The Issuer UUID. |
| `APP_STORE_CONNECT_API_KEY_CONTENT` | Base64 of the `.p8` file: `base64 -i AuthKey_XXXX.p8 \| pbcopy`. |

Cut a TestFlight build:

```bash
git tag v1.0.1
git push origin v1.0.1
```

The workflow will archive, upload, and attach the `.ipa` as a workflow artifact (kept for 7 days).

---

## Metadata you may want to edit before a real run

`fastlane/metadata/review_information/` contains placeholders you must replace before submitting for review:

- `demo_password.txt` — `REPLACE_WITH_REAL_DEMO_PASSWORD`. The password for the demo account Apple reviewers will use.
- `phone_number.txt` — `REPLACE_WITH_CONTACT_PHONE`. The reviewer contact number.

Localized copy (`en-US/`, `es-MX/`) is already filled in with production-ready text. Edit `description.txt`, `keywords.txt`, and the URLs as the product evolves; `bundle exec fastlane metadata` pushes changes without re-uploading a binary.
