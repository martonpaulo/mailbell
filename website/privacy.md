# Privacy Policy

**Last updated:** June 4, 2026

Mailbell ("the app") is a macOS menu bar application published by [samzong](https://github.com/samzong). This policy describes what data the app handles and how.

## Summary

Mailbell runs on your Mac. It connects directly to Google (OAuth and Gmail IMAP) to detect new inbox mail and show local notifications. The app does not operate a separate cloud service that stores your email, credentials, or notification history.

## Data the app processes

### On your Mac (local only)

- **OAuth tokens** (access and refresh tokens) and optional **OAuth client secret** — stored in the macOS Keychain
- **Account email addresses**, connection/checkpoint state, and non-secret UI preferences — stored in app preferences (`UserDefaults`)
- **Message headers** used for notifications: sender, subject, date, and identifiers needed to open the thread in Gmail Web — fetched over IMAP when new mail arrives; not written to a remote Mailbell server

### Sent to Google (by design)

- OAuth sign-in and token refresh (Google identity and token endpoints)
- IMAP over TLS to `imap.gmail.com` using XOAUTH2, scoped as `https://mail.google.com/`

Google processes this data under [Google's Privacy Policy](https://policies.google.com/privacy). Mailbell does not control Google's retention or use of data on their systems.

### Not collected by Mailbell

- No Mailbell-operated account database or analytics backend
- No sale of personal data
- No upload of full message bodies or attachments for notifications (headers only)
- No logging of OAuth codes, refresh tokens, client secrets, or raw message bodies in app logs

## Notifications

macOS delivers notifications through **User Notifications** on your device. Notification content (sender and subject) is shown according to your system notification settings. Mailbell does not send notification payloads to a third-party push provider.

## Third parties

- **Google** — authentication and Gmail IMAP
- **GitHub** (optional) — if you download releases or view this website; governed by GitHub's policies

There is no default integration that shares your mail content with other third parties.

## Your choices

- **Sign in / sign out** — disconnecting removes stored tokens for that account from the Keychain (per app behavior)
- **Revoke access** — you can revoke the app's Google access in your [Google Account security settings](https://myaccount.google.com/permissions)
- **Uninstall** — remove the app from Applications; remove Keychain items and preferences if you want to clear local state

## Children

Mailbell is not directed at children under 13, and we do not knowingly collect personal information from children.

## Changes

We may update this policy when the app's data practices change. The "Last updated" date at the top will change accordingly. Continued use after an update means you accept the revised policy.

## Contact

Questions about this policy: open an issue at [github.com/samzong/mailbell](https://github.com/samzong/mailbell/issues).