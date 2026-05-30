# Mailbell Agent Notes

## Project Boundary

`mailbell` is a minimal macOS menu bar notifier for Gmail. It is a local notification bridge, not an email client.

Keep the product boundary tight:

- Notify on new Gmail inbox mail.
- Open Gmail Web for reading and mail management.
- Do not add mailbox UI, message body reading, reply/archive/delete/label/compose flows, or cloud relay services unless the user explicitly changes the product scope.
- Do not introduce content polling as the primary new-mail mechanism. The current design is Gmail IMAP IDLE with a liveness re-arm timer.

## Architecture

This is a SwiftPM macOS 13+ executable app:

- Package: `Package.swift`
- App entry and menu/settings UI: `Sources/Mailbell/App/`
- OAuth, loopback redirect, token persistence: `Sources/Mailbell/Auth/`
- IMAP models/client/connection/parsing: `Sources/Mailbell/IMAP/`
- Connection state machine: `Sources/Mailbell/Service/MailMonitor.swift`
- Native notifications: `Sources/Mailbell/Notify/`
- Packaging metadata: `Resources/Info.plist`

The expected flow is:

```text
MenuBarExtra
-> Google OAuth desktop client with PKCE
-> Keychain token storage
-> IMAP XOAUTH2 against imap.gmail.com:993
-> SELECT INBOX
-> IMAP IDLE
-> fetch headers only
-> UNUserNotificationCenter notification
-> Gmail Web
```

## Security And Data Rules

- Refresh tokens and access-token cache belong in Keychain only.
- UserDefaults may hold non-secret UI state, the account email, and IMAP checkpoint data.
- Do not log tokens, OAuth codes, client secrets, IMAP auth payloads, or raw message bodies.
- A Google desktop OAuth client secret is not confidential, but still avoid treating it as regular app text outside the configured storage path.
- IMAP requires the broad `https://mail.google.com/` scope. Do not claim a narrower Gmail API scope works for the current IMAP implementation.
- Fetch headers only for notifications unless the user explicitly approves a broader data surface.

## State And Reliability

Preserve the reconnect model in `MailMonitor`:

- `UIDVALIDITY` plus `lastSeenUID` is the gap-fill checkpoint.
- If `UIDVALIDITY` changes, rebaseline without notifying the backlog.
- Refresh-token failure must surface as `reauthRequired`; do not hide it behind silent retry loops.
- Network recovery and sleep/wake should force reconnect promptly.
- Keep IDLE re-arm below Gmail's 29-minute limit.

## UI Rules

- The app is accessory-style and should stay out of the Dock by default.
- Keep settings small: OAuth client configuration, account status, start at login, sign in/disconnect.
- Native notifications need a real app bundle identifier. `make run` is useful for development, but notification verification requires a bundled app via `make install` or the packaging script.

## Build And Verification

Prefer the project Makefile targets:

```bash
make help
make build
make run
make test
make lint
make check
make install
make dmg
```

Use `make build` as the narrow compile check for normal code edits. Use `make check` when SwiftLint is available and the change is meant to be ready for broader review.

For behavior touching notifications, login items, app bundle metadata, or launch behavior, verify with an installed/bundled app, not only `swift run` or `make run`.

## Documentation

`docs/design.md` captures the current product decisions. Treat code as truth when it conflicts with docs, then update the smallest relevant doc section only when the user requested documentation changes or the code change would otherwise leave a false instruction behind.
