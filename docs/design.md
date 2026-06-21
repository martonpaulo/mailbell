# Mailbell Design

## Name

`mailbell`

The name describes the product boundary: a small bell for mail events. It avoids framing the app as a full Gmail client.

## Product Goal

Build a minimal macOS menu bar app that notifies the user when Gmail receives new mail, even when the browser is closed and the iPhone is unavailable.

The app should let the user keep reading and managing mail in Gmail Web. It should not become another mailbox UI.

## Non-Goals

- No full email client.
- No mailbox browsing UI.
- No full message body reader or attachment reader.
- No reply, archive, delete, move, label, or compose flow.
- No cloud relay service in the default architecture.
- No content polling loop for new mail. The IMAP IDLE keepalive re-arm is a liveness timer, not content polling.
- No browser tab requirement.
- No dependency on iPhone notification mirroring.

Allowed exceptions inside the notifier boundary:

- Bounded sanitized text previews for notification/menu context.
- Server-backed `Mark as Read` for pending items already surfaced by Mailbell.
- Dismiss/open/read dispositions for pending items so the menu does not re-show handled messages.

## Minimal User Experience

- A macOS menu bar item shows aggregate connection state and an optional grouped pending count.
- The user signs in with one or more Google accounts through OAuth.
- New Gmail inbox messages create native macOS notifications with sender, subject, and a sanitized body preview when available.
- The menu shows an `Awaiting Review` section with one item per Gmail thread when thread IDs are available.
- Opening any pending item opens Gmail Web, not an in-app mailbox.
- Clicking a notification opens Gmail Web using the account's configured browser.
- Pending items can be opened, dismissed, or marked as read from the menu.
- Settings stay small: OAuth/setup state, account status/actions, browser routing, notification behavior, and start at login.

## Recommended Architecture

```text
MenuBarExtra
  -> AppState prepared UI state
  -> AccountSupervisor
  -> AccountRuntime per account
  -> OAuth login
  -> account-scoped Keychain token storage
  -> IMAP XOAUTH2 authentication
  -> monitored mailbox SELECT
  -> IMAP IDLE session to imap.gmail.com:993
  -> unread UID reconciliation
  -> metadata fetch + bounded body-preview fetch
  -> EmailStore admission/grouping
  -> UNUserNotificationCenter notification
  -> Gmail Web through WebmailOpener
```

## Transport Choice

Use Gmail IMAP IDLE. This is a performance-first decision: the product target is near-instant notification with a negligible idle footprint.

Reasoning:

- Gmail exposes IMAP `IDLE` in its IMAP capabilities.
- IDLE is true server push from the app's perspective: an untagged `EXISTS` arrives quickly without short-interval polling.
- Idle cost is minimal: one quiet TLS connection per enabled account plus a periodic re-arm, with fewer wakeups than polling.
- It keeps the architecture local and avoids Google Cloud Pub/Sub, webhook hosting, subscription acknowledgements, and Gmail API `watch()` renewal.
- IMAP is provider-portable in shape. A future non-Gmail provider can reuse the same transport wherever it supports IDLE.

Alternatives considered and rejected:

- **Gmail API incremental polling (`history.list` + `historyId`):** simpler and allows narrower API scopes, but latency equals the poll interval and tight polling repeatedly wakes the CPU/network stack.
- **Gmail API + Cloud Pub/Sub push:** also near-push and can use narrower scopes, but adds a GCP topic/subscription, `watch()` renewal, and an extra network hop. That is heavier than a direct local IDLE connection for a personal menu bar app.

Cost of this choice: IMAP forces the broad `https://mail.google.com/` scope. Accepted in exchange for latency, energy, and operational simplicity.

## OAuth And Permissions

For IMAP OAuth, Gmail uses XOAUTH2. Google's documented IMAP, POP, and SMTP OAuth scope is:

```text
https://mail.google.com/
```

This is a restricted full-mail scope. IMAP offers no narrower option even though Mailbell limits itself to metadata, bounded sanitized text previews, and read marking for pending items. The consent surface covers broader mail access than the app intentionally uses.

The OAuth client must be a user-owned Google Desktop/installed-app client and must use PKCE. Local development reads the client ID and desktop client secret from environment variables or `.env`; local packaging injects those values into the app bundle. Mailbell must not ship, document as usable, or fall back to an upstream/shared OAuth client.

Token storage must use Keychain. Refresh tokens must not be stored in `UserDefaults`, plaintext files, or logs.

### Token Lifecycle

The refresh token is the main operational dependency. A revoked or unavailable refresh token breaks the notifier until the user signs in again.

For day-to-day personal use, publish the OAuth consent screen to **In production** after setup.

Two viable configurations:

- **Personal/private use:** External + In production.
- **Google Workspace owner:** Internal, only when the Cloud project belongs to that Workspace or Cloud Identity organization and all sign-ins are from that organization.

When minting the token, request `access_type=offline` and `prompt=consent` so Google returns a durable refresh token.

Even then, a refresh token can be revoked by inactivity, account changes, manual revocation, or per-client token limits. Refresh-token failure must route to `reauthRequired` with a clear reconnect affordance. It must not become a silent retry loop.

## Data Access Contract

Fetch the smallest useful data needed for notification and pending-review context:

- account
- sender display name/address
- subject
- sent date
- mailbox UID
- RFC `Message-ID`
- Gmail `X-GM-MSGID` and `X-GM-THRID` when available
- bounded sanitized text preview

Current IMAP fetches:

- metadata: `UID X-GM-MSGID X-GM-THRID BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE MESSAGE-ID)]`
- preview: `UID BODY.PEEK[TEXT]<0.8192>`

Important constraints:

- Use `BODY.PEEK` so preview generation does not mark mail as read.
- Do not fetch attachments.
- Do not fetch or persist full message bodies.
- Do not log raw message bodies, OAuth secrets, IMAP auth payloads, or provider responses that may contain secrets.
- Treat preview text as local user data. It may appear in Notification Center and the menu, but it should stay bounded and sanitized.

## Preview Content Contract

Body preview is a convenience layer, not a mail reader. The sanitizer should keep useful human text while removing transport and rendering noise:

- decode UTF-8 or ISO Latin-1 data
- remove MIME part headers and multipart boilerplate
- decode quoted-printable text
- strip scripts, styles, HTML tags, and basic entities
- replace URLs with a generic placeholder
- collapse whitespace and punctuation spacing
- return at most the configured preview length
- wrap the menu preview into at most three readable lines

Notification and menu behavior intentionally differ:

- A notification preview belongs to the specific message that triggered that notification.
- A menu row represents a pending thread group. Its sender, subject, date, preview, and URL come from the first message that entered Mailbell's pending store for that group, not necessarily the oldest message in the Gmail thread.

## Pending Store Contract

`EmailStore` owns local pending-review state. It is not a durable mailbox cache.

- `EmailStoreIdentity.id` is per message using Gmail message ID, Gmail thread ID, RFC message ID, or mailbox UID fallback.
- `EmailStoreIdentity.groupID` groups by Gmail thread ID when available.
- The menu and counter show grouped pending items.
- Multiple unread messages in the same Gmail thread can still produce notifications, but the pending count remains one.
- Opening a pending item, dismissing it, or marking it read removes the whole known group from the menu.
- Handled dispositions are persisted in `UserDefaults` with pruning; pending message content itself stays in memory.
- External Gmail reads are handled by unread reconciliation: if a pending UID is no longer unread, it is removed.
- Unknown unread UIDs discovered during reconciliation can be admitted with bounded fetches so Mailbell catches items missed while offline.

## State Machine

```text
signedOut
  -> authorizing
  -> tokenReady
  -> connectingIMAP
  -> selectingMailbox       (record UIDVALIDITY + last seen UID)
  -> idling
  -> eventReceived          (untagged EXISTS or mailbox change)
  -> reconcileUnreadState
  -> admitPendingBatches
  -> notifyNewest
  -> syncUnreadStore
  -> idling

idling
  -> reIdle                 (re-arm IDLE before the 29-minute server limit)
  -> idling

networkLost / sleepWake / idleTimeout
  -> reconnecting
  -> resyncByUID            (validate UIDVALIDITY; fill gap above lastSeenUID)
  -> idling

tokenExpired
  -> refreshToken
  -> reconnecting

refreshFailed / tokenRevoked
  -> reauthRequired         (prompt user to reconnect; re-run OAuth)
  -> authorizing
```

The reconnect checkpoint is the per-account, per-mailbox pair `(UIDVALIDITY, lastSeenUID)`. If `UIDVALIDITY` is unchanged, fetch unread UIDs above the checkpoint and notify the gap. If it changed, rebaseline without notifying the backlog. A dead refresh token is not recoverable automatically and must route to `reauthRequired`.

## Burst And Checkpoint Contract

Large unread bursts have two separate limits:

- **Admission limit:** fetch and admit fresh unread UIDs in batches of 100 so the pending store does not skip older fresh mail.
- **Notification limit:** post notifications for only the newest 10 messages per fetch so Notification Center is not flooded.

The checkpoint may advance only after each admission batch is successfully fetched and offered to the pending store. This is intentionally different from "notify newest then jump to newest"; jumping early can permanently skip older fresh messages.

## Performance And Energy Budget

The design is push-based and never content-polls. The happy path should notify within a few seconds on a healthy connection.

- **Network awareness:** use `NWPathMonitor` to react to network/interface/VPN changes and reconnect instead of waiting for TCP timeout.
- **Liveness:** enable TCP keepalive and re-arm IDLE on an app-side timer below the 29-minute IMAP limit. Treat a missed re-arm round trip as a dead connection.
- **Sleep/wake:** observe `NSWorkspace` sleep/wake notifications and reconnect on wake.
- **Idle cost:** one long-lived TLS connection per enabled account, quiet except for the periodic re-arm.
- **Fetch cost:** metadata and preview fetches are bounded. Avoid unbounded body reads, attachment reads, or broad mailbox scans.
- **Render cost:** SwiftUI views consume prepared state such as pending counts by account; expensive grouping and formatting should stay outside `body` hot paths.

## Accounts And Providers

Accounts are modeled as a provider-backed collection, not as fixed slots. This personal fork supports Gmail only; the provider-shaped runtime keeps account supervision explicit without adding other providers.

Each account owns:

- account metadata in `UserDefaults`
- provider-scoped credentials in Keychain
- per-mailbox checkpoints in `UserDefaults`
- pending handled dispositions in `UserDefaults`
- one runtime state machine
- one IMAP IDLE connection while enabled and connected

`AccountSupervisor` owns global lifecycle events such as app launch, network recovery, and wake-from-sleep, then fans reconnect requests out to account runtimes. UI state observes supervisor snapshots instead of managing `MailMonitor` instances directly.

## Webmail Opening

Each account can choose how Gmail opens: system default browser, a selected installed browser, or Google Chrome with an optional profile directory.

Notification clicks, pending item opens, and per-account `Open Gmail` use the same opener path. Message-specific opens use Gmail thread links when IMAP provides `X-GM-THRID`; generic account opens still open Gmail Web. Mailbell does not add `authuser` routing.

When opening a pending thread group, use the first message that entered the pending store for that group. This keeps the menu row, preview, and destination coherent.

## macOS App Shape

- SwiftUI app with `MenuBarExtra`.
- Minimum target macOS 26, matching the local personal-use toolchain and avoiding older Settings compatibility paths.
- Accessory-style app by default, with no Dock icon.
- `Settings` scene for preferences.
- `UNUserNotificationCenter` for notifications.
- `SMAppService` for start-at-login.
- Keychain for secrets.
- A small IMAP service owns the long-lived network connection.

Use AppKit only where SwiftUI does not cover the needed menu bar, settings, login item, notification, or browser-opening behavior.

## Project Structure

Mailbell intentionally uses the standard SwiftPM project shape:

```text
Package.swift
Sources/Mailbell/
Tests/MailbellTests/
Resources/
Scripts/
docs/
```

This matches SwiftPM defaults: the package manifest lives at the root, the executable target has its sources under `Sources/Mailbell`, and the test target has its tests under `Tests/MailbellTests`. `Package.swift` uses explicit `path` values because the executable target is named `mailbell` while the source folder is capitalized as `Mailbell`.

Source subfolders are ownership boundaries:

- `Account`: durable account model and persistence.
- `App`: SwiftUI app shell, menu, Settings, and prepared UI state.
- `Auth`: OAuth, loopback redirect, token storage, and Keychain wrapper.
- `IMAP`: protocol client, connection, parser, models, preview sanitizer, and read command.
- `Notify`: native notification authorization/content/posting.
- `Provider`: provider URL and routing model.
- `Service`: runtime supervision, monitor state machine, pending store, checkpoints, and cross-boundary orchestration.
- `Util`: small shared utilities.
- `Webmail`: browser/profile discovery and opening.

Refactor rule: keep this layout until a move reduces real coupling, isolates a reusable module, or prevents a correctness issue. Do not create local packages, extra targets, or renamed top-level folders just for visual symmetry. For this personal app, one executable target plus one test target is lower-cost and clearer than premature modularization.

When a type grows large, prefer narrow extension files only when they map to a real feature boundary, such as account webmail actions or mark-as-read behavior.

## MVP Phases

1. CLI spike: OAuth, IMAP XOAUTH2, select inbox, enter IDLE, print new message headers.
2. Menu bar shell: connection state, sign in, sign out, open Gmail.
3. Native notifications: request permission, show notification, open Gmail on click.
4. Resilience: reconnect after network changes, wake from sleep, token expiry, UID gap fill, unread reconciliation, and burst admission.
5. Pending review: grouped pending store, sanitized previews, open/dismiss/mark-as-read actions.
6. Packaging: login item, ad-hoc signed app bundle/DMG, basic diagnostics.

Ad-hoc signing is sufficient for private local use and needs no Apple Developer account. Notarization is optional and only matters for distribution to other Macs.

## Resolved Decisions

- **Transport:** Gmail IMAP IDLE, performance-first. See Transport Choice.
- **OAuth publishing:** External + In production for private use; Workspace Internal if available. Avoid long-term Testing-mode token behavior for day-to-day use. See Token Lifecycle.
- **OAuth scope:** `https://mail.google.com/` is required by IMAP XOAUTH2. Narrow Gmail API scopes do not authenticate this transport.
- **Notification scope:** Gmail inbox by default, with optional Spam monitoring when enabled. Gmail category tabs are not separate IMAP folders, so "Primary only" over IMAP is not part of this design.
- **Preview scope:** bounded sanitized text preview is in scope; full body reading and attachments are not.
- **Pending grouping:** count one grouped menu item per Gmail thread when thread IDs are available.
- **Read action:** `Mark as Read` is in scope only for known pending items and must use IMAP `UID STORE`.
- **Accounts:** account collection with one runtime per enabled account. Gmail is the only supported provider.
- **Browser:** per-account Webmail open preference: system default, selected browser, or optional Chrome profile.
- **Deep link:** notification and pending item opens use Gmail thread links when `X-GM-THRID` is available. Generic account actions still open Gmail Web.
- **Project structure:** keep the standard SwiftPM layout and current domain folders; no structural refactor is currently justified.
