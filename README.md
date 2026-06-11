# mailbell

<p align="center">
  <img src="Resources/logo.png" alt="Mailbell logo" width="128">
</p>

Minimal macOS menu bar notifier for Gmail.

The project goal is a local notification bridge, not an email client. The app authenticates with Google, keeps a lightweight Gmail IMAP IDLE connection alive (a performance-first, low-energy push transport), shows macOS notifications for new mail, and opens Gmail in the browser when the user wants to read.

See [docs/design.md](docs/design.md) for the full design.

## Requirements

- macOS 13 (Ventura) or newer.

No Apple Developer account is needed: builds are ad-hoc signed for local use. An app you build and install locally is not quarantined, so Gatekeeper will not block it (only matters if you copy the DMG to another Mac).

## Google sign-in

Mailbell does not ship a shared Google OAuth client. Create your own Google OAuth client for local use, provide its values through environment variables or a local `.env`, then build or install the app.

The app requests `https://mail.google.com/`, `openid`, and `email`. The broad Gmail scope is required for Gmail IMAP XOAUTH2; Mailbell still fetches only headers for notifications. For personal-use OAuth projects, Google may show an unverified-app warning during sign-in.

Set the OAuth values in the shell environment or create `.env` from `.env.example` before running `make run`, `make install`, or `make dmg`. `make install` and `make dmg` fail before packaging if the values are missing or malformed.

Expected local variables:

```bash
MAILBELL_GOOGLE_CLIENT_ID=
MAILBELL_GOOGLE_CLIENT_SECRET=
```

## Build and run

```bash
make            # list targets
make build      # build debug
make run        # run unbundled (menu bar app; notifications need a bundle)

# Install an ad-hoc signed app bundle to /Applications (enables notifications):
make install
open /Applications/Mailbell.app

# Or build a DMG:
make dmg
```

`./Scripts/package_app.sh` builds a local `build/Mailbell.app` without installing, if you prefer.

Tokens are stored in the macOS Keychain. Use the menu's `Disconnect` to remove them.

## License

MIT
