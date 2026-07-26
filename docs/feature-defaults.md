# Feature defaults and configurability

Every user-facing behavior declares a default and a configurability decision.
A missing decision is a review failure.

## Rules

- Defaults live in one place: the centralized settings defaults. Views,
  services, tests, and migrations never restate a fallback value.
- Prefer a setting when both states are legitimate user preferences.
- Do **not** add a setting for a bug fix, a security behavior, an internal
  implementation detail, mandatory accessibility behavior, or anything with only
  one valid outcome.
- Every configurable preference is registered so Restore Defaults resets it.
- Reset never touches accounts, Keychain tokens, notification permission, the
  login item, IMAP checkpoints, or handled-message history.
- Preserve existing user choices on upgrade; migrate a stored value only when the
  old representation is invalid.

## Current defaults

| Behavior | Default | Configurable | Notes |
|---|---|---|---|
| Show review count in the menu bar | **on** | Yes — General | Hiding it keeps the glyph alone |
| Start at login | **off** | Yes — General | Real system state, read back from the login item |
| Include Spam | **off** | Yes — Advanced | Turning it off also removes pending Spam items |
| Webmail routing | System default browser | Yes — Advanced, per account | Chrome profiles are offered when present |
| Automatic update checks | **on** | Yes — Updates | Inert in development builds |

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
