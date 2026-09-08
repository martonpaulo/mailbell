# Mailbell

Mailbell is a native macOS menu-bar companion that alerts Gmail users to new
mail and keeps a review queue while Gmail Web remains the place for reading
and managing messages.

## User and job

For macOS users who want timely Gmail awareness without keeping Gmail open
throughout the day. Mailbell provides a notification and a lightweight review
entry, then opens the account in the selected browser or Chrome profile.

## Intended outcomes

- Notice new Inbox mail, and Spam when the user enables it.
- Review sanitized previews and act on pending messages.
- Open Gmail Web, mark messages read on Gmail, or dismiss them locally.
- Surface expired sign-in and connection errors so interrupted monitoring is visible.

## Boundaries and reasons

- No backend, relay, analytics, or telemetry: mail processing stays on the Mac.
- No full-body reader, attachments, compose, reply, archive, delete, move, or label
  management: Gmail Web owns those workflows, keeping Mailbell's data access and
  retained content small.
- Gmail only: the implemented authentication and monitoring contracts are Gmail-specific.
- IMAP IDLE remains the new-mail mechanism: avoid a separate content-polling loop.

## Success and constraints

Success means new mail becomes visible, review actions have accurate outcomes,
and interrupted monitoring clearly asks for the user's attention. Numeric
performance or retention targets are not established here; the pending queue
retention policy remains an owner decision in
[issue #27](https://github.com/martonpaulo/mailbell/issues/27).

Mailbell targets macOS 26+, uses public stable Apple APIs, stores tokens only in
Keychain, and distributes through signed and notarized direct downloads with
Sparkle updates. The Google OAuth client remains unverified; public copy must
disclose its warning screen and new-user cap.

The canonical website is [martonpaulo.com/mailbell](https://martonpaulo.com/mailbell/).
The detailed product, privacy, reliability, and release contracts remain in
[AGENTS.md](../AGENTS.md). This document does not resolve pending product
decisions or replace issue acceptance criteria.
