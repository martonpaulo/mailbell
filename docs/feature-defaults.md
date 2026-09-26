# Feature defaults and configurability

Every user-facing behavior declares a default and a configurability decision.
A missing decision is a review failure.

## Rules

- Defaults live in one place: the centralized settings defaults. Views,
  services, tests, and migrations never restate a fallback value.
- Decide whether each behavior is user-configurable and record why here.
- Prefer a setting when both states are legitimate user preferences.
- Do **not** add a setting for a bug fix, a security behavior, an internal
  implementation detail, mandatory accessibility behavior, or anything with only
  one valid outcome.
- Persist configurable preferences through the typed settings layer, which is
  the runtime source of truth.
- Every configurable preference is registered so Restore Defaults resets it.
- Each Settings pane resets only its own preferences, from its last section.
  Decided on #54, which supersedes the single Restore Defaults for every pane;
  #74 implements it.
- Reset never touches accounts, Keychain tokens, notification permission, the
  login item, IMAP checkpoints, or handled-message history.
- Preserve existing user choices on upgrade; migrate a stored value only when the
  old representation is invalid. `LegacyDomainMigration` is the only copy
  across defaults domains: on the first launch under the 0.4.0 bundle
  identifier it copies Mailbell's own names once and never overwrites a stored
  value (Decided on #47).

## Queue limits

The owner delegated the retention decision on 2026-09-09. Decided on #27;
`PendingQueueBudget` implements it. Capacity eviction is not a handled
disposition: Gmail remains authoritative, and retained membership and the
visible menu projection have one owner each in `EmailStore`.

| Boundary | Approved value | Configurable | Reason |
|---|---|---|---|
| Retained message records | **500 per account**, shared by Inbox and optional Spam | No | Bound local mail state without making one busy account evict another account's items. |
| Visible conversation rows | **50 per account** | No | Keep the native menu bounded; additional retained conversations remain part of the queue. |

Retained messages and visible conversations are different units. All retained
message identities count toward the message budget, including members of one
long conversation. The visible-row limit is a projection of that one store,
not a second queue. Total allowance scales with the connected accounts.

Prefer recent conversations using the server-receipt chronology approved in
issue #11. Preserve the first-admitted representative while its conversation is
retained. At capacity, release older non-representative context from the
least-recent conversation first; remove its row only when its representative is
its sole remaining record. A single oversized conversation retains its
representative and recent context within the same account budget.

Capacity eviction releases reconstructible local data only. It never marks mail
read, deletes mail, or records an explicit dismissal. Do not create a persistent
overflow list, another content cache, or an unbounded shadow identity index.
Fresh-mail notifications and successful-batch checkpoint guarantees continue
independently of whether a message can stay in the retained window.

Show the retained/shown scope and an account-specific overflow notice with an
Open Gmail action; do not invent a total count of unknown Gmail mail. Existing
Check Now explicitly refills the recent window in bounded batches, and relaunch
rebuilds it from Gmail and existing handled history. Do not automatically refill
older capacity-excluded mail just because an action freed space: clearing the
queue must not immediately reveal another historical window. Fresh arrivals
and read-state reconciliation continue through existing IDLE handling.

Bulk actions use a stable snapshot of **all retained messages**, including those
outside the visible rows, and disclose their retained-message count before
activation. They never reach capacity-excluded Gmail messages. Conversation
actions likewise affect only captured retained members, preserving issue #22's
late-arrival protections. Explicit dismissals remain suppressed while their
bounded history records exist; eviction is never treated as dismissal.

These are product budgets, not benchmark-derived performance guarantees. They
live once in `PendingQueueBudget` and are deliberately not preferences: there is
no legitimate second answer for a user to choose, so they carry no settings key
and no Restore Defaults entry.

## Current defaults

| Behavior | Default | Configurable | Notes |
|---|---|---|---|
| Show review count in the menu bar | **on** | Yes — General | Hiding it keeps the glyph alone |
| Play notification sounds | **on** | Yes — General (Decided on #54) | Turning it off keeps notifications and the review queue visual-only |
| Start at login | **off** | Yes — General | Real system state, read back from the login item |
| Include Spam | **off** | Yes — Accounts | Turning it off also removes pending Spam items |
| Webmail routing | System default browser | Yes — Accounts, per account | Chrome profiles are offered when present |
| Automatic update checks | **on** | Yes — About (Decided on #54) | Inert in development builds |

## Deliberately not configurable

| Behavior | Why |
|---|---|
| Menu bar alert icon when sign-in is needed | Single valid outcome. An app that silently looks idle while monitoring nothing is a defect, not a preference. |
| Notification when sign-in expires | Same rule as the alert icon, for a user who is not looking at the menu bar. It fires once per expiry, and only for an enabled account. |
| Threads counting once in the menu | Product rule, not taste. Notifications remain per message. |
| Preview length and `BODY.PEEK` bounds | Privacy and data-minimization contract. Not user-tunable. |
| Accessory (no Dock icon) style | Defines what Mailbell is. |
| Dismiss All leaving Gmail untouched | Dismiss is explicitly local; a variant that also mutates Gmail is Mark All as Read. |
| Sparkle signature verification | Security behavior. |

## When adding a behavior

1. Add the default to the centralized defaults.
2. Register the key as configurable if it is a preference.
3. Add or update coverage for default, persistence, and reset.
4. Update the table above.
