# Changelog

All notable changes to Mailbell are documented here. This project follows
[Semantic Versioning](https://semver.org/) and
[Keep a Changelog](https://keepachangelog.com/).

## Unreleased

The website moved to its own subdomain. The links the app opens follow it.

### Changed

- **The website is now `https://mailbell.martonpaulo.com/`.** The About pane's
  website, privacy policy, and terms links open the new address. The old
  `martonpaulo.com/mailbell/` path is gone and does not redirect, so 0.3.0
  and earlier open a "not found" page from those links until they update.

## 0.3.0 — 2026-09-09

Previews that were showing you CSS, base64 and invisible filler now show the
message. Mail is listed in the order Gmail lists it. And several ways Mailbell
could act on the wrong message, or quietly stop watching, are closed.

> **Google OAuth unverified beta.** Unchanged: Google shows an "unverified app"
> screen during sign-in and limits unverified clients to **100 new users**.

### Fixed

- **Previews showed stylesheets instead of the message.** A notification could
  open with `body, table, td { font-family: Arial… }`. Mail whose stylesheet
  arrived without its opening tag now has it removed, and a message that is
  nothing but styling shows no preview rather than showing code.
- **Previews showed raw base64.** Some mail arrived as
  `ICAgIMKhSmFuZSB0ZSBpbnZpdMOz…`. Two causes: the fetch could cut the payload
  at a length that cannot be decoded, and some transports fold it on spaces.
  Both decode now.
- **Previews filled up with invisible characters.** Marketing mail pads its
  preheader with zero-width and no-break characters to keep the inbox snippet
  short. Those runs used up the whole preview before any readable text. They
  are removed — but a single joiner is left alone, so emoji and Persian and
  Indic text are unaffected.
- **Accented characters and currency symbols could vanish.** Mail that declares
  one encoding but sends another lost its euro signs and curly quotes.
- **Previews opened on a "view online" link.** A leading link marker is dropped
  when there is a message behind it.
- **The queue was not in Gmail's order.** After a reconnect, mail appeared in
  whatever order the server answered. It now follows the same chronology Gmail
  uses, and a reply lifts its whole conversation.
- **Mark as Read could mark the wrong message.** If Gmail rebuilt a mailbox and
  reused a number, an action prepared beforehand could land on a different
  message. Every read action now checks that the mailbox is still the one it
  was prepared against, and refuses instead of guessing.
- **A reply arriving mid-action was marked read without being read.** Only the
  messages actually sent to the server are finalized.
- **Older unread mail could never reach the queue.** If everything recent had
  been dismissed, each check spent its whole budget on those same messages.
- **Check Now could stop working.** Cancelling a connection mid-handshake left
  the account stuck with no way to recover.
- **An account could keep working after you turned it off.** Stopping or
  restarting an account now takes effect even mid-connection.
- **Inbox and Spam notifications could replace each other** when two messages
  happened to share a number.
- **The menu bar told VoiceOver to sign in for problems that need Reconnect.**

### Added

- **Failures now appear where you started them.** A bulk result, a Gmail that
  opened in the wrong browser, and a sign-in that failed from the menu are all
  visible in the menu instead of being silently discarded.
- **The queue has a stated limit.** Each account keeps up to 500 recent
  messages and shows up to 50 conversations, and the menu says how many more
  are waiting with a link to Gmail. Nothing is marked read or deleted — Gmail
  keeps everything.
- **Settings says what Google's unverified status actually means for you**,
  including the 100-new-user cap.
- **Screenshots on the website and README**, captured from the real window.

### Changed

- **Two System Settings buttons stopped promising a destination** they cannot
  guarantee; each now says what it does and tells you where to go.
- **The sign-in page in your browser no longer says you are connected** before
  Mailbell has finished. It points you at the menu bar to confirm.
- **Terms now distinguishes removing an account from revoking access at
  Google.** Removing it in Mailbell deletes your tokens locally; it does not
  tell Google anything.

## 0.1.2 — 2026-07-26

An expired sign-in now reaches you instead of waiting to be noticed.

> **Google OAuth unverified beta.** Unchanged from 0.1.0: Google shows an
> "unverified app" screen during sign-in and limits unverified clients to
> **100 new users**.

### Added

- **A notification when an account's sign-in expires.** Until now the only
  signal was the menu bar alert icon, which helps only if you happen to look at
  it — Mailbell could stop watching your mail quietly. The alert names the
  account, fires once per expiry, and is not a preference, for the same reason
  the alert icon is not.

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
