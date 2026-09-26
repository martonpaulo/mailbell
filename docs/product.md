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

## Implemented boundary

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

## Reasons for the boundary

- No backend: mail processing stays on the Mac.
- No reader or mail management: Gmail Web owns those workflows, keeping
  Mailbell's data access and retained content small.
- Gmail only: the implemented authentication and monitoring contracts are Gmail-specific.
- IMAP IDLE remains the new-mail mechanism: avoid a separate content-polling loop.

## Success and constraints

Success means new mail becomes visible, review actions have accurate outcomes,
and interrupted monitoring clearly asks for the user's attention. Numeric
performance targets are not established here. The
[queue limits](feature-defaults.md#queue-limits) keep a per-account recent
window with separate retention and menu-display limits, implemented by
`PendingQueueBudget`.

Mailbell targets macOS 26 or later on Apple silicon, because every Swift app of
the owner targets the current major macOS (owner decision, 2026-09-17, recorded
on #44). It uses public stable Apple APIs, stores tokens only in Keychain, and
distributes through signed and notarized direct downloads with Sparkle updates.
The Google OAuth client remains unverified; public copy must disclose its
warning screen and new-user cap.

The canonical website is [mailbell.martonpaulo.com](https://mailbell.martonpaulo.com/).
Engineering contracts live in [architecture.md](architecture.md), interface
rules in [interface.md](interface.md), and defaults in
[feature-defaults.md](feature-defaults.md). This document does not resolve
pending product decisions or replace issue acceptance criteria.

## Decision index

One row per consequential decision. Each row points to the canonical rule and
does not restate it.

| Decision | Outcome | Canonical document | Deciding source |
| --- | --- | --- | --- |
| Landing page host | `mailbell.martonpaulo.com`, with no redirect from `martonpaulo.com/mailbell/` | [AGENTS.md](../AGENTS.md), "Landing page" | Owner, 2026-09-09 |
| Queue limits | 500 retained messages and 50 visible conversations per account; not configurable | [feature-defaults.md](feature-defaults.md#queue-limits) | [#27](https://github.com/martonpaulo/mailbell/issues/27) |
| Queue order | Newest server receipt first | [architecture.md](architecture.md#service), "Queue order" | [#11](https://github.com/martonpaulo/mailbell/issues/11) |
| Thread members during a read action | Only the members fixed before the request are finalized | [architecture.md](architecture.md#reliability-contracts) | [#22](https://github.com/martonpaulo/mailbell/issues/22) |
| System Settings action labels | A label names what the action actually opens | [interface.md](interface.md#settings) | [#31](https://github.com/martonpaulo/mailbell/issues/31) |
| Platform floor | macOS 26 or later, Apple silicon | [product.md](#success-and-constraints) | [#44](https://github.com/martonpaulo/mailbell/issues/44) (owner, 2026-09-17) |
| Package layout | Pure logic in a `MailbellKit` library target | [AGENTS.md](../AGENTS.md), "Architecture" | [#44](https://github.com/martonpaulo/mailbell/issues/44) |
| Where UI text lives | One English-only String Catalog; no locale added | [AGENTS.md](../AGENTS.md), "Product copy" | [#44](https://github.com/martonpaulo/mailbell/issues/44), [#61](https://github.com/martonpaulo/mailbell/issues/61) |
| Settings panes | Three panes: General, Accounts, About; updates and the automatic-updates toggle in About | [interface.md](interface.md#settings) | [#54](https://github.com/martonpaulo/mailbell/issues/54) |
| Restore Defaults scope | Each pane resets only its own preferences | [feature-defaults.md](feature-defaults.md#rules) | [#54](https://github.com/martonpaulo/mailbell/issues/54) |
| Menu bar glyph precedence | Account problems, then a denied notification permission, then unread mail | [interface.md](interface.md#menu-bar-glyph) | [#54](https://github.com/martonpaulo/mailbell/issues/54) |
| Accent colour | The system accent; amber only in the icon, the glyph and the site | [interface.md](interface.md#app-shape) | [#54](https://github.com/martonpaulo/mailbell/issues/54) |
| Title case and sentence case | Title Case for pane names, buttons and menu commands only | [interface.md](interface.md#copy) | [#54](https://github.com/martonpaulo/mailbell/issues/54) |
| Ellipsis | Only when more input or a confirmation follows | [interface.md](interface.md#copy) | [#61](https://github.com/martonpaulo/mailbell/issues/61) |
| App credit | Two credit lines in `NSHumanReadableCopyright`; `LICENSE` and `NOTICE.md` unchanged | [AGENTS.md](../AGENTS.md), "Copyright" | [#73](https://github.com/martonpaulo/mailbell/issues/73) |
| Bundle identifier | `com.martonpaulo.mailbell` from v0.4.0; preferences copied once, Keychain tokens not migrated | [AGENTS.md](../AGENTS.md), "Public identifiers" | [#47](https://github.com/martonpaulo/mailbell/issues/47) |
| README drift | Tracked in its own issue, apart from baseline alignment | [README.md](../README.md) | [#55](https://github.com/martonpaulo/mailbell/issues/55) |

## Accepted evidence gaps

- Manual screen-reader passes: not run; accepted by the owner
  (martonpaulo/skill-deck#266). Accessibility evidence is automated.
- The macOS 26 `notFound` login-item status was observed in WindowHop, not
  reproduced in an installed Mailbell
  ([#49](https://github.com/martonpaulo/mailbell/issues/49)).
