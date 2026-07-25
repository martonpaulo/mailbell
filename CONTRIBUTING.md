# Contributing

Thanks for looking. Mailbell is a small, deliberately narrow macOS menu bar app,
and keeping it small is a feature.

## Before you start

Read [AGENTS.md](AGENTS.md). It is the durable policy for how this project is
built: product boundary, OAuth and privacy rules, reliability contracts, UI
rules, and the pattern-break protocol. It applies to humans and coding agents
alike.

## Build and check

Requires macOS 26+ and a current Xcode toolchain.

```sh
make check
```

That runs the debug build (must be warning-free), SwiftLint, the tests, and
`Scripts/validate.sh` repository invariants.

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

- Conventional Commits, English everywhere.
- Business-rule changes come with tests.
- Every user-facing behavior declares its default and configurability decision
  (see [docs/feature-defaults.md](docs/feature-defaults.md)).
- New preferences use the centralized defaults, preserve existing values, and are
  covered by Restore Defaults.
- No private Apple APIs, no new dependencies, no polling while idle.
- Never commit `.env`, credentials, tokens, or signing material.
- Update documentation when behavior changes.

## Reporting problems

Open an issue with your macOS version, the Mailbell version from Settings →
Updates, and what you expected versus what happened. Never paste tokens, OAuth
codes, or full email content into an issue.
