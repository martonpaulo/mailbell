# Interface rules

Rules for Mailbell's menu bar surface and Settings. Every visual constant comes
from design tokens ([AGENTS.md](../AGENTS.md), "Mailbell rules"). Defaults,
configurability and Restore Defaults belong to
[feature-defaults.md](feature-defaults.md).

## App shape

- Keep the app accessory-style and out of the Dock.
- The app keeps the system accent colour. It ships no `AccentColor` set, and
  views use `Color.accentColor`. Mailbell's amber lives in the app icon, the
  bell glyph and the site: macOS applies an app accent only while the user's
  system accent is Multicolor, and the native menu highlight always follows the
  system. Decided on #54.

## Menu bar glyph

The menu bar glyph has one owner and one precedence. An account needing the
user (sign-in expired, surfaced error) outranks a denied notification
permission, which outranks unread mail. The alert symbol replaces the bell, so
the app never looks idle while nothing is monitored or no alert can get through.
Decided on #54 (the denied-permission level; #72 implements it).

## Settings

- Settings stays small and native: three panes, each owning one question.
  Decided on #54, which supersedes the earlier four-pane rule; #68, #73 and #74
  implement it.
  - **General**: how Mailbell presents itself and whether alerts get through
    (menu bar, startup, notification permission and sounds).
  - **Accounts**: which mailboxes are watched, and everything about each
    account.
  - **About**: what it is and how it is updated (version, build and release
    date, the automatic-updates toggle, Check for Updates…, Report an Issue…,
    project links).
- Never split one entity across panes: an account's status, routing, and removal
  belong together.
- **Controls carry meaning; pick the right one.** These follow what macOS
  System Settings actually does, not invention:
  - `Toggle` for a binary preference, labelled with a **stable description of
    the enabled state**. A label that inverts with its own value
    ("Disable Account") reads as its own opposite and is a defect.
  - **Explanation belongs in the row, under its own label** (`SettingsRow` and
    `SettingsToggleRow`), the way System Settings explains FileVault, AirDrop,
    and AirPlay Receiver. A section `footer` is for text about the group as a
    whole.
  - `LabeledContent` / `SettingsRow` for **label to value** — status, counts,
    versions — or label to a row-scoped control. A label that merely restates
    its button ("Remove Account: Remove") is banned.
  - **Action placement follows the action's scope**, and every action goes
    through `SettingsActionRow` so alignment has one definition:
    - *row-scoped* → in that row, trailing (System Settings: "Siri history"
      `Delete Siri & Dictation History…`, "Recovery Key" `Show`);
    - *section-scoped* → inside the box, as its own last row, trailing
      (`Add User…`, `About AirDrop & Privacy…`);
    - *pane-scoped* → below every box, trailing, in the last section's footer
      (`Advanced…` in Privacy & Security).
  - Buttons are sized to their content and trailing-aligned. Leading-aligned,
    full-width buttons are not the platform convention.
  - A control that opens System Settings names what it actually opens; it names
    a pane only when a documented public API opens that pane. Decided on #31.
  - Destructive actions use `role: .destructive`, never a hand-applied red, and
    anything irreversible confirms first.
  - A status row earns its space only when it can disagree with the control
    above it; otherwise it is noise.

  These rules are enforced by `scripts/validate.sh` source-shape invariants.
- Preserve native controls, keyboard navigation, focus, hover/pressed/disabled/
  loading/error states, Dynamic Type, contrast, validation feedback, and safe
  areas.
- Before UI edits, briefly critique the current UI, then plan layout, controls,
  states, accessibility, and verification.

## Copy

- Keep user-facing copy concise and consistent with nearby product language.
- Title Case only for pane names, buttons and menu commands; sentence case for
  toggles, row labels, section headers, status values and footers. Decided on
  #54.
- Ellipsis, as the HIG separates it:
  - a **push button** that opens another window, sheet or app, or a
    confirmation, ends with `…` ("Open Login Items Settings…", "Check for
    Updates…", "Details…", "Manage Google Access…", "Open Gmail…", "Restore
    Defaults…"); the confirm button drops it;
  - a **menu item** ends with `…` only when it needs more input before it acts
    ("Settings…" by convention, "Mark All as Read in Gmail…" while a
    confirmation follows); "Open in Gmail" has none;
  - a **text link** never has one ("Website", "GitHub").
  Decided on #61 (corrected by the owner on 2026-09-26 after the first rule
  misread the HIG).
