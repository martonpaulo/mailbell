# Mailbell

<p align="center">
  <img src="Resources/logo.png" alt="Mailbell logo" width="128">
</p>

Mailbell is a local, notification-first Gmail companion for macOS. It is a local bridge from your Google account to native macOS notifications: Google OAuth, Keychain tokens, Gmail IMAP XOAUTH2, `INBOX` `SELECT`, IMAP `IDLE`, minimal header fetches, bounded sanitized text previews, native notifications, and Gmail Web for reading or managing mail.

## Personal-Use Scope

This fork is for private local use on your own Mac.

- Its current implemented scope is menu-bar notifications, pending-review context, bounded sanitized previews, Gmail Web opening, and `Mark as Read` for pending items, implemented against Gmail IMAP with `UID STORE +FLAGS.SILENT (\\Seen)`.
- Full body viewing, reply, archive, delete, move, labels, compose, and attachments are not implemented by this app today.
- Those capabilities are allowed only as deliberate future product changes. Each must define data minimization, on-demand fetch rules, storage lifetime, permissions/scopes, UI/accessibility behavior, failure semantics, and tests before implementation.
- Do not add unused models, generic repositories, attachment caches, compose systems, or Gmail API abstractions just to prepare speculatively.
- It watches Gmail `INBOX` with IMAP `IDLE`; it does not use content polling as the primary notification mechanism.
- It opens Gmail Web when you click a notification, open a pending item, or choose `Open Gmail`.
- It has no cloud relay, hosted backend, analytics relay, public website, gh-pages flow, or public release pipeline.

## Privacy And Security Model

You must create and use your own Google OAuth Desktop credentials. This fork does not ship or fall back to any shared OAuth client.

- Real OAuth credentials live only in your shell, local `.env`, or a locally injected app bundle.
- `.env` is ignored by git. `.env.example` contains variable names only.
- Access and refresh tokens are stored in the macOS Keychain under the app bundle identifier configured for your local build.
- Non-secret account metadata, UI state, webmail preferences, IMAP checkpoints, and bounded pending-item dispositions are stored in `UserDefaults`.
- Notification and menu content use account, sender, subject, sent date, mailbox UID, Gmail thread/message identifiers when available, and a sanitized text preview.
- IMAP metadata fetches use `BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE MESSAGE-ID)]` with Gmail `X-GM-MSGID` and `X-GM-THRID` when available.
- Body preview fetches use `BODY.PEEK[TEXT]<0.8192>` only for a bounded text preview. Mailbell does not fetch attachments or full message bodies.
- Preview text is decoded and sanitized locally: SwiftSoup handles generic HTML parsing/text/entity extraction, then Mailbell strips or replaces MIME artifacts, URLs, and noisy transport markers before rendering in notifications and the menu.
- Because previews are email content, they can appear in macOS Notification Center and in the local menu while Mailbell is running.

Requested OAuth scopes:

| Scope | Why Mailbell requests it |
| --- | --- |
| `https://mail.google.com/` | Required by Gmail IMAP XOAUTH2 and the IMAP mark-as-read action. This is a broad restricted Gmail scope even though Mailbell limits itself to metadata, bounded sanitized text previews, and pending-item read marking. Do not replace it with narrower Gmail API scopes unless the transport changes away from IMAP. |
| `openid` | Required for the OpenID Connect user info call after sign-in. |
| `email` | Lets the app read the signed-in Gmail address, label the account, and authenticate IMAP as that user. |

The broad Gmail scope is the main privacy tradeoff of this design. Gmail's narrower API scopes, such as `gmail.metadata`, do not authenticate this IMAP implementation.

## Runtime Contracts

These are the user-visible contracts the code is expected to preserve:

- **Transport:** Gmail IMAP `IDLE` is the primary new-mail mechanism. Re-arm timers and manual `Check Now` reconnect the IDLE loop; they are not content polling loops.
- **Checkpointing:** each monitored mailbox uses `(UIDVALIDITY, lastSeenUID)`. If `UIDVALIDITY` changes, Mailbell rebaselines without notifying old backlog. If it is unchanged, Mailbell gap-fills unread UIDs above the checkpoint.
- **Burst handling:** fresh unread UIDs are admitted to the pending store in bounded batches of 100. Notification Center is capped to the newest 10 messages per fetch, but the checkpoint advances only after each admission batch is fetched and admitted, so older fresh messages in a burst are not skipped.
- **Pending store:** the menu shows one pending item per Gmail thread when `X-GM-THRID` is available. The counter follows the grouped menu item count, not the number of raw messages in the thread.
- **Thread previews:** notifications use the preview for the specific message being notified. The menu item for a thread uses the first message that entered Mailbell's pending store for that thread, and opening any item in that group opens that first pending message's Gmail URL.
- **External reads:** when a message is read directly in Gmail Web, unread reconciliation removes it from Mailbell's pending store.
- **Dismiss/open/read:** dismissing, opening, or marking a pending group as read suppresses that group locally. `Mark as Read` also marks every known IMAP identity in the group as read on the server.
- **Sanitized preview shape:** previews are plain text, at most three lines in the menu, with URLs replaced and MIME/HTML noise removed as best effort.

## Requirements

- macOS 26 or newer.
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
9. Copy the Client ID. The Client ID should end with `.apps.googleusercontent.com`. If Google shows a Desktop Client Secret, you may copy it too, but Mailbell treats it as optional because installed-app clients are public clients.

The app uses Google's installed-app OAuth flow with PKCE and a temporary `http://127.0.0.1:<port>/oauth/callback` loopback redirect. The callback server binds only to IPv4 loopback and uses an OS-assigned dynamic port. Do not create a Web app client for this fork.

## Local Configuration

Create a private `.env` from the example and fill in your own Desktop client ID. You can also set the bundle identity used for your local app build there:

```bash
cp .env.example .env
$EDITOR .env
```

Example `.env` content:

```bash
MAILBELL_GOOGLE_CLIENT_ID=your-desktop-client-id.apps.googleusercontent.com
MAILBELL_BUNDLE_ID=dev.example.mailbell
MAILBELL_APP_DISPLAY_NAME=Mailbell
MAILBELL_GOOGLE_CLIENT_SECRET=
```

`MAILBELL_GOOGLE_CLIENT_SECRET` is optional. Leave it blank or omit it unless you intentionally want Mailbell to send the Desktop client secret for backward compatibility with an existing local setup.

You can use shell environment variables instead:

```bash
export MAILBELL_GOOGLE_CLIENT_ID="your-desktop-client-id.apps.googleusercontent.com"
export MAILBELL_BUNDLE_ID="dev.example.mailbell"
export MAILBELL_APP_DISPLAY_NAME="Mailbell"
# Optional:
export MAILBELL_GOOGLE_CLIENT_SECRET="your-desktop-client-secret"
```

Packaging commands read environment variables first, then `.env`, and take the client ID plus optional secret from one source rather than combining credentials across sources. `Scripts/inject_oauth_config.sh` validates the values and writes only these expected bundle keys into the copied app `Info.plist`:

- `MailbellGoogleClientID`
- `MailbellGoogleClientSecret` only when `MAILBELL_GOOGLE_CLIENT_SECRET` is nonblank
- `CFBundleIdentifier`
- `CFBundleName`
- `CFBundleDisplayName`

The source `Resources/Info.plist` should not contain real credentials.

Identity notes:

- `MAILBELL_BUNDLE_ID` must be a reverse-DNS identifier and should be unique to your local build.
- `MAILBELL_APP_DISPLAY_NAME` controls `CFBundleName` and `CFBundleDisplayName` in packaged apps.
- The checked-in `Resources/Info.plist` uses a neutral placeholder bundle id. `make install` and `make dmg` inject your configured bundle id into the copied app bundle.
- Runtime namespaces for Keychain, logging, and internal dispatch queues derive from the packaged bundle id. Unbundled `make run` uses a neutral local bundle identifier.
- Changing `MAILBELL_BUNDLE_ID` after signing in creates a new Keychain namespace, so you may need to sign in again and remove previous tokens under the earlier bundle id.

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
make install MAILBELL_BUNDLE_ID=dev.example.mailbell MAILBELL_APP_DISPLAY_NAME=Mailbell
```

After changing `.env`, rerun `make install` or `make dmg`; installed bundles contain a copy of the OAuth config injected during packaging.

## First Run

1. Launch `/Applications/Mailbell.app`.
2. Mailbell appears in the menu bar only; it has no Dock icon by default.
3. Allow notification permission when macOS asks.
4. Open Mailbell `Settings…`.
5. In `Accounts`, choose `Add Google Account`.
6. Complete the Google browser sign-in. If Google shows an app warning, continue only if the Cloud project and OAuth client are yours.
7. After sign-in, Mailbell stores the account session in Keychain and starts watching Gmail `INBOX`.
8. Choose `Open Gmail`, open a pending item, or click a notification to open Gmail Web in the configured browser.
9. Pending review items can be opened, dismissed, or marked as read from the menu.

To verify local token storage without printing secrets, open Keychain Access and search for the bundle id you configured with `MAILBELL_BUNDLE_ID`.

## Troubleshooting

### Missing OAuth Credentials

Symptoms:

- `make install` or `make dmg` prints `error: set MAILBELL_GOOGLE_CLIENT_ID...`.
- The app shows `OAuth setup required` and disables `Add Google Account`.

Fix:

- Fill `.env` or export `MAILBELL_GOOGLE_CLIENT_ID`.
- Reinstall or rebuild the app bundle after changing packaged credentials.

### Invalid Client ID Or Optional Secret

Symptoms:

- The installer says the Client ID must end in `.apps.googleusercontent.com`.
- Google token exchange fails after browser sign-in.

Fix:

- Use an OAuth client of type `Desktop app`.
- Copy the Client ID from a Desktop OAuth client. If you configure `MAILBELL_GOOGLE_CLIENT_SECRET`, copy it from the same OAuth client.
- Do not use a Web, iOS, Android, Chrome, or service-account credential.

### Redirect Or Loopback Errors

Mailbell starts a temporary local loopback listener and sends Google a `http://127.0.0.1:<port>/oauth/callback` redirect URI.

Fix:

- Let the app open the system browser.
- Avoid VPN/firewall rules that block local loopback traffic.
- Recreate the OAuth client as `Desktop app` if you used another client type.

### Token Revoked Or Reauth Required

Symptoms:

- Account status becomes `Reconnect needed`.
- Refresh returns `invalid_grant`.

Fix:

- In `Settings > Accounts > <email>`, choose `Sign in again`.
- If the account is stale or wrong, choose `Remove Account` and add it again.
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

### Remove An Account

Use `Settings > Accounts > <email> > Remove Account`. This stops the monitor, deletes the account's Keychain tokens, resets its IMAP checkpoints, removes pending records for that account, and removes the account metadata from UserDefaults.

Manual Keychain cleanup should be a last resort. If needed, use Keychain Access and search for the bundle id you configured with `MAILBELL_BUNDLE_ID`.

## Maintenance

- Keep ordinary work on `main` unless you intentionally create a focused feature branch.
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

- `Package.swift`: SwiftPM package and macOS 26 minimum.
- `Sources/Mailbell/App/`: menu bar app, Settings, login item, app state.
- `Sources/Mailbell/Auth/`: OAuth config/client, loopback redirect, Keychain token storage.
- `Sources/Mailbell/IMAP/`: Gmail IMAP XOAUTH2, mailbox selection, IDLE, metadata/body-preview fetches, parser, preview sanitizer, and read marker command.
- `Sources/Mailbell/Service/`: account supervision, monitor state machine, UID checkpoints, pending store, unread reconciliation, and server-backed mark-as-read orchestration.
- `Sources/Mailbell/Notify/`: native notification authorization and posting.
- `Sources/Mailbell/Webmail/`: browser/profile routing for Gmail Web.
- `Resources/`: app icon and base `Info.plist`.
- `Scripts/` and `Makefile`: local build, install, DMG, icon, and OAuth injection paths.
- `Tests/MailbellTests/`: focused tests for stores, OAuth config, IMAP parsing, notifications, providers, and webmail routing.

Project structure contract:

- Keep the standard SwiftPM shape: `Package.swift` at the root, app sources under `Sources/Mailbell`, and tests under `Tests/MailbellTests`.
- Keep one executable target and one test target until a module boundary reduces real coupling or enables reuse. For this personal menu bar app, splitting local packages now would add manifest and visibility overhead without shrinking the core surface.
- Organize source files by ownership domain (`App`, `Account`, `Auth`, `IMAP`, `Notify`, `Provider`, `Service`, `Util`, `Webmail`) before adding new top-level folders.
- Prefer narrow extension files for large owner types when the feature boundary is real, as with account webmail actions and mark-as-read behavior.

Test strategy:

- Use `make build` for quick compile validation.
- Use `make test` for behavior changes.
- Use dummy OAuth values for packaging validation; never commit real credentials.
- Keep new tests focused on changed behavior, persistence contracts, validation-sensitive parsing, and regressions.


## License

MIT

## References

- App icon source is `Resources/logo.png`; derived icons are generated by `Scripts/generate_app_icon.sh`.
- App icon generated with [IconKitchen][icon-kitchen-app-icon] using the `notifications_active` round clipart icon, no effect, a 270-degree gradient background without texture, foreground `#FFFFFF`, gradient `#FFD54A` to `#D89B00`, and 15% padding.

[icon-kitchen-app-icon]: https://icon.kitchen/i/H4sIAAAAAAAAA0VR0W6DIBT9l7tX01CdVn1b2m5PS5Zsb02zICCSKBjEpo3x33dB7Xjh3sPhHO5hghttRzFAOUEtj6Y1Fkp4qcOCCKp_LKMJF3nAfh69QEhaypXQLmAfW4NKgzN9kCSLGE9fKZLIrijIPk7zLCepX5k_5nlREQJzBFTLFnXjA8Gmkp9iaLxIb5R2KHeZ4A4l2cVpBI-tYNvz0iQ7vZ9RZmUdNpYvnqzsLTmdc5ivweG7oWEQpixD5wgjWEdjreqpDZNRLsUzhD0XRZUtIYi7Gy2SJ9Sq5RflXGnpH4zTQ7lHW6tkg4H4sjLOmW6pW1EHNNw7rk4-NoEbWDNqjg6KGY2tNk7VilGnjB5-KXPqJmDGq53hY-t_7gIdZWaA6_wHPt2MQs4BAAA

## Original Project

This repository is a fork of [samzong/mailbell](https://github.com/samzong/mailbell). The original MIT copyright notice is retained in [LICENSE](LICENSE).
