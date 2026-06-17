# Mailbell Agent Policy

This is the durable root policy for the personal-use Mailbell fork. Follow it for all coding, documentation, validation, git, and release-prep work in this repository.

## Product Boundary

Mailbell is a minimal local macOS menu bar notifier for Gmail. It is a notification bridge, not an email client.

Keep the product boundary tight:

- Notify on new Gmail inbox mail.
- Open Gmail Web for reading and mail management.
- Do not add mailbox UI, message body reading, attachment reading, reply, archive, delete, move, label, compose, or message-management flows.
- Do not add cloud relay services, hosted backends, analytics relays, public mail processing, or third-party notification services.
- Do not introduce content polling as the primary new-mail mechanism. Gmail IMAP IDLE is the product transport; the liveness re-arm timer is not a content polling loop.

The expected flow is:

```text
MenuBarExtra
-> user-owned Google OAuth desktop client with PKCE
-> Keychain token storage
-> Gmail IMAP XOAUTH2 against imap.gmail.com:993
-> SELECT INBOX
-> IMAP IDLE
-> fetch headers only
-> UNUserNotificationCenter notification
-> Gmail Web through the account webmail opener
```

## Architecture Map

This is a SwiftPM macOS 26+ executable app:

- Package definition: `Package.swift`
- App entry, menu, Settings UI, login item: `Sources/Mailbell/App/`
- OAuth config/client, loopback redirect, token persistence, Keychain wrapper: `Sources/Mailbell/Auth/`
- IMAP models, client, connection, parser, MIME header decoding: `Sources/Mailbell/IMAP/`
- Runtime/state machine and checkpoints: `Sources/Mailbell/Service/`
- Provider URL/routing model: `Sources/Mailbell/Provider/`
- Native notifications: `Sources/Mailbell/Notify/`
- Browser/profile webmail opening: `Sources/Mailbell/Webmail/`
- Packaging metadata/assets: `Resources/`
- Package/install/DMG scripts: `Makefile` and `Scripts/`
- Tests: `Tests/MailbellTests/`

Prefer the existing ownership boundaries above before adding new files or abstractions.

## OAuth Privacy Rules

This personal fork must use only the user's own Google OAuth credentials.

- Do not preserve, ship, document as usable, or fall back to the original developer's Google OAuth client ID or client secret.
- Do not add hardcoded OAuth credentials, placeholder secrets that look usable, bundled fallback credentials, or remote credential download paths.
- Real OAuth credentials may come only from local/private configuration such as `.env`, shell environment variables, local build settings, or a locally injected bundle plist.
- `.env` must stay untracked. `.env.example` may contain variable names only, with empty values.
- Build/runtime paths must fail clearly or show setup guidance when credentials are missing. Do not silently continue with fake, upstream, or fallback credentials.
- OAuth uses Google's desktop/installed-app flow with PKCE and the scopes required for the current IMAP implementation: `https://mail.google.com/`, `openid`, and `email`.
- Refresh tokens and access-token cache belong in the macOS Keychain only.

## Security And Data Rules

- Do not commit `.env`, real OAuth credentials, refresh tokens, access tokens, logs containing secrets, build artifacts, or generated release artifacts unless explicitly requested and safe.
- Do not log tokens, OAuth codes, client secrets, IMAP auth payloads, raw message bodies, attachments, or full provider responses that may contain secrets.
- Fetch message headers only for notifications: sender/from, subject, date, account, UID, and Gmail thread/message identifiers when available.
- Do not fetch message bodies or attachments unless the user explicitly changes the product scope.
- UserDefaults may hold non-secret UI state, account metadata, webmail preferences, and IMAP checkpoint data only.
- Keep Keychain and UserDefaults ownership DRY; do not introduce parallel persistence paths for the same state.
- Treat the broad `https://mail.google.com/` scope honestly. Do not claim a narrower Gmail API scope works for the current IMAP XOAUTH2 implementation.

## Reliability Rules

Preserve the IMAP IDLE reconnect model in `MailMonitor` or its direct successor:

- `UIDVALIDITY` plus `lastSeenUID` is the gap-fill checkpoint.
- If `UIDVALIDITY` changes, rebaseline silently without notifying the backlog.
- On reconnect with the same `UIDVALIDITY`, fetch headers for UIDs above the checkpoint and notify the gap.
- Refresh-token failure or token revocation must surface as `reauthRequired`; do not hide it behind silent retry loops.
- Transient network failures may retry with bounded backoff, but must not mask credential failure.
- Network recovery and sleep/wake should force reconnects without broad polling.
- Keep IDLE re-arm below Gmail's server limit. Verify the timeout against source and docs when editing this area.
- Do not add new observers, timers, caches, polling, background jobs, broad fetches, or concurrency surfaces unless required and justified.
- Keep Swift 6 compatibility as the direction. Preserve explicit, minimal actor/main-actor boundaries and do not regress Swift concurrency safety.

## UI And UX Rules

- Use native SwiftUI first and AppKit only where SwiftUI does not cover menu bar, Settings, login item, notification, or browser-opening behavior.
- Keep the app accessory-style and out of the Dock by default.
- Keep Settings small: OAuth/setup state, account status/actions, browser routing, start at login, sign in/reconnect/disconnect.
- Preserve native controls, keyboard navigation, focus, hover/pressed/disabled/loading/error states, Dynamic Type, contrast, validation feedback, and safe areas.
- Before UI edits, critique the current UI briefly and plan layout, controls, states, accessibility, validation, and verification.
- Do not replace native controls with custom UI unless there is clear product value and accessibility is preserved.
- Keep user-facing copy concise and consistent with nearby product language.

## Workflow Rules

- Search first. Use `rg`/`rg --files` where available and read the smallest useful chunks.
- Reuse existing code, patterns, components, services, mappers, formatters, helpers, tests, and Makefile targets before adding new ones.
- Keep changes scoped to the task. Avoid unrelated cleanup, redesigns, broad refactors, dependency changes, or future-phase work.
- No new dependencies unless they are clearly required, justified, and consistent with a native, low-cost macOS app.
- Enforce DRY for business rules, copy lists, state, formatting, sorting, filtering, mapping, persistence, and parallel implementations.
- Add or update focused tests only for changed behavior, regressions, persistence/sync contracts, accessibility-critical flows, or validation-sensitive code.
- Avoid tests that mirror implementation details, constants, behaviorless wrappers, or duplicate existing coverage.
- Run the smallest relevant validation first. For normal code edits, prefer `make build`; use `make test` or `make check` when the change warrants it.
- Logs and command captures for task work must go under `artifacts/`.
- Inspect failed logs before rerunning. Never rerun the same failing command without a relevant code/config change or a clearly different diagnostic purpose.
- Delete current-task temporary artifacts before closeout unless they are requested deliverables, needed failure evidence, or required by repo rules. Never delete pre-existing user files or unrelated artifacts.
- Do not revert, overwrite, discard, or delete user changes unless explicitly requested.
- If documentation conflicts with code, treat code as truth, then update the smallest relevant doc section when the task asks for docs or a code change would leave false instructions behind.

## Website, Branch, And Public Distribution Rules

- This fork is for personal local use. Do not create a website, gh-pages flow, public marketing site, public distribution flow, hosted OAuth domain site, or generated static site unless it directly supports local personal use and the user asks for it.
- Do not merge or preserve `gh-pages`, generated Pages output, public marketing artifacts, or upstream site deployment workflows by default.
- Branches such as `website`, `docs/github-pages`, and `gh-pages` are ignore/delete candidates for the personal fork. Port only genuinely useful personal setup guidance into `README.md` or local docs.
- Public OAuth verification, CASA, notarized distribution, and public release automation are out of scope unless the user explicitly changes the distribution goal.

## Git And Completion

- Check `git status --short --branch` before editing and before final response.
- Use focused Conventional Commits for durable repository changes.
- Commit only files that belong to the current task. Leave unrelated dirty files untouched and report them.
- Push when a personal `origin` remote is configured and the task asks for commit/push or repo policy requires it.
- Do not push to upstream unless explicitly requested.
- Final reports must include changed files, validation commands/results, artifacts kept/deleted, commit and push status, final `git status --short --branch`, unrelated dirty files, and risks or follow-ups.

## Conflict Resolution

- These root instructions apply unless a more specific in-repo `AGENTS.md` overrides them for its subtree.
- Upstream product/security rules beat generic polish or feature-expansion ideas.
- Personal-use OAuth/privacy rules beat upstream behavior that ships, assumes, documents, or falls back to the original developer's OAuth client.
- Direct user instructions for the current task override standing preferences unless unsafe, impossible, or outside the product/privacy boundary.
