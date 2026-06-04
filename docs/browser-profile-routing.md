# Browser and Profile Routing Design

Status: implemented with known limitations

## Summary

Mailbell supports per-account Webmail opening preferences:

- default: open Gmail with the system default browser, preserving current behavior
- per account: open Gmail with a selected browser installed on this Mac
- Chrome-first: when Google Chrome is selected, optionally select a Chrome profile directory

This is valuable for multi-account Gmail users because Mailbell can notify for account A while the default browser session is signed in to account B. Account-directed browser/profile routing keeps the notification-to-reading path aligned without turning Mailbell into an email client.

## Current Behavior

The current implementation stores an optional Webmail opening preference on each `MailAccount`:

- `nil` preference means system default browser.
- `.application(bundleIdentifier:appPath:)` stores the selected browser bundle identifier and its current app path.
- `chromeProfileDirectory` stores an optional Chrome profile directory name such as `Default` or `Profile 2`.
- `GmailProvider.webmailURL` remains `https://mail.google.com/`; notification URLs use Gmail thread links when IMAP provides `X-GM-THRID`.
- Notification payloads include both `webmailURL` and `accountID`.
- Notification clicks route through the account-aware Webmail opener when the app can resolve the account.
- If account lookup fails, old notifications still fall back to the stored `webmailURL`.

Known limitation: the opener currently trusts the stored `appPath`. If the selected browser is moved or reinstalled at a new path while keeping the same bundle identifier, Settings may still rediscover it by bundle identifier but opening can fall back to the system default browser until the user saves the preference again.

## Goals

- Let each `MailAccount` choose how Gmail opens.
- Preserve the current default behavior for existing accounts.
- Prefer native macOS browser discovery and opening for generic browser routing.
- Add first-class support for Google Chrome profiles.
- Keep settings small and account-scoped.
- Keep notification content and mail transport unchanged.
- Fall back safely when the configured browser/profile is missing.

## Non-Goals

- No mailbox UI, message reading, reply, archive, label, or compose flow.
- No browser cookie inspection.
- No attempt to infer which browser profile is signed in to which Gmail account.
- No Gmail `authuser` routing in v1.
- No Safari profile support in v1.
- No Arc Space/Profile support in v1.
- No custom user-data-dir creation or profile management.
- No deep links to a specific message inside a Gmail thread in v1.

## Platform Findings

### Generic Browser Routing

macOS LaunchServices can find apps that can open a URL and can open URLs with a specific application path. This is the right base for "open Gmail with Safari / Chrome / Arc / another browser".

Relevant APIs:

- `NSWorkspace.urlsForApplications(toOpen:)`
- `NSWorkspace.open(_:withApplicationAt:configuration:completionHandler:)`
- `NSWorkspace.OpenConfiguration`

Source: Apple Developer Documentation for `NSWorkspace.open(_:withApplicationAt:configuration:completionHandler:)`.

### Chrome Profile Routing

Chrome profiles live under the Chrome user data directory. On macOS, Chromium documents the default Chrome user data directory as:

```text
~/Library/Application Support/Google/Chrome
```

Each profile is a subdirectory of that user data directory, commonly `Default`, `Profile 1`, `Profile 2`, and so on. Chrome also has a top-level `Local State` JSON file with `profile.info_cache`, which contains profile display metadata such as profile name and account username.

Source: Chromium `docs/user_data_dir.md`.

Chrome can be launched with command-line profile selection:

```text
--profile-directory=<profile directory>
```

This is browser-specific behavior. It should not be generalized to all browsers.

## Implemented Model

`MailAccount` has an optional Webmail opening preference.

Implemented shape:

```swift
struct WebmailOpenPreference: Codable, Equatable {
    var browser: BrowserSelection
    var chromeProfileDirectory: String?
}

enum BrowserSelection: Codable, Equatable {
    case systemDefault
    case application(bundleIdentifier: String, appPath: String)
}
```

Implementation notes:

- `nil` preference must mean current behavior: system default browser.
- Store preferences in `UserDefaults` with the existing account metadata.
- Do not store anything in Keychain; browser/profile choices are not secrets.
- The bundle identifier is used to match saved preferences against rediscovered browser candidates in Settings.
- The opener currently uses the stored app path to launch the selected browser.
- Secure-scoped bookmarks are not used. Add them only if sandboxing is introduced.

## Browser Discovery

`BrowserRegistry` provides browser discovery:

- Input: `https://mail.google.com/`
- Output: sorted browser candidates
- Candidate fields:
  - display name
  - bundle identifier
  - app URL
  - capability flags, such as `supportsChromeProfiles`

Discovery rules:

- Use `NSWorkspace.shared.urlsForApplications(toOpen:)` for generic candidates.
- Filter candidates with a browser bundle identifier allowlist.
- Always include `System Default` as the first option.
- Detect Google Chrome by bundle id `com.google.Chrome`.
- Only `com.google.Chrome` currently gets Chrome profile controls.

Do not hardcode only `/Applications`. Users may install browsers under `~/Applications`.

## Chrome Profile Discovery

`ChromeProfileStore` provides Chrome profile discovery:

- Locate `~/Library/Application Support/Google/Chrome/Local State`.
- Parse JSON field `profile.info_cache`.
- Expose profile candidates:
  - directory name: `Default`, `Profile 2`, etc.
  - display name: `name`
  - optional signed-in username: `user_name`
- Exclude obvious non-user profiles:
  - `Guest Profile`
  - `System Profile`

The directory name is the stable launch value. Display names are UI labels only and may change.

Failure behavior:

- If `Local State` is missing or unreadable, show only `Default (no explicit profile)` and allow Chrome without an explicit profile.
- If a saved profile directory is not found in `Local State`, keep it selectable as a missing option and show a warning on that account.
- When opening with a missing saved profile directory, fall back to opening Chrome without `--profile-directory`; if the selected browser app is missing or cannot open, fall back to the system default browser.

## Opening Strategy

`WebmailOpener` owns browser/profile opening.

Inputs:

- `MailAccount`
- provider `webmailURL`
- account `WebmailOpenPreference?`

Cases:

1. No preference or `systemDefault`
   - Use `NSWorkspace.shared.open(url)`.

2. Non-Chrome browser app selected
   - Use `NSWorkspace.open([url], withApplicationAt: appURL, configuration: .init())`.
   - If opening fails, fall back to `NSWorkspace.shared.open(url)` and surface an account-level warning.

3. Google Chrome selected without profile
   - Prefer `NSWorkspace.open([url], withApplicationAt: chromeAppURL, configuration: .init())`.
   - Fall back to system default on failure.

4. Google Chrome selected with profile
   - Verify the profile directory still exists under the Chrome user data directory.
   - Launch Chrome's executable directly with:

```text
--profile-directory=<saved profile directory>
https://mail.google.com/
```

The executable path is derived from the selected app path:

```text
Google Chrome.app/Contents/MacOS/Google Chrome
```

and launched with `Process`.

## Notification Flow

Keep notification payloads account-aware:

- Continue writing `accountID` into `UNNotificationContent.userInfo`.
- On notification click, resolve `accountID` to the current `MailAccount`.
- Ask `WebmailOpener` to open the provider URL with that account's preference.
- If account lookup fails, use the existing `webmailURL` fallback.

This keeps old notifications safe after account removal or settings changes.

## Settings UI

Keep settings inside the existing `Accounts` tab. Do not add a separate browser tab for v1.

For each account row, add compact controls:

- `Open with`: `System Default`, plus installed browser candidates
- If selected browser is Google Chrome:
  - `Chrome profile`: `Default` or discovered profile choices
- `Open Gmail` button for manual verification

UI rules:

- Existing accounts should show `System Default` until changed.
- Chrome profile picker appears only for Chrome.
- Missing saved browser/profile should show a small account-level warning.
- The profile picker always includes `Default (no explicit profile)` before discovered profile directories.
- Avoid exposing raw filesystem paths unless needed for debugging.

## Error Handling

Opening failures should not affect IMAP connection status. They are account-level Webmail opening errors.

Recommended error text examples:

- `Selected browser is no longer available.`
- `Selected Chrome profile is no longer available.`
- `Could not open Gmail with the selected browser.`

Errors should clear after a successful open or after the user changes the preference.

## Product Value

This feature is worth doing if Mailbell is used with more than one Gmail account.

Without it:

- notification account and browser session can diverge
- clicking a notification can open the wrong inbox
- users must manually switch Gmail accounts or browser profiles
- multi-account support feels incomplete even though monitoring works

With it:

- each account can open into its intended browser session
- Mailbell stays a notification bridge
- no email-client scope is added
- no additional Google API or OAuth scope is needed

For single-account users, the default remains system browser behavior unless they change the account's Webmail preference.

## Impact

Touched areas:

- `Sources/Mailbell/Account/MailAccount.swift`
- `Sources/Mailbell/App/AppState.swift`
- `Sources/Mailbell/App/MailbellApp.swift`
- `Sources/Mailbell/Notify/NotificationManager.swift`
- `Sources/Mailbell/Service/AccountSupervisor.swift`
- service files for browser discovery, Chrome profile discovery, preferences, and opening
- tests for account decoding, browser preference generation, missing picker options, and Chrome profile parsing

No expected changes:

- OAuth scopes
- token storage
- IMAP transport
- notification header fetching
- Keychain model

Risk:

- Chrome profile opening may behave differently when Chrome is already running.
- Browser discovery is intentionally allowlisted and may omit a browser until its bundle identifier is added.
- Saved app paths may become stale after app deletion or move.
- Chrome `Local State` is browser-private data and may change format.

## Verification Plan

Automated:

- old `MailAccount` JSON decodes with `webmailOpenPreference == nil`
- account coding preserves browser preference
- Chrome `Local State` fixture parses profile directory, display name, and username
- guest/system profiles are excluded
- browser preference generation clears Chrome profile values for non-Chrome browsers
- missing saved browser/profile options stay visible in Settings picker data

Not yet automated:

- `WebmailOpener` system default, selected app, Chrome profile, and fallback paths
- notification click end-to-end routing through `UNUserNotificationCenter`

Manual on macOS:

- default behavior opens Gmail in the system default browser
- selecting Safari opens Gmail in Safari
- selecting Google Chrome without profile opens Gmail in Chrome
- selecting Chrome `Default` opens Gmail in that profile
- selecting Chrome `Profile 2` opens Gmail in that profile
- deleting or renaming the selected Chrome profile shows an account warning and falls back safely
- notification click uses the account's configured browser/profile
- `Open Gmail` account action uses the same account browser/profile preference with the generic Gmail URL

Gate:

```bash
make check
```

For notification click behavior, verify with a bundled app, not only `swift run`.

## Rollout Plan

1. Add data model and decoding compatibility.
2. Add browser discovery and Chrome profile parsing services.
3. Add `WebmailOpener` with fallback behavior.
4. Route notification clicks through `accountID` lookup.
5. Add per-account Settings controls and manual `Open Gmail`.
6. Add tests and manual verification notes.

## Deferred Work

- Resolve selected browser app moves/reinstalls by bundle identifier before falling back to the system default browser.
- Gmail `authuser` URL support.
- Gmail message-level deep links inside a thread.
- Safari profile support.
- Arc Space/Profile support.
- Brave, Edge, and Chrome channel profile support.
- Importing/matching Gmail account emails to Chrome profile usernames.
- Custom browser command templates.

Do not implement deferred work until there is concrete user demand. The v1 feature should solve the common Chrome multi-profile case without becoming a browser automation layer.
