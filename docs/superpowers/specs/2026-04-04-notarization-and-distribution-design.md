# Notarization & Dual Distribution Design

## Goal

Ship MarkdownQuickLook through two channels from one open-source codebase:

1. **GitHub Releases** — notarized zip, no Gatekeeper warnings, no App Data Protection dialogs
2. **Mac App Store** — submitted manually from Xcode when ready

## CI Secrets

Six GitHub repository secrets:

| Secret | Value |
|---|---|
| `DEVELOPER_ID_CERT_BASE64` | Developer ID Application certificate + private key exported as `.p12`, then base64-encoded |
| `DEVELOPER_ID_CERT_PASSWORD` | Password set when exporting the `.p12` |
| `NOTARY_KEY` | Contents of the `.p8` App Store Connect API key file |
| `NOTARY_KEY_ID` | Key ID from App Store Connect |
| `NOTARY_ISSUER_ID` | Issuer ID from App Store Connect |
| `KEYCHAIN_PASSWORD` | Arbitrary password for the temporary CI keychain |

Forks will not have these secrets. The workflow must handle this gracefully.

## Workflow Structure

`release.yml` is restructured into two jobs:

### Job 1: `test`

Unchanged from today. Runs all three test suites with ad-hoc signing. No secrets needed.

### Job 2: `release` (depends on `test`)

Steps:

1. **Set up keychain** — create a temporary keychain on the runner, import the Developer ID certificate from `DEVELOPER_ID_CERT_BASE64`, set it as the default keychain for codesigning.
2. **Build** — run `build-release.sh`, which detects the Developer ID certificate and signs with it.
3. **Notarize** — run `Scripts/notarize.sh`, which:
   - Writes the `.p8` API key to a temporary file
   - Submits the zip via `xcrun notarytool submit --apple-api-key --wait`
   - Staples the ticket onto the `.app` via `xcrun stapler staple`
   - Re-zips the stapled app
4. **Create GitHub release** — upload the notarized zip (same as today).

## Build Script Signing Modes

`build-release.sh` handles three contexts:

| Context | Signing | Detection |
|---|---|---|
| Local dev | Development certificate (automatic from project.yml) | Neither `CI` nor `DEVELOPER_ID_IDENTITY` set |
| CI with certificate | Developer ID Application | `CI=true` and `DEVELOPER_ID_IDENTITY` env var set |
| CI without certificate (forks) | Ad-hoc fallback | `CI=true` and no `DEVELOPER_ID_IDENTITY` |

The CI workflow sets `DEVELOPER_ID_IDENTITY` to the Common Name of the imported certificate (e.g., `Developer ID Application: Reza KAREGARAN (42QK7B5HYB)`).

`CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` remains for all release builds to strip `get-task-allow`.

## New Script: `Scripts/notarize.sh`

Accepts the zip path as an argument. Responsibilities:

1. Write the API key `.p8` to a temp file from `NOTARY_KEY` env var.
2. Extract the `.app` from the zip (needed for stapling).
3. Submit the zip to Apple: `xcrun notarytool submit "$ZIP" --apple-api-key "$KEY_FILE" --apple-api-key-id "$NOTARY_KEY_ID" --apple-api-issuer "$NOTARY_ISSUER_ID" --wait`.
4. On success, staple the `.app`: `xcrun stapler staple "$APP"`.
5. Re-zip the stapled `.app` to replace the original zip.
6. Clean up the temp key file.

Exits non-zero if notarization fails. The CI workflow surfaces the `notarytool log` output for debugging.

## Settings & App Group Restoration

Once notarization is verified working, a follow-up commit restores the app group and settings sharing:

- Add `com.apple.security.application-groups` back to the extension entitlements.
- Revert `PreviewViewController.renderPayload()` to read from `MarkdownSettingsStore().settings`.
- Remove the `DisclosureGroup` wrapper from the settings panel in `StatusView` — show it directly.

This is a separate step, done only after confirming the notarized build eliminates the App Data Protection dialog.

## Out of Scope

- **App Store submission automation** — done manually from Xcode. App Review requires manual approval anyway.
- **Sparkle / auto-update** — users re-download from GitHub Releases.
- **Hardened Runtime changes** — Developer ID signing implies hardened runtime automatically.
- **Provisioning profiles in CI** — Developer ID signing does not require them.

## File Changes Summary

| File | Change |
|---|---|
| `.github/workflows/release.yml` | Split into `test` + `release` jobs; add keychain setup, notarize step |
| `Scripts/build-release.sh` | Three-mode signing detection (local / CI+cert / CI+adhoc) |
| `Scripts/notarize.sh` | New script: notarize, staple, re-zip |
| `README.md` | Expand notarization section with full setup instructions |
| Extension entitlements | Restore app group (after notarization verified) |
| `PreviewViewController.swift` | Restore settings reading (after notarization verified) |
| `StatusView.swift` | Remove DisclosureGroup deferral (after notarization verified) |
