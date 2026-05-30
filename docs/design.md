# Mailbell Design

## Name

`mailbell`

The name describes the product boundary: a small bell for mail events. It avoids framing the app as a full Gmail client.

## Product Goal

Build a minimal macOS menu bar app that notifies the user when Gmail receives new mail, even when the browser is closed and the iPhone is unavailable.

The app should let the user keep reading and managing mail in Gmail Web. It should not become another mailbox UI.

## Non-Goals

- No full email client.
- No message body reader.
- No reply, archive, delete, move, label, or compose flow.
- No cloud relay service in the default architecture.
- No content polling loop for new mail. (The IMAP IDLE keepalive re-arm is a liveness timer, not content polling.)
- No browser tab requirement.
- No dependency on iPhone notification mirroring.

## Minimal User Experience

- A macOS menu bar item shows connection state and unread count.
- The user signs in with a Google account through OAuth.
- New Gmail inbox messages create native macOS notifications.
- Clicking a notification opens Gmail Web in the configured browser.
- The menu provides `Open Gmail`, `Reconnect`, `Settings`, and `Quit`.
- Settings stay small: account, notification scope, browser choice, start at login, disconnect.

## Recommended Architecture

```text
MenuBarExtra
  -> OAuth login
  -> Keychain token storage
  -> IMAP XOAUTH2 authentication
  -> IMAP IDLE session to imap.gmail.com:993
  -> new message event
  -> fetch headers only
  -> UNUserNotificationCenter notification
  -> open Gmail Web
```

## Transport Choice

Use Gmail IMAP IDLE for the first implementation. This is a performance-first decision: the product target is near-instant notification with a negligible idle footprint.

Reasoning:

- Gmail exposes IMAP `IDLE` in its IMAP capabilities.
- IDLE is true server push from the app's perspective: an untagged `EXISTS` arrives in ~1s. It is the lowest-latency realistic option, over the shortest path (Mac to Gmail directly, no intermediary).
- Idle cost is minimal: one quiet TLS connection plus a periodic re-arm, with the fewest wakeups of the options. Best for battery and CPU.
- It keeps the architecture local and avoids Google Cloud Pub/Sub, webhook hosting, subscription acknowledgements, and Gmail API `watch()` renewal.
- Bonus: IMAP is provider-portable. A future non-Gmail provider can reuse the same transport wherever it supports IDLE.

Alternatives considered and rejected:

- **Gmail API incremental polling (`history.list` + `historyId`):** simplest, and allows the narrow `gmail.metadata` scope, but latency equals the poll interval and tight polling repeatedly wakes the radio/CPU. Rejected because low latency and low energy are hard requirements.
- **Gmail API + Cloud Pub/Sub push (streaming pull):** also near-push and allows the narrow `gmail.metadata` scope, but adds a GCP project, a Pub/Sub topic/subscription, `watch()` renewal every 7 days, and an extra network hop. Not better than IDLE on latency or energy, and heavier to operate. Reconsider only if a narrow OAuth scope becomes a hard requirement.

Cost of this choice: IMAP forces the broad `https://mail.google.com/` scope (see OAuth and Permissions). Accepted in exchange for the latency, energy, and operational simplicity above.

## OAuth and Permissions

For IMAP OAuth, Gmail uses XOAUTH2. Google's documented IMAP, POP, and SMTP OAuth scope is:

```text
https://mail.google.com/
```

This is a restricted full-mail scope. IMAP offers no narrower option: even though the app only reads message headers, the consent surface covers full mail access. This is the one real cost of choosing IMAP over the Gmail API (whose `gmail.metadata` scope is narrower), accepted because the priority is latency and low overhead, not consent-surface minimization (see Transport Choice).

The OAuth client is a macOS "Desktop / installed app" client and must use PKCE. A desktop client secret is not actually confidential; never treat it as a real credential.

Token storage must use Keychain. Refresh tokens must not be stored in `UserDefaults`, plaintext files, or logs.

### Token Lifecycle and the 7-Day Problem

This is the single biggest feasibility risk, and it is independent of the transport: it applies to IMAP and the Gmail API equally because both rely on an OAuth refresh token.

Problem: if the OAuth consent screen's publishing status is **Testing** with user type **External**, Google revokes the refresh token after **7 days**. For a notifier meant to stay connected indefinitely, that forces a weekly re-login and breaks the product.

Decision: publish the OAuth consent screen to **In production**. Once in production, refresh tokens persist indefinitely (subject to the normal revocation rules below). For personal/private use this does **not** require Google verification or a CASA security assessment — the app stays "Unverified" and the user clicks through a one-time "Google hasn't verified this app" warning on first sign-in.

Two viable configurations:

- **Personal / private use (default):** External + In production + Unverified. No CASA. One-time unverified warning. Refresh token persists. Subject to the unverified-app user cap (~100 users), irrelevant for personal use.
- **Google Workspace owner:** set user type to **Internal**. No verification, no warning, no 7-day expiry — but only accounts in that Workspace org can sign in.

Public distribution (External + In production + Verified) additionally requires OAuth verification plus an annual CASA security assessment for the restricted scope. Out of scope for the first release; this is the deciding factor behind "private-use first."

When minting the token, request `access_type=offline` and `prompt=consent` so Google returns a durable refresh token.

Even after the 7-day issue is solved, a refresh token can still be revoked by ~6 months of inactivity, an account password change, the user revoking access, or exceeding the per-client live-token cap. The app must therefore treat "refresh failed / token revoked" as a normal, recoverable state: surface a clear reconnect affordance and re-run OAuth rather than failing silently (see State Machine `reauthRequired`).

## Notification Content

Fetch the smallest useful data:

- account
- sender display name or address
- subject
- received date
- Gmail message/thread identifiers if available

Do not fetch message body or attachments for the first version.

## State Machine

```text
signedOut
  -> authorizing
  -> tokenReady
  -> connectingIMAP
  -> selectingInbox        (record UIDVALIDITY + last seen UID)
  -> idling
  -> eventReceived         (untagged EXISTS)
  -> fetchHeaders
  -> notify
  -> idling

idling
  -> reIdle                (re-arm IDLE before the 29-minute server limit)
  -> idling

networkLost / sleepWake / idleTimeout
  -> reconnecting
  -> resyncByUID           (validate UIDVALIDITY; fill gap above last seen UID)
  -> idling

tokenExpired
  -> refreshToken
  -> reconnecting

refreshFailed / tokenRevoked
  -> reauthRequired        (prompt user to reconnect; re-run OAuth)
  -> authorizing
```

The app must handle sleep, wake, network changes, VPN changes, access-token refresh, and refresh-token revocation. The reconnect checkpoint is the pair `(UIDVALIDITY, lastSeenUID)`: if `UIDVALIDITY` is unchanged, fetch headers for UIDs above the checkpoint and notify the gap; if it changed, rebaseline without notifying the backlog. A dead refresh token is not recoverable automatically and must route to `reauthRequired`, never to a silent retry loop.

## Performance and Energy Budget

The design is push-based (IMAP IDLE) and never content-polls. The happy path is already fast — IDLE delivers `EXISTS` within ~1s — so the real work is shrinking the window where the connection is silently dead and no events arrive:

- **Latency target:** mail arrival to notification within a few seconds on a healthy connection.
- **Network awareness:** use `NWPathMonitor` to react immediately to network, interface, and VPN changes and reconnect, instead of waiting for a TCP timeout.
- **Liveness:** enable TCP keepalive and re-arm IDLE on an app-side timer below the 29-minute IMAP limit (RFC 2177). Treat a missed re-arm round-trip as a dead connection.
- **Sleep/wake:** observe `NSWorkspace` sleep/wake notifications and pre-warm a reconnect on wake rather than waiting for the next IDLE cycle.
- **Idle cost:** one long-lived TLS connection, quiet except for the periodic re-arm; no short-interval timers that wake the CPU or radio. Do not defeat App Nap for the parts of the app that can sleep.
- **No data loss on reconnect:** use the `(UIDVALIDITY, lastSeenUID)` checkpoint to fill gaps, and rate-limit notifications so a large backlog or first sync cannot flood Notification Center.

## macOS App Shape

- SwiftUI app with `MenuBarExtra`.
- Minimum target macOS 13 (Ventura), required by `MenuBarExtra` and `SMAppService`.
- Accessory-style app by default, with no Dock icon.
- `Settings` scene for preferences.
- `UNUserNotificationCenter` for notifications.
- `SMAppService` for start-at-login.
- Keychain for secrets.
- A small IMAP service owns the long-lived network connection.

Use AppKit only where SwiftUI does not cover the needed menu bar, settings, login item, or notification behavior.

## MVP Phases

1. CLI spike: OAuth, IMAP XOAUTH2, select inbox, enter IDLE, print new message headers.
2. Menu bar shell: connection state, sign in, sign out, open Gmail.
3. Native notifications: request permission, show notification, open Gmail on click.
4. Resilience: reconnect after network changes, wake from sleep, token expiry, and UID gap fill.
5. Packaging: login item, ad-hoc signed app bundle / DMG, basic diagnostics. Ad-hoc signing is sufficient for private local use and needs no Apple Developer account. Notarization (Developer ID) is optional and only matters for distributing the app to other Macs.

## Resolved Decisions

- **Transport:** Gmail IMAP IDLE, performance-first. See Transport Choice.
- **OAuth publishing:** External + In production + Unverified for private use; Workspace Internal if available. Solves the 7-day token expiry without CASA. See Token Lifecycle.
- **Notification scope:** `INBOX` for the first release. Gmail's category tabs (Primary/Social/Promotions/...) are not separate IMAP folders, so a "Primary only" filter is not achievable over IMAP and would require the Gmail API. Revisit only if category filtering becomes a requirement.
- **Accounts:** single Gmail account for the first release; multi-account deferred.
- **Browser:** open in the system default browser; per-account/browser choice deferred.
- **Deep link:** feasible via `X-GM-THRID` converted to hex in a Gmail Web URL. First release opens the inbox; per-message deep links are a fast follow once verified.

## Open Questions

- Will the project ever need public distribution (and therefore OAuth verification + annual CASA), or is private/Workspace use the permanent boundary?
- For multi-account (later), is one IMAP IDLE connection per account acceptable given Gmail's per-account connection limits?
- Is per-message deep linking reliable enough across Gmail Web states to enable by default, or should it stay opt-in?

## Verified Source Facts

- Gmail IMAP capabilities include `IDLE`.
- Gmail IMAP OAuth uses XOAUTH2.
- Gmail IMAP/POP/SMTP OAuth uses the `https://mail.google.com/` scope.
- Gmail API push notifications require Cloud Pub/Sub and mailbox watch renewal.
- An OAuth consent screen in "Testing" status with "External" user type issues refresh tokens that expire after 7 days.
- Publishing the consent screen to "In production" removes the 7-day expiry; for personal/internal use this needs no verification or CASA assessment (the app stays "Unverified" with a one-time warning).
- A refresh token can still be revoked by ~6 months of inactivity, password change, manual revocation, or exceeding the per-client live-token cap.
- The `https://mail.google.com/` scope is a restricted scope; public distribution requires OAuth verification plus an annual CASA security assessment.
- RFC 2177 recommends re-arming IMAP IDLE at least every 29 minutes.
