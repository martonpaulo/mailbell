# Contributing

Thanks for looking. Mailbell is a small, deliberately narrow macOS menu bar app,
and keeping it small is a feature.

## Before you start

Read [AGENTS.md](AGENTS.md). It is the durable policy for how this project is
built: identity, release policy, the process rules, and the pattern-break
protocol. It links to the product boundary in [docs/product.md](docs/product.md),
the OAuth, privacy and reliability contracts in
[docs/architecture.md](docs/architecture.md), and the UI rules in
[docs/interface.md](docs/interface.md). It applies to humans and coding agents
alike.

## Build and check

Requires macOS 26+ and a current Xcode toolchain.

```sh
make check
```

That runs the debug build (must be warning-free), SwiftLint, the tests, and
`scripts/validate.sh` repository invariants.

To exercise notifications you need a real bundle, because macOS will not deliver
notifications to an unbundled binary:

```sh
make install
```

You will need your own Google Desktop OAuth client in `.env` to run a local
build. Copy `.env.example` and fill in `MAILBELL_GOOGLE_CLIENT_ID`. Released
builds ship the project's own client; local builds do not.

## Out of scope

Please open an issue before building any of these, because the answer is usually
no:

- Reading full message bodies, attachments, reply, compose, archive, delete,
  labels, or move.
- Any backend, relay, sync service, or hosted component.
- Analytics, telemetry, crash reporting, or advertising.
- Providers other than Gmail, unless the whole provider abstraction is designed
  first.
- Content polling as the new-mail mechanism. IMAP IDLE is the transport.

## Pull requests

- Conventional Commits, English everywhere. A commit made for an issue ends its subject with
  `(#<issue number>)`.
- Work on `main` unless a branch was requested; keep each commit to one concern.
- Business-rule changes come with tests.
- Every user-facing behavior declares its default and configurability decision
  (see [docs/feature-defaults.md](docs/feature-defaults.md)).
- New preferences use the centralized defaults, preserve existing values, and are
  covered by Restore Defaults.
- No private Apple APIs, no new dependencies, no polling while idle.
- Never commit `.env`, credentials, tokens, or signing material.
- Sign local builds with a stable identity: set `DEVELOPER_ID_IDENTITY` in `.env` to an identity from `security find-identity -v -p codesigning`. macOS ties Keychain items and the notification and login-item permissions to the code signature, and an ad-hoc signature changes with every build, so an ad-hoc `make install` can lose the Gmail sign-in or ask for permissions again. Releases are signed and notarized only by the tag workflow.
- Update documentation when behavior changes.

## Reporting problems

Open an issue with your macOS version, the Mailbell version from Settings →
Updates, and what you expected versus what happened. Never paste tokens, OAuth
codes, or full email content into an issue.
