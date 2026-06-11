# Mailbell

<p align="center">
  <img src="Resources/logo.png" alt="Mailbell logo" width="128">
</p>

Mailbell is a personal macOS menu bar Gmail notifier. It is a local bridge from your Google account to native macOS notifications: Google OAuth, Keychain tokens, Gmail IMAP XOAUTH2, `INBOX` `SELECT`, IMAP `IDLE`, header-only fetches, native notifications, and Gmail Web for reading or managing mail.

## Personal-Use Scope

This fork is for private local use on your own Mac.

- It is a menu bar notifier, not a full email client.
- It does not provide mailbox browsing, body reading, attachment reading, reply, archive, delete, label, or compose flows.
- It watches Gmail `INBOX` with IMAP `IDLE`; it does not use content polling as the primary notification mechanism.
- It opens Gmail Web when you click a notification or choose `Open Gmail`.
- It has no cloud relay, hosted backend, analytics relay, public website, gh-pages flow, or public release pipeline.

## Privacy And Security Model

You must create and use your own Google OAuth Desktop credentials. This fork does not ship or fall back to any shared OAuth client.

- Real OAuth credentials live only in your shell, local `.env`, or a locally injected app bundle.
- `.env` is ignored by git. `.env.example` contains variable names only.
- Access and refresh tokens are stored in the macOS Keychain using service `com.perso.mailbell`.
- Non-secret account metadata, UI state, webmail preferences, and IMAP checkpoints are stored in `UserDefaults`.
- Notification content is built from headers only: account, sender, subject, date, UID, and Gmail thread/message identifiers when available.
- IMAP fetches use `BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE)]`; message bodies and attachments are not fetched.

Requested OAuth scopes:

| Scope | Why Mailbell requests it |
| --- | --- |
| `https://mail.google.com/` | Required by Gmail IMAP XOAUTH2. This is a broad restricted Gmail scope even though Mailbell only fetches headers. Do not replace it with narrower Gmail API scopes unless the transport changes away from IMAP. |
| `openid` | Required for the OpenID Connect user info call after sign-in. |
| `email` | Lets the app read the signed-in Gmail address, label the account, and authenticate IMAP as that user. |

The broad Gmail scope is the main privacy tradeoff of this design. Gmail's narrower API scopes, such as `gmail.metadata`, do not authenticate this IMAP implementation.

## Requirements

- macOS 13 Ventura or newer.
- Xcode Command Line Tools or a Swift toolchain that can build the SwiftPM package.
- `make`, `python3`, `xcrun`, and `codesign` from the macOS toolchain for local install/DMG packaging.
- Optional: `swiftlint` and `swiftformat` if you run `make lint`, `make format`, or `make check`.

No Apple Developer account is required for local use. `make install` and `make dmg` use ad-hoc signing by default.

## Google Cloud Setup

Use a Google account and Cloud project that you control.

1. Create or select a project in Google Cloud Console.
2. Open the OAuth consent screen setup.
3. Choose the consent/audience mode:
   - Personal Gmail or non-Workspace use: choose `External`. For day-to-day use, publish the app `In production` after setup. Use `Testing` only for short validation.
   - Google Workspace-owned project: choose `Internal` only if the project belongs to your Workspace or Cloud Identity organization and you will sign in only with accounts from that organization.
4. If you temporarily leave the app in `Testing`, add your Gmail address as a test user.
5. Fill required app name/support email fields with values you control. Leave optional app-domain fields blank if the console permits it.
6. Add only the scopes this app requests:
   - `https://mail.google.com/`
   - `openid`
   - `email`
7. Do not set up Pub/Sub, Gmail API push watches, SMTP, a hosted redirect service, or public website pages for this app. Mailbell connects directly to Gmail IMAP. If Google Cloud requires an API to be enabled for scope configuration, enable only what the console requires; Mailbell does not call Gmail REST API endpoints.
8. Create an OAuth Client ID with application type `Desktop app`.
9. Copy the Client ID and Client Secret. The Client ID should end with `.apps.googleusercontent.com`.

The app uses Google's installed-app OAuth flow with PKCE and a random local loopback redirect. Do not create a Web app client for this fork.

## Local Configuration

Create a private `.env` from the example and fill in your own Desktop client values:

```bash
cp .env.example .env
$EDITOR .env
```

Example `.env` content:

```bash
MAILBELL_GOOGLE_CLIENT_ID=your-desktop-client-id.apps.googleusercontent.com
MAILBELL_GOOGLE_CLIENT_SECRET=your-desktop-client-secret
```

You can use shell environment variables instead:

```bash
export MAILBELL_GOOGLE_CLIENT_ID="your-desktop-client-id.apps.googleusercontent.com"
export MAILBELL_GOOGLE_CLIENT_SECRET="your-desktop-client-secret"
```

Packaging commands read environment variables first, then `.env`. `Scripts/inject_oauth_config.sh` validates the values and writes only these expected bundle keys into the copied app `Info.plist`:

- `MailbellGoogleClientID`
- `MailbellGoogleClientSecret`
- `CFBundleIdentifier`
- `CFBundleName`
- `CFBundleDisplayName`

The source `Resources/Info.plist` should not contain real credentials.

Useful checks before committing:

```bash
git check-ignore .env
git status --short -- .env .env.example Resources/Info.plist README.md
```

## Build, Test, Run, Install

List available targets:

```bash
make help
```

Build and test:

```bash
make build
make test
```

Run directly from SwiftPM:

```bash
make run
```

`make run` is useful for development, but it runs an unbundled executable. Native notifications and login item behavior require a bundled app identity, so use `make install` for normal local use.

Install an ad-hoc signed app bundle to `/Applications/Mailbell.app`:

```bash
make install
open /Applications/Mailbell.app
```

Build a local DMG:

```bash
make dmg
```

Architecture notes:

- Packaging defaults to `ARCH=arm64`.
- On Intel Macs, use `ARCH=x86_64 make install` or `ARCH=x86_64 make dmg`.
- The Makefile builds one architecture at a time; it does not currently create a universal binary.

Optional bundle/display overrides:

```bash
make install BUNDLE_ID=com.perso.mailbell APP_DISPLAY_NAME=Mailbell
```

After changing `.env`, rerun `make install` or `make dmg`; installed bundles contain a copy of the OAuth config injected during packaging.

## First Run

1. Launch `/Applications/Mailbell.app`.
2. Mailbell appears in the menu bar only; it has no Dock icon by default.
3. Allow notification permission when macOS asks.
4. Open Mailbell `Settings...`.
5. In `Accounts`, choose `Add Google Account`.
6. Complete the Google browser sign-in. If Google shows `Google hasn't verified this app`, continue only if the Cloud project and OAuth client are yours and you accept the personal-use risk.
7. After sign-in, Mailbell stores the account session in Keychain and starts watching Gmail `INBOX`.
8. Choose `Open Gmail` or click a notification to open Gmail Web in the configured browser.

To verify local token storage without printing secrets, open Keychain Access and search for service `com.perso.mailbell`.

## Troubleshooting

### Missing OAuth Credentials

Symptoms:

- `make install` or `make dmg` prints `error: set MAILBELL_GOOGLE_CLIENT_ID and MAILBELL_GOOGLE_CLIENT_SECRET...`.
- The app shows `OAuth setup required` and disables `Add Google Account`.

Fix:

- Fill `.env` or export both environment variables.
- Reinstall or rebuild the app bundle after changing packaged credentials.

### Invalid Client ID Or Secret

Symptoms:

- The installer says the Client ID must end in `.apps.googleusercontent.com`.
- Google token exchange fails after browser sign-in.

Fix:

- Use an OAuth client of type `Desktop app`.
- Copy the Client ID and Client Secret from the same OAuth client.
- Do not use a Web, iOS, Android, Chrome, or service-account credential.

### Redirect Or Loopback Errors

Mailbell starts a temporary local loopback listener and sends Google a `http://127.0.0.1:<port>` redirect URI.

Fix:

- Let the app open the system browser.
- Avoid VPN/firewall rules that block local loopback traffic.
- Recreate the OAuth client as `Desktop app` if you used another client type.

### Token Revoked Or Reauth Required

Symptoms:

- Account status becomes `Reconnect needed`.
- Refresh returns `invalid_grant`.

Fix:

- Use the account actions menu and choose `Sign in again`.
- If the account is stale or wrong, choose `Remove` and add it again.
- If your OAuth consent screen is still in `Testing`, move it to `In production` for day-to-day personal use or expect periodic reauth depending on Google policy.

### Gmail IMAP Disabled Or Blocked

Mailbell uses Gmail IMAP at `imap.gmail.com:993` over SSL.

Fix:

- In Gmail Web, check `Settings > See all settings > Forwarding and POP/IMAP` and enable IMAP if needed.
- For Google Workspace accounts, check admin policies for IMAP, third-party app access, and restricted OAuth scopes.

### Notifications Do Not Appear

Fix:

- Use `make install` and run `/Applications/Mailbell.app`; unbundled `make run` cannot post normal macOS notifications.
- Check `System Settings > Notifications > Mailbell`.
- Keep Mailbell running in the menu bar.

### Start At Login Does Not Work

The `Start at login` toggle uses `SMAppService` and requires a bundled app.

Fix:

- Install with `make install`.
- Toggle `Start at login` in `Settings > Behavior`.
- If macOS asks for approval, check `System Settings > General > Login Items`.

### Remove Local Tokens

Use `Settings > Accounts > Account actions > Remove`. This stops the monitor, deletes the account's Keychain tokens, resets its IMAP checkpoint, and removes the account metadata from UserDefaults.

Manual Keychain cleanup should be a last resort. If needed, use Keychain Access and search for service `com.perso.mailbell`.

## Maintenance

- Keep work on the personal branch unless you intentionally create a focused feature branch.
- Fetch upstream intentionally and inspect branches before merging or cherry-picking.
- Ignore website, gh-pages, hosted OAuth-domain pages, and public release automation unless the personal-use goal changes.
- Never merge upstream behavior that ships, documents as usable, or falls back to a shared OAuth client.
- Run `make build` and `make test` before committing docs or code that affects setup behavior.
- Follow [AGENTS.md](AGENTS.md) for product, security, workflow, commit, and validation rules.

## Revoking Access And Uninstalling

To remove local app access:

1. In Mailbell, remove each account from `Settings > Accounts`.
2. Quit Mailbell.
3. Run:

```bash
make uninstall
```

To revoke Google's grant, open your Google Account security settings, find third-party app access for the OAuth app/project you created, and remove it. Revoking in Google invalidates tokens, but it does not delete local app files; removing the account in Mailbell clears local tokens.

## Development Notes

Important paths:

- `Package.swift`: SwiftPM package and macOS 13 minimum.
- `Sources/Mailbell/App/`: menu bar app, Settings, login item, app state.
- `Sources/Mailbell/Auth/`: OAuth config/client, loopback redirect, Keychain token storage.
- `Sources/Mailbell/IMAP/`: Gmail IMAP XOAUTH2, `INBOX` selection, IDLE, header fetch, parser.
- `Sources/Mailbell/Service/`: account supervision, monitor state machine, UID checkpoints.
- `Sources/Mailbell/Notify/`: native notification authorization and posting.
- `Sources/Mailbell/Webmail/`: browser/profile routing for Gmail Web.
- `Resources/`: app icon and base `Info.plist`.
- `Scripts/` and `Makefile`: local build, install, DMG, icon, and OAuth injection paths.
- `Tests/MailbellTests/`: focused tests for stores, OAuth config, IMAP parsing, notifications, providers, and webmail routing.

Test strategy:

- Use `make build` for quick compile validation.
- Use `make test` for behavior changes.
- Use dummy OAuth values for packaging validation; never commit real credentials.
- Keep new tests focused on changed behavior, persistence contracts, validation-sensitive parsing, and regressions.


## License

MIT
