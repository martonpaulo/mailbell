# Security Policy

## Reporting a vulnerability

Please report security issues privately through
[GitHub Security Advisories](https://github.com/martonpaulo/mailbell/security/advisories/new)
rather than a public issue.

Include what you found, how to reproduce it, and the Mailbell version from
Settings → Updates. Please do not include real tokens, OAuth codes, or email
content in the report.

## Scope

Mailbell runs entirely on the user's Mac. There is no Mailbell server, so there
is no hosted attack surface to report. Relevant areas are:

- The OAuth desktop flow, PKCE handling, and the local loopback redirect server.
- Keychain storage of refresh and access tokens.
- The IMAP client, including TLS handling and the XOAUTH2 exchange.
- Body-preview sanitizing, which processes untrusted remote HTML.
- Sparkle update verification and the release signing chain.

## What Mailbell guarantees

- Tokens live in the macOS Keychain and nowhere else.
- Only bounded, non-mutating previews are fetched. Attachments and full message
  bodies are never requested.
- Tokens, OAuth codes, client secrets, IMAP auth payloads, and raw message
  bodies are never logged.
- Official releases are signed with a stable Developer ID Application identity,
  notarized by Apple, and stapled. Sparkle verifies the EdDSA signature and the
  Apple code signature before replacing the app.
- The Sparkle private key lives in a login Keychain and is never committed.

## Current status

Mailbell's Google OAuth client is **not yet verified by Google**. During sign-in
Google shows an "unverified app" screen, and Google caps unverified clients at
100 new users. This is a review status, not a compromise: the app still runs
locally and no Gmail data passes through any server operated by this project.
See the [Privacy Policy](https://martonpaulo.github.io/mailbell/privacy.html).
