# Mailbell

<p align="center">
  <img src="Resources/logo.png" alt="Mailbell logo" width="128">
</p>

<p align="center">
  <a href="https://github.com/samzong/mailbell/releases/latest">
    <img src="https://img.shields.io/badge/Download%20Latest%20Release-28a745?style=for-the-badge&labelColor=28a745" alt="Download latest release">
  </a>
</p>

<p align="center">
  Minimal macOS menu bar notifier for Gmail.
</p>

<p align="center">
  <a href="https://github.com/samzong/mailbell/releases"><img src="https://img.shields.io/github/v/release/samzong/mailbell" alt="Release"></a>
  <a href="https://github.com/samzong/mailbell/blob/main/LICENSE"><img src="https://img.shields.io/github/license/samzong/mailbell" alt="License"></a>
</p>

Mailbell is a **local notification bridge**, not an email client. It signs in with Google, keeps a lightweight Gmail IMAP IDLE connection on your Mac, shows native notifications for new inbox mail, and opens Gmail in your browser when you want to read.

## Features

- Menu bar status for one or more Gmail accounts
- Near-instant new-mail alerts via IMAP IDLE (no content polling loop)
- Native macOS notifications with sender and subject (headers only)
- Opens Gmail Web in your chosen browser when you click a notification
- OAuth tokens stored in the macOS Keychain on your machine
- No cloud relay service; mail data stays between your Mac and Google

## Requirements

- macOS 13 (Ventura) or newer
- A Google Cloud OAuth client (Desktop app type)

## Install

Download the latest `Mailbell-arm64.dmg` from [Releases](https://github.com/samzong/mailbell/releases), drag Mailbell into Applications, then open it from the menu bar.

> **First launch:** If macOS shows a security warning for a downloaded build, right-click the app, choose **Open**, or run:
>
> `xattr -dr com.apple.quarantine /Applications/Mailbell.app`

Build from source: see the [GitHub repository](https://github.com/samzong/mailbell#build-and-run).

## Google OAuth setup

Mailbell uses a **Desktop** OAuth client with PKCE. In Google Cloud Console:

1. Configure the OAuth consent screen (**In production** for personal use avoids 7-day refresh-token expiry).
2. Add scope `https://mail.google.com/` (plus `openid` and `email`).
3. Create an OAuth client ID of type **Desktop app**.
4. In Mailbell **Settings**, paste the Client ID and secret, save, then **Sign in with Google**.

For OAuth application domain fields, use this site:

| Field | URL |
| --- | --- |
| Application home page | https://mailbell.samzong.me/ |
| Privacy policy | https://mailbell.samzong.me/privacy.html |
| Terms of service | https://mailbell.samzong.me/terms.html |

## What Mailbell does not do

- No mailbox UI, message body viewer, or compose/reply/archive flows
- No third-party server that stores your mail or tokens
- No replacement for Gmail Web for reading and managing mail

## Source and license

- Source: [github.com/samzong/mailbell](https://github.com/samzong/mailbell)
- License: [MIT](https://github.com/samzong/mailbell/blob/main/LICENSE)