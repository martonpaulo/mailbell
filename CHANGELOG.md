# Changelog

All notable changes to Mailbell are documented here. This project follows
[Semantic Versioning](https://semver.org/) and
[Keep a Changelog](https://keepachangelog.com/).

## 0.1.0 — 2026-07-25

First public beta.

> **Google OAuth unverified beta.** Mailbell's Google OAuth client has not been
> verified by Google yet. During sign-in Google shows an "unverified app" screen,
> and Google limits unverified clients to **100 new users**. Mailbell still runs
> entirely on your Mac and no Gmail data passes through any server operated by
> this project.

### New

- **Mark All as Read** clears the whole review queue and marks every message read
  in Gmail, using one authenticated IMAP session per account instead of one
  connection per message.
- **Dismiss All** clears the review queue locally without touching Gmail.
  Dismissed messages stay unread in your mailbox and do not come back.
- **Menu bar alert icon.** When an account needs you to sign in again, or has a
  surfaced error, the menu bar shows an alert symbol instead of the normal bell,
  so Mailbell can no longer look idle while it is monitoring nothing.
- **Automatic updates** via [Sparkle](https://sparkle-project.org), verified
  against the release signature before replacing the app.
- **Updates pane** in Settings with an automatic-check toggle, the current
  version, and a manual check.
- **Restore Defaults** in Settings, which resets menu bar and mail preferences
  without touching accounts, sign-ins, or notification permission.
- **About pane** with links to the website, source, issue tracker, latest
  release, privacy policy, terms, and Google access management.
- A public [website](https://martonpaulo.github.io/mailbell/) with the privacy
  policy and terms of service.

### Changed

- Mailbell is now distributed as a signed, notarized, stapled DMG through GitHub
  Releases, with the Google OAuth client already configured. You no longer need
  to create your own Google Cloud client to use it.
- When a build is packaged without OAuth credentials, Settings reports it as a
  build problem with a link to the issue tracker, rather than instructing you to
  create a Google Cloud client.
- Settings panes share one window size, so switching panes no longer resizes the
  window.
- Every packaging path (install, DMG, release) now goes through one bundle
  builder, so the layout and the Sparkle nested-signing order have a single
  definition.

### Internal

- Marking messages read batches UID sets per mailbox over a single IMAP session.
- Repository invariants are enforced by `Scripts/validate.sh` and run in CI.
