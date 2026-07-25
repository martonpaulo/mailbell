# Changelog

All notable changes to Mailbell are documented here. This project follows
[Semantic Versioning](https://semver.org/) and
[Keep a Changelog](https://keepachangelog.com/).

## 0.1.1 — 2026-07-25

Settings now follows macOS System Settings conventions, and a preview defect
that reached real notifications is fixed.

> **Google OAuth unverified beta.** Unchanged from 0.1.0: Google shows an
> "unverified app" screen during sign-in and limits unverified clients to
> **100 new users**.

### Fixed

- **Notification previews no longer leak Markdown.** A message whose plain-text
  alternative was Markdown could reach the notification as
  `[![]( [IMG] broadcast\_body\_warning`. Escaped punctuation is now unescaped,
  image and link scaffolding is unwrapped, and heading, quote, and rule markers
  are stripped.
- **The account toggle no longer reads as its own opposite.** It was labelled
  "Disable Account" while switched on; it now says "Watch this account for new
  mail".

### Changed

- **Settings is four panes instead of six.** Everything about an account —
  status, review count, where its mail opens, reconnecting, removal — now lives
  in that account's own section, instead of being split between Accounts and
  Advanced. Spam moved to a "Watched Mailboxes" section that states plainly that
  Inbox is always watched, and Updates folded into General.
- **Controls follow the platform.** Action buttons are sized to their content
  and trailing-aligned, placed by scope the way System Settings places them:
  in the row for a row-scoped action, as the box's last row for a section-scoped
  one, and below every box for a pane-scoped one such as Restore Defaults.
  Explanations sit under their own control's label rather than in a footer.
- Sign-in now warns about Google's unverified-app screen *before* you meet it.
- The review count per account no longer hides behind the menu bar count
  preference.

### Internal

- One build number derivation shared by the local and CI release paths.
- Settings control-semantics rules moved into repository validation.

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
