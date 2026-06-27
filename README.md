# Mailbell

<p align="center">
  <img src="Resources/logo.png" alt="Mailbell logo" width="128">
</p>

## What Mailbell Is

Mailbell is a local, notification-first Gmail companion for macOS. It sits in the menu bar, signs in with a Google OAuth Desktop client you own, stores tokens in Keychain, connects to Gmail IMAP with XOAUTH2, watches `INBOX` with IMAP `IDLE`, fetches minimal headers plus bounded sanitized previews, posts native notifications, and opens Gmail Web for reading and mail management.

Current implemented scope:

- New Gmail inbox notifications.
- Pending menu-bar review with sender, subject, sent date, account, Gmail identifiers when available, and bounded sanitized preview text.
- Gmail Web opening for notifications, pending items, and account actions.
- Server-backed `Mark as Read` for pending items Mailbell already surfaced, using IMAP `UID STORE +FLAGS.SILENT (\\Seen)`.

Not implemented today: full body viewing, reply, archive, delete, move, labels, compose, attachments, a hosted backend, public website, gh-pages flow, Sparkle auto-update, App Store flow, analytics relay, or content polling as the primary new-mail mechanism.

## Privacy And OAuth Scope

Mailbell uses the Gmail IMAP XOAUTH2 transport. Google documents `https://mail.google.com/` as the scope for IMAP, POP, and SMTP OAuth access, and that scope is broad even though Mailbell intentionally fetches only the smallest useful notification/menu data.

Requested OAuth scopes:

| Scope | Why Mailbell requests it |
| --- | --- |
| `https://mail.google.com/` | Required for Gmail IMAP XOAUTH2 and the server-backed mark-as-read command. Narrower Gmail API scopes do not authenticate this IMAP transport. |
| `openid` | Required for the OpenID Connect user info call after sign-in. |
| `email` | Lets Mailbell read the signed-in Gmail address and authenticate IMAP as that user. |

Privacy rules:

- Use your own Google Cloud project and OAuth Desktop client.
- Real OAuth config lives only in `.env`, shell environment, or the copied app bundle generated on your Mac.
- `.env` is ignored by git and must stay untracked.
- Refresh tokens and access-token cache are stored in macOS Keychain only.
- Mailbell does not fetch attachments or full message bodies. Preview fetches are bounded to `BODY.PEEK[TEXT]<0.8192>` and sanitized locally before display.
- For private/local use, you own the Cloud project and OAuth client. For broader public distribution, Google verification requirements may apply because `https://mail.google.com/` is a restricted Gmail scope.

Current official references:

- [Google OAuth 2.0 for iOS & Desktop Apps](https://developers.google.com/identity/protocols/oauth2/native-app)
- [Gmail XOAUTH2 protocol for IMAP, POP, and SMTP](https://developers.google.com/workspace/gmail/imap/xoauth2-protocol)
- [Gmail API scope classifications](https://developers.google.com/workspace/gmail/api/auth/scopes)

## Requirements

- macOS 26 or newer.
- Xcode Command Line Tools or a Swift toolchain that can build this SwiftPM package.
- `make`, `python3` with `pip`, `xcrun`, `codesign`, `hdiutil`, and `spctl` from the macOS toolchain.
- Optional for `make check`: `swiftlint` and `swiftformat`.
- Optional for public release outside the Mac App Store: Apple Developer Program membership, a Developer ID Application certificate, and `notarytool` credentials stored in Keychain.

Local development, `make install`, and local `make dmg` do not require an Apple Developer account; they use ad-hoc signing by default.

## One-Time Setup

### Google Cloud OAuth Desktop Client

Create or select a Google Cloud project you control.

1. Configure the OAuth consent screen.
2. For personal Gmail or non-Workspace use, choose `External`; for a Workspace-owned project, choose `Internal` only if all sign-ins are from that organization.
3. For day-to-day personal use, publish the consent screen to `In production` after setup. Use `Testing` only for short validation.
4. Add only the scopes Mailbell requests: `https://mail.google.com/`, `openid`, and `email`.
5. Create an OAuth Client ID with application type `Desktop app`.
6. Copy the Desktop client ID. It should end with `.apps.googleusercontent.com`.

Mailbell uses Google's installed-app flow with PKCE and a temporary `http://127.0.0.1:<port>/oauth/callback` loopback redirect. The callback server binds only to IPv4 loopback with an OS-assigned dynamic port. Do not create a Web app client, hosted redirect site, or OAuth domain website for this fork.

`MAILBELL_GOOGLE_CLIENT_SECRET` is optional. Leave it blank unless Google shows a Desktop client secret or token exchange fails without it; if you do set it, use the secret from the same Desktop OAuth client.

### Local .env

Create the private local configuration file:

```bash
cp .env.example .env
$EDITOR .env
```

Supported `.env` keys:

```bash
MAILBELL_GOOGLE_CLIENT_ID=123456789012-abcde12345mailbellxyz.apps.googleusercontent.com
MAILBELL_GOOGLE_CLIENT_SECRET=
MAILBELL_BUNDLE_ID=com.johndoe.mailbell
MAILBELL_CODE_SIGN_IDENTITY=Developer ID Application: John Doe (9A1B2C3D4E)
MAILBELL_NOTARY_KEYCHAIN_PROFILE=mailbell-notary
```

Only the first three are needed for normal local development and local packaging. `MAILBELL_BUNDLE_ID` controls the packaged app identity and Keychain namespace; changing it after signing in means you may need to sign in again.

Mailbell is always named `Mailbell`. The product name, DMG volume name, version, build number, and release DMG filename are repo/release metadata, not user-specific `.env` config.

### Optional Apple Developer ID Signing Setup

Run this once on the Mac used for public release builds:

```bash
make setup-release-signing
```

The helper lists available `Developer ID Application` certificates, lets you choose or confirm the exact `MAILBELL_CODE_SIGN_IDENTITY`, and creates or updates the `notarytool` Keychain profile. The notary profile stores Apple notarization credentials in Keychain; `.env` stores only the profile name.

Apple signing/notarization references:

- [Signing Mac software with Developer ID](https://developer.apple.com/developer-id/)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [Resolving common notarization issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues)

Important distinction: ad-hoc signing is enough for local dev on your Mac. Developer ID signing plus notarization is the modern flow for distributing macOS software outside the Mac App Store. `notarytool` submits the signed DMG to Apple, and `stapler` attaches the accepted notarization ticket to the DMG. Apple supports notarizing distributed file types including DMG.

## Daily Development Flow

Use `main` for this personal fork unless you intentionally create a focused branch for a separate task.

```bash
git status --short --branch
make build
make test
# edit code
make check
git status --short --branch
git add ...
git commit -m "feat: ..."
git push origin main
```

Useful targets:

```bash
make help
make build
make test
make check
make run
make icons
```

`make run` launches the unbundled SwiftPM executable. Use `make install` for normal local use because notifications, login item behavior, app identity, and bundle resources require an installed app bundle.

`make icons` regenerates icon PNGs and `Resources/AppIcon.icns` from `Resources/logo.png` into `.build/icon-gen` first, then overwrites tracked icon files only when bytes differ. Running it repeatedly should not dirty the repo unless generated icon content actually changed.

## Local Install Flow

Generate and install a local ad-hoc signed app bundle:

```bash
make install
open /Applications/Mailbell.app
```

`make install` builds the release executable for the selected architecture, copies it into `/Applications/Mailbell.app`, injects OAuth and bundle config into the copied `Info.plist`, compiles resources, ad-hoc signs the app, and registers it with LaunchServices.

Packaging defaults to `ARCH=arm64`. On Intel Macs:

```bash
ARCH=x86_64 make install
```

After changing `.env`, rerun `make install` so the installed bundle receives the updated copied config.

## Local DMG Flow

Build a local/test drag-to-Applications DMG:

```bash
make dmg
```

`make dmg` is for local packaging validation. It uses ad-hoc signing by default and writes:

```text
.build/Install Mailbell.dmg
```

This local DMG is not the public notarized release artifact. It mounts as `Install Mailbell`, contains `Mailbell.app` plus an `Applications` shortcut, and may install the pinned build-only `dmgbuild==1.6.5` helper into `.build/dmg-python-tools` for deterministic Finder layout. That helper is not bundled into Mailbell.

## Release Flow

`make release` is the public distribution flow for this fork. It requires:

- clean worktree
- `HEAD` exactly on one release tag matching `vX.Y.Z`
- OAuth config in `.env` or shell
- `MAILBELL_CODE_SIGN_IDENTITY`
- `MAILBELL_NOTARY_KEYCHAIN_PROFILE`
- Developer ID certificate available in the signing keychain
- notarytool profile already stored in Keychain

Release metadata is resolved from the exact tag and CI environment:

- `v1.0.0` becomes `VERSION=1.0.0`
- build number comes from common CI build-number variables when present, otherwise `git rev-list --count HEAD`
- output DMG name is `Mailbell-<VERSION>.dmg`
- DMG volume name is `Install Mailbell`

Release commands:

```bash
git status --short --branch
make check
git tag -a v1.0.0 -m "Release v1.0.0"
make release
git push origin main
git push origin v1.0.0
```

Output:

```text
.build/Mailbell-1.0.0.dmg
```

`make release` builds the app, injects OAuth config plus `CFBundleShortVersionString` and `CFBundleVersion`, compiles resources, Developer ID signs the `.app`, verifies the app signature, creates the DMG, Developer ID signs the DMG, verifies the DMG signature, submits the DMG with `xcrun notarytool submit --wait`, staples it with `xcrun stapler staple`, validates the stapled DMG, and prints the final artifact path.

A DMG does not provide automatic updates by itself. Users must install a new DMG manually unless a separate updater system is designed and implemented in a future explicit task.

### Practical Example: Feature To Release

Assume the one-time Google OAuth, `.env`, Developer ID certificate, and notarytool Keychain profile setup already exists. This example adds a feature, installs it locally for a quick manual check, then ships version `1.1.0`.

Start clean and update local `main`:

```bash
git status --short --branch
git pull --ff-only origin main
make build
make test
```

Edit the feature and its tests. During the edit loop, use the smallest useful validation:

```bash
make build
make test
make install
open /Applications/Mailbell.app
```

If the feature changed `Resources/logo.png` or icon inputs, regenerate icons and prove the second run is stable:

```bash
make icons
git status --short -- Resources/Assets.xcassets/AppIcon.appiconset Resources/AppIcon.icns
make icons
git status --short -- Resources/Assets.xcassets/AppIcon.appiconset Resources/AppIcon.icns
```

Finish the feature commit:

```bash
make check
git status --short --branch
git add -p
git diff --cached --stat
git commit -m "feat: describe the feature"
git push origin main
```

Create the tagged, signed, notarized release DMG:

```bash
git status --short --branch
git tag -a v1.1.0 -m "Release v1.1.0"
make release
git push origin main
git push origin v1.1.0
```

The release artifact is:

```text
.build/Mailbell-1.1.0.dmg
```

If publishing through GitHub Releases with `gh` installed:

```bash
gh release create v1.1.0 .build/Mailbell-1.1.0.dmg \
  --target main \
  --title "Mailbell 1.1.0" \
  --notes "Describe the feature and any manual upgrade notes."
```

If `make release` finds a code problem after the tag is created, fix the code, commit the fix, delete the local bad tag, and create the tag again on the corrected commit:

```bash
git tag -d v1.1.0
make check
git add -p
git commit -m "fix: address release issue"
git tag -a v1.1.0 -m "Release v1.1.0"
make release
```

## Publishing Checklist

Before publishing a DMG:

- `git status --short --branch` is clean.
- `.env` contains only local/private values and is ignored by git.
- `make check` passes.
- `make icons` does not dirty `Resources/Assets.xcassets/AppIcon.appiconset` or `Resources/AppIcon.icns`.
- The release tag matches `vX.Y.Z` and points at the intended commit.
- `make release` completed successfully.
- The final DMG path is `.build/Mailbell-<VERSION>.dmg`.
- Push `main` and the tag only after the release build succeeds.
- Do not commit `.env`, secrets, tokens, logs with secrets, `.app` bundles, `.dmg` files, or release artifacts.

## Troubleshooting

### Missing OAuth Credentials

Symptoms:

- `make install`, `make dmg`, or `make release` prints `set MAILBELL_GOOGLE_CLIENT_ID`.
- The app shows `Google OAuth setup required`.

Fix:

- Fill `.env` or export `MAILBELL_GOOGLE_CLIENT_ID`.
- Reinstall or rebuild the app bundle after changing packaged credentials.

### Invalid Client ID Or Optional Secret

Symptoms:

- The packaging script says the client ID must end in `.apps.googleusercontent.com`.
- Google token exchange fails after browser sign-in.

Fix:

- Use an OAuth client of type `Desktop app`.
- Do not use a Web, iOS, Android, Chrome, or service-account credential.
- Leave `MAILBELL_GOOGLE_CLIENT_SECRET` blank unless your Desktop client requires it.

### Redirect Or Loopback Errors

Mailbell starts a temporary local loopback listener and sends Google a `http://127.0.0.1:<port>/oauth/callback` redirect URI.

Fix:

- Let Mailbell open the system browser.
- Avoid VPN/firewall rules that block local loopback traffic.
- Recreate the OAuth client as `Desktop app` if you used another client type.

### Gmail IMAP Disabled Or Blocked

Mailbell uses Gmail IMAP at `imap.gmail.com:993` over SSL.

Fix:

- In Gmail Web, check `Settings > See all settings > Forwarding and POP/IMAP` and enable IMAP if needed.
- For Google Workspace accounts, check admin policies for IMAP, third-party app access, and restricted OAuth scopes.

### Token Revoked Or Reauth Required

Symptoms:

- Account status becomes `Reconnect needed`.
- Refresh returns `invalid_grant`.

Fix:

- In `Settings > Accounts > <email>`, choose `Sign in again`.
- If the account is stale or wrong, choose `Remove Account` and add it again.
- If your OAuth consent screen is still in `Testing`, move it to `In production` for day-to-day personal use or expect periodic reauth depending on Google policy.

### Signing Or Notarization Fails

Fix:

- Run `make setup-release-signing` again and confirm the exact Developer ID Application identity.
- Confirm the certificate appears in `security find-identity -v -p codesigning`.
- Confirm `MAILBELL_NOTARY_KEYCHAIN_PROFILE` matches the profile stored by `xcrun notarytool store-credentials`.
- Read the notary log path printed under `artifacts/notarization/` if notarization fails. Successful notarization removes the temporary log.
- Use `xcrun stapler validate <dmg>` and `spctl -a -t open --context context:primary-signature -vv <dmg>` to inspect the final DMG.

### Notifications Do Not Appear

Fix:

- Use `make install` and run `/Applications/Mailbell.app`.
- Check `System Settings > Notifications > Mailbell`.
- Keep Mailbell running in the menu bar.

### Start At Login Does Not Work

The `Start at login` toggle uses `SMAppService` and requires a bundled app.

Fix:

- Install with `make install`.
- Toggle `Start at login` in `Settings > Behavior`.
- If macOS asks for approval, check `System Settings > General > Login Items`.

## Maintenance Notes

Important paths:

- `Package.swift`: SwiftPM package and macOS 26 minimum.
- `Sources/Mailbell/App/`: menu bar app, Settings, login item, app state.
- `Sources/Mailbell/Auth/`: OAuth config/client, loopback redirect, Keychain token storage.
- `Sources/Mailbell/IMAP/`: Gmail IMAP XOAUTH2, mailbox selection, IDLE, metadata/body-preview fetches, parser, preview sanitizer, and read marker command.
- `Sources/Mailbell/Service/`: account supervision, monitor state machine, UID checkpoints, pending store, unread reconciliation, and mark-as-read orchestration.
- `Sources/Mailbell/Notify/`: native notification authorization and posting.
- `Sources/Mailbell/Webmail/`: browser/profile routing for Gmail Web.
- `Resources/`: app icon and base `Info.plist`.
- `Scripts/` and `Makefile`: local build, install, DMG, icon, bundle injection, signing, notarization, and release paths.
- `Tests/MailbellTests/`: focused tests for stores, OAuth config, scripts, IMAP parsing, notifications, providers, and webmail routing.

Keep the standard SwiftPM shape: one executable target under `Sources/Mailbell`, one test target under `Tests/MailbellTests`, and domain folders below `Sources/Mailbell`. Do not add a website, gh-pages flow, hosted OAuth domain site, public marketing site, Sparkle updater, App Store flow, hosted backend, or broad Gmail API abstraction unless that is the explicit task.

To remove local app access:

```bash
make uninstall
```

Then remove each account in Mailbell settings and revoke the OAuth grant from your Google Account security settings if desired. Manual Keychain cleanup should be a last resort; search Keychain Access for the bundle id configured with `MAILBELL_BUNDLE_ID`.

## License

MIT. See [LICENSE](LICENSE). Attribution and third-party notices are in [ATTRIBUTIONS.md](ATTRIBUTIONS.md).
