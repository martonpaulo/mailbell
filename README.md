# mailbell

<p align="center">
  <img src="Resources/logo.png" alt="Mailbell logo" width="128">
</p>

Minimal macOS menu bar notifier for Gmail.

The project goal is a local notification bridge, not an email client. The app authenticates with Google, keeps a lightweight Gmail IMAP IDLE connection alive (a performance-first, low-energy push transport), shows macOS notifications for new mail, and opens Gmail in the browser when the user wants to read.

See [docs/design.md](docs/design.md) for the full design.

## Requirements

- macOS 13 (Ventura) or newer.
- A Google Cloud OAuth client (Desktop app type). See "Google setup" below.

No Apple Developer account is needed: builds are ad-hoc signed for local use. An app you build and install locally is not quarantined, so Gatekeeper will not block it (only matters if you copy the DMG to another Mac).

## Google setup

1. In the Google Cloud Console, create a project and enable the OAuth consent screen.
2. Set the consent screen to **In production** (publishing status). For personal use you can leave it **Unverified** — this avoids the 7-day refresh-token expiry without needing CASA verification. If you own a Workspace org, set the user type to **Internal** instead.
3. Add the scope `https://mail.google.com/` (plus `openid` and `email`).
4. Create an OAuth client ID of type **Desktop app**. Note the client ID (and the non-secret client secret it gives you).
5. Provide them to the app one of two ways:
   - **In the app (recommended):** open the menu → `Settings…` → "Google OAuth client", paste the Client ID and secret, click `Save client`, then `Sign in with Google`. The client ID is stored in app preferences and the secret in the Keychain.
   - **Environment variables (for `swift run` from a terminal only):** GUI apps launched from Finder do not inherit these.

```bash
export MAILBELL_CLIENT_ID="xxxx.apps.googleusercontent.com"
export MAILBELL_CLIENT_SECRET="yyyy"   # Google issues one for desktop clients; it is not treated as confidential
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

## Release

Releases are tag-driven. Push a version tag and GitHub Actions will build, verify, and publish the DMG:

```bash
git tag v0.1.0
git push origin v0.1.0
```

## License

MIT
