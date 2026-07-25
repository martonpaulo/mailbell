# Architecture

Mailbell is a single SwiftPM executable: a macOS 26+ accessory app with no
backend of any kind. This document describes responsibilities, not a file
listing — names drift, contracts do not.

## Layers

### Auth

Owns the Google OAuth desktop flow with PKCE, the loopback redirect server, and
token persistence.

- The client ID (and optional secret) is compiled into `Info.plist` at packaging
  time from local configuration. Nothing is fetched remotely, and nothing is
  committed.
- Refresh tokens and the access-token cache live in the macOS Keychain, keyed by
  the bundle identifier. UserDefaults never sees a token.
- A refresh failure or a revoked grant becomes `reauthRequired` and is surfaced,
  never swallowed by a retry loop.

### IMAP

A hand-rolled Gmail IMAP client over TLS to `imap.gmail.com:993`, authenticated
with XOAUTH2.

- `SELECT` a mailbox, then `IDLE`, re-arming below Gmail's server timeout.
- Fetch the smallest useful header set plus a bounded, non-mutating body preview
  (`BODY.PEEK[TEXT]<0.8192>`). Attachments and full bodies are never fetched.
- `UID STORE +FLAGS.SILENT (\Seen)` marks messages read on the server. UID sets
  are batched, so marking twenty messages is a few commands, not twenty
  connections.
- Previews pass through SwiftSoup for generic HTML handling, then Mailbell's own
  MIME-artifact, boilerplate, URL, whitespace, and line-shape rules.

### Service

The runtime. One monitor per enabled account, supervised centrally.

- **Checkpoints.** `UIDVALIDITY` plus `lastSeenUID` is the gap-fill anchor. A
  changed `UIDVALIDITY` rebaselines silently rather than notifying a backlog.
- **The review store** holds what is awaiting the user. Items are grouped by
  Gmail thread so a conversation counts once in the menu while notifications stay
  per message.
- **Dispositions** (`opened`, `markedRead`, `dismissed`) persist in UserDefaults,
  pruned to a bounded history, so a handled message never comes back.
- **Reconciliation** removes items read directly in Gmail Web and may admit
  bounded unknown unread items missed while offline.
- **Bulk actions** collect every pending group per account, mark them in one
  authenticated session, and publish a single state update.

### App surface

The menu bar extra, Settings, login item, Sparkle, and presentation helpers.

- `AppState` is the only thing views observe. It owns no business rules; it
  mirrors supervisor state and forwards user intent.
- The menu bar glyph has exactly one derivation with one precedence: **an account
  that needs the user outranks unread mail.** Sign-in expired or a surfaced error
  replaces the bell with an alert symbol, so the app can never look idle while it
  is monitoring nothing.
- Every visual constant comes from design tokens.

## Threading

The supervisor, review store, and all UI state are `@MainActor`. IMAP work runs
on its own connection tasks and crosses back through explicit `MainActor.run`
boundaries. Nothing blocks the main actor.

## Network activity

Two destinations, both user-visible:

1. **Google** — OAuth token endpoints and Gmail IMAP.
2. **Sparkle** — the appcast on GitHub, and the release asset when updating.

There is no third. No analytics, no telemetry, no crash reporting, no Mailbell
server.

## Persistence map

| What | Where | Why |
|---|---|---|
| Refresh and access tokens | Keychain | Secrets, and only secrets |
| Account list and webmail routing | UserDefaults | Non-secret metadata |
| IMAP checkpoints | UserDefaults | Cheap, per-account, disposable |
| Handled-item dispositions | UserDefaults | Bounded history, pruned |
| Menu bar and mail preferences | UserDefaults | Reset by Restore Defaults |

Restore Defaults clears the last row only. Accounts, tokens, checkpoints, and
handled history are user data, not preferences.
