# Architecture

Mailbell is a SwiftPM executable: a macOS 26+ accessory app with no backend of
any kind. Its package layout is in [AGENTS.md](../AGENTS.md), "Architecture". This document describes responsibilities, not a file
listing — names drift, contracts do not.

## Targets

- **`MailbellKit`** holds the pure logic, with no system framework and no
  network: IMAP response parsing, the IMAP value models and UID sequences, MIME
  header decoding, the body-preview pipeline, header and date formatting,
  `StorageKeys` and the stores over an injected `UserDefaults` (accounts,
  checkpoints, settings, handled history), the review store and its ordering,
  retention and actions, monitor status, the webmail URL rules, OAuth
  configuration and token values, the loopback callback page, and the menu bar
  and account presentation rules. It imports only `Foundation`, `Observation`,
  `Synchronization` and `CoreGraphics`, keeps the nonisolated default, and
  exposes `public` only what the app uses.
- **`Mailbell`**, the app target, holds what wraps a system framework or the
  network: `AppState`, the views, `UpdateManager` (Sparkle), `NotificationManager`
  (UserNotifications), the IMAP client and connection, `MailMonitor`,
  `AccountSupervisor`, the OAuth client and loopback server, the Keychain
  wrappers, the webmail opener, logging, and the SwiftSoup HTML extractor.
- The preview sanitizer takes its HTML extractor as a required parameter, and
  `IMAPClient` passes the app's SwiftSoup one. The same client turns the raw
  Subject into display text when it parses a header, so a header reaching the
  review store already carries its title text and the Kit never sees SwiftSoup
  (Decided on #80).

## Layers

By responsibility:

- **Auth** — OAuth config/client, PKCE, loopback redirect, token persistence,
  Keychain wrapper.
- **IMAP** — models, client, connection, parser, MIME header decoding,
  body-preview sanitizing, and the read-flag command.
- **Service** — runtime state machine, checkpoints, the pending review store,
  unread reconciliation, and mark-as-read / bulk-action orchestration.
- **Provider** — webmail URL and routing model.
- **Notify** — native notification content and delivery.
- **Webmail** — browser and Chrome-profile opening.
- **App** — menu bar surface, Settings, login item, Sparkle, design tokens, and
  presentation helpers.

### Auth

Owns the Google OAuth desktop flow with PKCE, the loopback redirect server, and
token persistence.

- The client ID (and optional secret) is compiled into `Info.plist` at packaging
  time from local configuration. Nothing is fetched remotely, and nothing is
  committed.
- Refresh tokens and the access-token cache live in the macOS Keychain, keyed by
  the bundle identifier. UserDefaults never sees a token. A new identifier
  orphans the tokens by design: after the 0.4.0 move every account signs in
  again once (Decided on #47).
- A refresh failure or a revoked grant becomes `signInRequired` and is surfaced,
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
  MIME-artifact, boilerplate, URL, whitespace, and line-shape rules. Subjects
  go through the same pipeline once, when the header is parsed.

### Service

The runtime. One monitor per enabled account, supervised centrally.

- **Checkpoints.** `UIDVALIDITY` plus `lastSeenUID` is the gap-fill anchor. A
  changed `UIDVALIDITY` rebaselines silently rather than notifying a backlog.
- **The review store** holds what is awaiting the user. Items are grouped by
  Gmail thread so a conversation counts once in the menu while notifications stay
  per message.
- **Queue order** is Gmail's ordinary inbox chronology: newest server receipt
  (`INTERNALDATE`) first. A conversation is as new as its newest *pending*
  member, so a reply lifts the thread while the first-admitted message stays its
  representative. Groups the server gave no usable timestamp for follow the
  dated ones in admission order. The sender's own `Date` header is never
  substituted for server receipt. Decided on #11.
- **Dispositions** (`opened`, `markedRead`, `dismissed`) persist in UserDefaults,
  pruned to a bounded history. Dismissed items are suppressed; opened or marked-read items may reappear if still unread.
- **Reconciliation** removes items read directly in Gmail Web and may admit
  bounded unknown unread items missed while offline. It skips both pending and
  already-handled UIDs, so its bounded window makes progress instead of
  re-selecting the same discarded messages forever.
- **Bulk actions** collect every pending group per account, mark them in one
  authenticated session, and publish a single state update.
- **Mailbox generation.** A message is identified by mailbox name, `UIDVALIDITY`
  and UID together. Read actions re-check the generation from their own `SELECT`
  before `STORE`, and a generation change drops the pending items captured under
  the old one, so a reused UID can never be marked by mistake.

### App surface

The menu bar extra, Settings, login item, Sparkle, and presentation helpers.

- Sparkle is embedded only in the packaged app and only starts from a real
  installed bundle that ships both a feed URL and a public key.
- `AppState` is the only thing views observe. It owns no business rules; it
  mirrors supervisor state and forwards user intent.
- The menu bar glyph has exactly one derivation; its precedence is in
  [interface.md](interface.md#menu-bar-glyph).
- Every visual constant comes from design tokens.

## Threading

The supervisor, review store, and all UI state are `@MainActor`: the app target
is main-actor by default, and the review store in MailbellKit says so explicitly
because the Kit keeps the nonisolated default. IMAP work runs
on its own connection tasks and crosses back through explicit `MainActor.run`
boundaries. Nothing blocks the main actor. Keep `@MainActor` and actor
boundaries explicit and minimal; do not regress Swift 6 concurrency safety.

## Ownership

One home for each rule: menu-bar icon derivation, pending-item copy, status
presentation, formatting, sorting, persistence, and defaults. No parallel
implementations of the same rule.

## Network activity

Two destinations, both user-visible:

1. **Google** — OAuth token endpoints and Gmail IMAP.
2. **Sparkle** — the appcast on GitHub, and the release asset when updating.

There is no third. No analytics, no telemetry, no crash reporting, no Mailbell
server.

## OAuth and credentials

Mailbell ships as a public beta whose Google OAuth client is **not yet verified
by Google**.

- Release builds embed the project's own Google Desktop OAuth client, injected
  into `Info.plist` at packaging time from local configuration. End users never
  create their own client.
- Real credentials come only from local/private configuration: `.env`, shell
  environment, or the injected bundle plist. **`.env` stays untracked.**
  `.env.example` carries variable names with empty values.
- Never commit a client ID or secret, and never add a remote credential download
  path. Google treats installed-app client secrets as non-confidential, but they
  still belong in local configuration, not in git.
- A build without credentials must fail clearly and, in the UI, present a
  **build/packaging error** — never instructions telling an end user to create a
  Google Cloud client.
- OAuth uses Google's desktop/installed-app flow with PKCE and the scopes the
  IMAP implementation actually needs: `https://mail.google.com/`, `openid`, and
  `email`. Treat the broad mail scope honestly; do not claim a narrower Gmail
  API scope works for IMAP XOAUTH2.
- Refresh tokens and the access-token cache belong in the macOS Keychain only.
- Public copy (README, website, release notes, Settings) must state the
  unverified-app screen and Google's 100-new-user cap for unverified clients,
  and must not promise unlimited use before verification.

## Data minimization

- Never commit `.env`, credentials, tokens, signing material, logs containing
  secrets, or generated release artifacts.
- Never log tokens, OAuth codes, client secrets, IMAP auth payloads, raw message
  bodies, attachments, or full provider responses.
- Log through `Log.<area>` (`os.Logger`, subsystem = bundle identifier). Addresses,
  senders, subjects, message identifiers and error details are interpolated
  `.private` after `Log.redact`; user-facing error text carries no technical
  detail, which goes to the log through `Log.detail` (#61).
- State lives in `@Observable` models passed by initializer; there is no
  `ObservableObject` and no `.shared` singleton. `NotificationManager` is created
  once at launch and reaches monitors through `MailNotifying` (#62).
- Fetch only the smallest useful data: sender, subject, sent date, server
  receipt time (`INTERNALDATE`), account, UID, RFC message ID, Gmail
  thread/message identifiers when available, and a bounded sanitized text
  preview.
- Body preview fetches stay bounded and non-mutating (`BODY.PEEK[TEXT]<0.8192>`).
  Never fetch attachments or full bodies.
- Sanitize previews before UI/notification use: SwiftSoup for generic HTML
  parsing and entity handling, then Mailbell's MIME-artifact, boilerplate, URL,
  whitespace, length, and line-shape rules.
- UserDefaults holds non-secret UI state, account metadata, webmail preferences,
  IMAP checkpoints, and pruned handled-item dispositions only.
- Keep Keychain and UserDefaults ownership DRY; no parallel persistence paths
  for the same state.

## Reliability contracts

Preserve the IMAP IDLE reconnect model:

- `UIDVALIDITY` plus `lastSeenUID` is the gap-fill checkpoint.
- If `UIDVALIDITY` changes, rebaseline silently without notifying the backlog.
- On reconnect with the same `UIDVALIDITY`, fetch fresh unread UIDs above the
  checkpoint, admit all fresh items in bounded batches, and notify only the
  newest capped set.
- Never advance `lastSeenUID` past a fresh UID until its admission batch has been
  fetched and offered to the pending store.
- Threaded pending items count once in the menu when Gmail thread IDs exist;
  notifications remain per message.
- A read action fixes its set of members before the server round trip and
  finalizes only that set. A reply that joins the thread while the request is in
  flight was never marked on the server, so it stays pending. Decided on #22.
- Unread reconciliation removes items read directly in Gmail Web and may admit
  bounded unknown unread items missed while offline. Its bounded window skips
  what is already pending **and** what has already been handled, so a wholly
  dismissed newest window cannot consume every cycle's budget and starve older
  unread mail. Handled records remember where the message lived; a record
  without that location is backfilled the first time reconciliation meets it.
- Server-side read marking uses `UID STORE +FLAGS.SILENT (\Seen)`. Bulk actions
  use **one authenticated session per account**, never one connection per
  message.
- A message identity is `(mailbox name, UIDVALIDITY, UID)`, never a UID alone.
  A read action checks the generation reported by its own `SELECT` before
  issuing `STORE`, so a rebuilt mailbox that reused the number cannot be
  mutated. Pending items from a superseded generation are dropped on
  reconciliation rather than left actionable.
- Refresh-token failure or revocation must surface as `signInRequired` and must
  raise the menu bar alert icon. Do not hide it behind silent retry loops.
- Transient network failures may retry with bounded backoff but must not mask
  credential failure.
- Network recovery and sleep/wake force reconnects without broad polling.
- One run owns an account at a time. A run suspends on the network repeatedly,
  and cancelling its task does not stop the resumed continuation, so every
  effect — owning a client, publishing status, moving checkpoints, admitting
  messages — is gated on the run still being the current generation.
- Do not introduce content polling as the new-mail mechanism; the IDLE re-arm
  timer is not a polling loop. Keep re-arm below Gmail's server limit.

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

`StorageKeys` is the one owner of every UserDefaults key, including the
checkpoint key builder, the #47 migration marker and the two SwiftUI Settings
keys that screenshot mode pins. Stores name a key only through it, and
`scripts/validate.sh` fails on a key string literal passed to a UserDefaults
accessor anywhere else (#79). New keys end in `.v1`. Two predate that rule and
stay unversioned: the account list (`mailbell.accounts`) and the checkpoint keys
(`mailbell.account.<uuid>.mailbox.<name>.uidValidity` and `.lastSeenUID`).
Renaming them would need a migration whose only effect is risk to every user's
accounts and gap-fill anchors, and a stored value is migrated only when its old
representation is invalid ([feature defaults](feature-defaults.md)). Decided on #62.

## Screenshots

Screenshots are captured from the **real on-screen window**, never rendered
offscreen: an offscreen bitmap loses the drop shadow, the corner radius, the
material and the elevation, and raising the scale factor does not bring them
back.

Mailbell is an accessory app, so nothing else on the system can reliably say
which window is its. `Mailbell --screenshot-mode` therefore opens Settings
through the same action the menu uses, pins the window size and the selected
pane so the result does not depend on the developer's machine, activates the
window, and only then prints its own `CGWindowID` followed by a readiness
marker. A capture taken before that marker shows an inactive window: grey
traffic lights and dimmed controls.

`scripts/capture-screenshots.sh` consumes that output and runs
`screencapture -l<windowid>`. It never passes `-o`, which is the flag that
strips the shadow, and it refuses to run without a Retina display, because a 1x
display silently halves the resolution. Output is lossless WebP: identical
pixels, the shadow's alpha preserved, and roughly 70% smaller than the PNG.
The General pane is the site's hero, so the script also writes `general-480.webp`
and `general-800.webp`, which the page's `srcset` and preload `imagesrcset` list
next to the full-size file. They are resampled from the lossless capture and
encoded near-lossless: plain lossless makes a resampled screenshot so much
larger that a 1200 px width would outweigh the full 1576 px file, which is why
there is none.

The Accounts pane is not captured by default. It shows the connected address,
and a published screenshot would carry a real person's email.
