# Mailbell — Agent Policy

Durable root policy for Mailbell. Follow it for all coding, UI, documentation,
validation, packaging, git, and release-prep work in this repository. A more
specific `AGENTS.md` inside a subtree overrides this one for that subtree.

> This file documents **patterns and contracts**, not the current file layout.
> Describe responsibilities, not exact file or folder names — names drift, and
> stale structure docs are worse than none.

## Product

Mailbell is a notification-first Gmail companion for the macOS menu bar. It is a
native, accessory (menu-bar-only) app that runs entirely on the user's Mac.

Keep the implemented boundary tight:

- Notify on new Gmail mail (Inbox, and Spam when the user opts in).
- Surface a bounded review queue in the menu with sanitized previews.
- Open Gmail Web for reading and mail management, routed to the browser or
  Chrome profile the user chose per account.
- Act on the queue: open, mark as read on the server, dismiss locally, and the
  same three as bulk actions over everything pending.
- Full body viewing, reply, archive, delete, move, labels, compose, and
  attachments are **not** implemented and are not implied roadmap.

Each of those absent capabilities is allowed only as an explicit future product
change that first defines data minimization, on-demand fetch rules, storage
lifetime, scopes, UI and accessibility behavior, failure semantics, and tests.
Do not prebuild unused models, generic repositories, attachment caches, compose
systems, or Gmail API abstractions to look future-ready.

**No backend, ever.** There is no Mailbell server. Do not add cloud relays,
hosted backends, analytics, telemetry, public mail processing, or third-party
notification services. The only network activity is Gmail itself and Sparkle
update checks.

The expected flow is:

```text
MenuBarExtra
-> Google OAuth desktop client with PKCE (compiled into the bundle at build time)
-> Keychain token storage
-> Gmail IMAP XOAUTH2 against imap.gmail.com:993
-> SELECT INBOX
-> IMAP IDLE
-> fetch minimal headers plus bounded sanitized text preview
-> admit/group pending items
-> UNUserNotificationCenter notification
-> Gmail Web through the account webmail opener
```

## Build and validate

Prefer the smallest relevant check. Use `make` targets; do not hand-roll
equivalents.

- `make build` — debug build, must be warning-free.
- `make test` — unit tests.
- `make lint` — SwiftLint.
- `make validate` — repository invariants.
- `make check` — build + lint + test + validate.
- `make install` — ad-hoc signed bundle in `/Applications` (notifications need a
  real bundle, so this is the only way to exercise them).
- `make dmg` — ad-hoc signed installer DMG.
- `make release` — signed, notarized, stapled release DMG plus the Sparkle
  update archive and appcast entry. Requires a clean worktree on a `vX.Y.Z` tag.

Task logs and generated release artifacts live under `artifacts/` (gitignored).
Inspect a failed log before rerunning; never rerun an unchanged failing command.

## Hard rules

- **Public, stable Apple APIs only.** No private frameworks, no `_`-prefixed
  SPI, no beta-only behavior.
- **Native first.** SwiftUI for the menu and Settings; AppKit only where SwiftUI
  does not cover the surface. Do not replace native controls with custom UI
  unless there is clear product value and accessibility is preserved.
- **One bundle identifier: `com.perso.mailbell`.** Keychain service names and
  UserDefaults keys derive from it; changing it orphans user data.
- **Keep business logic out of views.** Views render prepared state. Keep
  expensive work out of SwiftUI `body` and never block the main actor.
- **DRY.** One home for each rule: menu-bar icon derivation, pending-item copy,
  status presentation, formatting, sorting, persistence, and defaults. No
  parallel implementations of the same rule.
- **Swift 6 concurrency.** Explicit, minimal `@MainActor` / actor boundaries; do
  not regress concurrency safety.
- **All visual constants come from design tokens.** No hardcoded sizes, insets,
  radii, or font sizes in views. Prefer semantic token names.

## Architecture (by responsibility)

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

Keep the SwiftPM structure standard: manifest at the root, the executable target
under `Sources/Mailbell`, tests under `Tests/MailbellTests`. Do not add local
packages, extra targets, or top-level folders for visual symmetry.

## OAuth and credential rules

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

## Security and data rules

- Never commit `.env`, credentials, tokens, signing material, logs containing
  secrets, or generated release artifacts.
- Never log tokens, OAuth codes, client secrets, IMAP auth payloads, raw message
  bodies, attachments, or full provider responses.
- Fetch only the smallest useful data: sender, subject, sent date, account, UID,
  RFC message ID, Gmail thread/message identifiers when available, and a bounded
  sanitized text preview.
- Body preview fetches stay bounded and non-mutating (`BODY.PEEK[TEXT]<0.8192>`).
  Never fetch attachments or full bodies.
- Sanitize previews before UI/notification use: SwiftSoup for generic HTML
  parsing and entity handling, then Mailbell's MIME-artifact, boilerplate, URL,
  whitespace, length, and line-shape rules.
- UserDefaults holds non-secret UI state, account metadata, webmail preferences,
  IMAP checkpoints, and pruned handled-item dispositions only.
- Keep Keychain and UserDefaults ownership DRY; no parallel persistence paths
  for the same state.

## Reliability rules

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
- Unread reconciliation removes items read directly in Gmail Web and may admit
  bounded unknown unread items missed while offline.
- Server-side read marking uses `UID STORE +FLAGS.SILENT (\Seen)`. Bulk actions
  use **one authenticated session per account**, never one connection per
  message.
- Refresh-token failure or revocation must surface as `reauthRequired` and must
  raise the menu bar alert icon. Do not hide it behind silent retry loops.
- Transient network failures may retry with bounded backoff but must not mask
  credential failure.
- Network recovery and sleep/wake force reconnects without broad polling.
- Do not introduce content polling as the new-mail mechanism; the IDLE re-arm
  timer is not a polling loop. Keep re-arm below Gmail's server limit.

## UI and UX rules

- Keep the app accessory-style and out of the Dock.
- The menu bar glyph has one owner and one precedence: an account needing the
  user (sign-in expired, surfaced error) outranks unread mail, so the alert
  symbol replaces the bell rather than the app looking idle while nothing is
  monitored.
- Settings stays small and native: menu bar, startup, notifications, accounts,
  advanced routing, updates, about.
- Preserve native controls, keyboard navigation, focus, hover/pressed/disabled/
  loading/error states, Dynamic Type, contrast, validation feedback, and safe
  areas.
- Before UI edits, briefly critique the current UI, then plan layout, controls,
  states, accessibility, and verification.
- Keep user-facing copy concise and consistent with nearby product language.

## Feature defaults and configurability

For every new user-facing behavior:

- Define its default explicitly, in the centralized settings defaults. Do not
  duplicate fallback values in views, services, tests, or migrations.
- Decide whether it is user-configurable and record why. Prefer a setting when
  both states are legitimate preferences; do not add settings for bug fixes,
  mandatory accessibility behavior, or single-outcome details.
- Persist configurable preferences through the typed settings layer, which is the
  runtime source of truth.
- Preserve existing user choices on upgrade; migrate a stored value only when the
  old representation is invalid.
- Register every configurable preference so Restore Defaults resets it. Reset
  must not touch accounts, Keychain tokens, permissions, or handled-item history.

A missing configurability decision is a review failure. See
`docs/feature-defaults.md`.

## Distribution and signing

- Distribution is **direct download only**: a notarized, stapled DMG signed with
  the stable Developer ID Application identity, plus Sparkle auto-update driven
  by an appcast hosted from this repository.
- Sparkle is embedded only in the packaged app and only starts from a real
  installed bundle that ships both a feed URL and a public key.
- **Signing material is never committed.** The Sparkle EdDSA private key lives in
  the login Keychain; only the public key ships in the bundle. Developer ID
  identity and notary credentials come from local environment/Keychain.
- Releases are tagged `vX.Y.Z`; the tag must match `CFBundleShortVersionString`.
  The appcast is regenerated from the built, signed archive and committed before
  the GitHub Release is published.
- The website under `docs/` is the public landing page, privacy policy, and
  terms. It is deployed by GitHub Pages from `main`.

## Conventions

- Conventional Commits. **English everywhere** — code, comments, docs, copy,
  errors, examples, file names.
- Comments state constraints the code cannot show (Gmail quirks, why a bound
  exists), not narration of what the code already says.
- Human-readable code over cleverness. Small, well-named units.
- Search first; read the smallest useful chunk; reuse existing code, patterns,
  components, formatters, helpers, and Makefile targets before adding new ones.
- No new dependencies unless clearly required, justified, and consistent with a
  native, low-cost menu-bar app.
- Add or update focused tests only for changed behavior, regressions,
  persistence contracts, accessibility-critical flows, or validation-sensitive
  code. Avoid tests that mirror implementation details or duplicate coverage.
- If documentation conflicts with code, treat code as truth, then update the
  smallest relevant doc section.

## Pattern-break protocol

This file is the source of truth for how Mailbell is built. **If a task seems to
require breaking an established pattern** — a second persistence path, a
hardcoded dimension, a new dependency, polling, business logic in a view, a
backend, or a broader OAuth scope — **stop and confirm with the user before
either forcing the change into the old pattern or defining a new one.** Name the
pattern in tension, the options, and the tradeoff. Silent divergence is a defect.
When a genuinely new pattern is agreed, document it here in the same turn.

## Git and completion

- Check `git status --short --branch` before editing and before the final reply.
  Work on `main` unless the user asks otherwise.
- Use focused Conventional Commits for durable changes. Commit only files that
  belong to the task; leave unrelated dirty files untouched and report them.
- Do not revert, overwrite, or discard user changes unless explicitly asked.
- Do not push to the `upstream` remote (the original project) under any
  circumstance.
- Final report includes: changed files, validation performed, artifacts
  kept/deleted, commit and push status, final `git status --short --branch`,
  unrelated dirty files, and remaining risks.

## Agent skill paths

- Domain glossary: `CONTEXT.md` (optional; create only when useful)
- ADRs: `docs/adr/` (only for hard-to-reverse, non-obvious decisions)
- Research notes: `docs/research/` (create only when persisting research)
- Handoffs: `.scratch/handoffs/`
- Prototypes: `.scratch/prototypes/`
