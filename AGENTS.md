# Mailbell — Agent Policy

Root rules for Mailbell; a subtree `AGENTS.md` overrides them for that subtree.

## Project identity and policy

- Display name: `Mailbell`
- Code name: `Mailbell`
- Slug: `mailbell`
- Identifier name: `mailbell`
- Benefit-first description: Gmail notifications in your macOS menu bar — instant IMAP IDLE alerts, a review queue you can clear in one click, no server in between.
- Repository: `martonpaulo/mailbell` (public); `origin` is the owner's fork, `upstream` the original project.
- Public identifiers: bundle identifier `com.martonpaulo.mailbell` from v0.4.0; `LegacyDomainMigration` copies the previous identifier's preferences once and Keychain tokens are not migrated, so each account signs in again (Decided on #47); executable `mailbell`; app `Mailbell.app`.
- Landing page: `https://mailbell.martonpaulo.com/`, owned by Marton Paulo, published from `site/` (`site/CNAME` names the host) by `deploy.yml`. A further domain or DNS change needs a separate explicit request.
- License: `MIT`
- Copyright: 2026 samzong and 2026 Marton Paulo; `LICENSE` and `NOTICE.md` keep both lines and every third-party notice. The app credit, `NSHumanReadableCopyright`, is two lines: `© 2026 Marton Paulo. Licensed under the MIT License.` and `Originally based on software by samzong.` (Decided on #73).
- Development language: English.
- Product copy: English only, read from one English-only String Catalog, `Support/Localizable.xcstrings`; no locale is added (Decided on #44; #61 adds it). The OAuth callback page stays an HTML template.
- Browser acceptance targets: Chromium and WebKit/Safari for the site and the OAuth callback page; check native Safari by hand when tooling cannot.
- Branch policy: work on `main` unless the owner explicitly requests a branch.
- Commit policy: a focused Conventional Commit when the authorized change is complete and validated; commit only task files.
- Push policy: only on explicit owner request, to `origin`; never to `upstream`.
- Product versioning: SemVer `X.Y.Z` in `CFBundleShortVersionString` (`Support/Info.plist`); `scripts/resolve-release-metadata.sh` derives the build number; tags `vX.Y.Z`. Versions change only in an explicit release request.
- Merge policy: merge commits only, every commit of the branch preserved. Never squash. Merge only an explicitly authorized pull request; an issue plan or review never authorizes it.
- Commit subject: a commit made for an issue ends with `(#<issue number>)`.
- Delete branches after merge: disabled on GitHub; delete one only on separate authorization.
- GitHub controls: secret scanning and push protection on; no ruleset or required check; `main` unprotected.
- GitHub topics: `gmail`, `gmail-imap`, `gmail-notifier`, `imap-idle`, `keychain`, `macos`, `menu-bar`, `menu-bar-app`, `notifications`, `oauth2`, `pkce`, `productivity`, `sparkle`, `swift`, `swiftui`.
- Issue metadata: keep the `bug`, `enhancement`, `documentation` types and the `priority:`, `evidence:`, `effort:`, `status:` labels; renaming a whole dimension needs an approved grooming mapping. A decision issue stays unassigned with `status: needs-decision`.
- Release, signing, and secret-storage policy: direct download, outside the Mac App Store. No field below is secret.
  - Channel and artifacts: GitHub Releases: `Mailbell-<version>.dmg` (canonical) and `Mailbell-<version>.zip` (Sparkle update).
  - Signing identity: `Developer ID Application: Marton Paulo (TBN79KU9ML)`.
  - Team ID: `TBN79KU9ML`.
  - Bundle identifier: `com.martonpaulo.mailbell`.
  - Build and package command: `scripts/package-with-oauth.sh` (the OAuth client around the canonical `scripts/package-app.sh`), then `scripts/make-dmg.sh`.
  - Entitlements and hardened runtime: no entitlements file; hardened runtime on.
  - Keychain profile: `skd-notary`, for local rehearsals; CI uses the `NOTARY_API_KEY*` secrets.
  - Release workflow: `release.yml`, run by a `v*.*.*` tag on the current `main` commit, equal to `CFBundleShortVersionString`.
  - Update feed: Sparkle `appcast.xml` at `SUFeedURL`, written by `release.yml` after the GitHub Release exists.
  - Homebrew cask: none.
  - Publishing authority: the owner, by pushing the tag; only artifacts verified in that run publish.
  - Secrets: the six standard release secrets and `MAILBELL_GOOGLE_CLIENT_*` in GitHub; the Sparkle private key also in the login Keychain.
- Skills baseline revision: `7cfc324fcded57145c36cc678977c070ed800692`
- Skills baseline applied: `2026-09-09`

Change an established identifier, license, visibility, branch, versioning, localization, landing-page or release policy only through an explicit task describing the migration and its effects.

## Build and validate

Use `make` targets, never hand-rolled equivalents. `make check` runs `build`, `lint`, `test` and `validate` and fails on any compiler warning. `make install` puts an ad-hoc signed bundle in `/Applications`, the only way to exercise notifications. Logs and generated artifacts go under `artifacts/` (ignored).

## Mailbell rules

Each line is the non-negotiable; the linked document holds the rule.

- **No backend, ever**; no reader or mail management ([product](docs/product.md)).
- **Public, stable Apple APIs only**; SwiftUI first, AppKit only where SwiftUI lacks the surface.
- **One bundle identifier**: Keychain and UserDefaults derive from it.
- **OAuth and data** ([architecture](docs/architecture.md#oauth-and-credentials)): scopes `https://mail.google.com/`, `openid`, `email`; tokens in Keychain only; previews `BODY.PEEK[TEXT]<0.8192>`.
- **Reliability** ([architecture](docs/architecture.md#reliability-contracts)): IMAP IDLE, never content polling; identity is (mailbox, `UIDVALIDITY`, UID).
- **Interface** ([interface](docs/interface.md)): design tokens only; no business logic in views.
- **Defaults** ([feature defaults](docs/feature-defaults.md)): one home for every default, each with a configurability decision.

## Architecture

See [docs/architecture.md](docs/architecture.md). Standard SwiftPM layout: `Sources/Mailbell`, `Tests/MailbellTests`, and pure logic in a `MailbellKit` library target (Decided on #44; #62 adds it). The app target is main-actor by default; warnings are errors. Add no other package, target, or top-level folder.

## Instruction hierarchy and sources of truth

- Follow the direct task, the most specific scoped instructions, this file, then general agreements. Read applicable instructions before editing.
- Code is evidence of current behavior, `AGENTS.md` is normative for process, and an approved specification for desired behavior. Expose divergence among them; never resolve it silently.
- When two sources disagree (issues, comments, this file, the agent's memory, the owner's current instruction), a newer trusted statement is the recommended side, never the decided one. Ask the owner before acting on either side and record the answer in the newer issue; `skd-agent-context-validation` owns the precedence.
- Keep one canonical source per rule; other documents link to it.
- Do not turn analysis, research, or a read-only audit into implementation without authorization.
- The owner calls `issue-*` and `project-*` skills by name; `skd-*` skills are internal: offer one in plain words, never by name.
- Be direct and evidence-based: state assumptions, risks, tradeoffs, blockers. Ask only about a material decision you cannot discover safely; otherwise make explicit, reversible assumptions.
- Give concise progress updates during long-running work.

## Long-running operations

For any command, process, browser action, integration, or delegated task likely to run long:

- Use the client's bounded yield, timeout, or status mechanism and wait for an observable
  condition instead of an arbitrary sleep.
- Keep the user informed at least once per minute when the client supports progress commentary.
- Distinguish slow but progressing work from a stall using new output, state changes, resource
  activity, the known duration of the current phase, or a tool-reported deadline. Elapsed time
  alone is not evidence of a stall.
- Inspect the current output and state before interrupting, retrying, or changing approach.
- Interrupt only when there is evidence of no useful progress, a deadline has expired, or the
  continued cost or risk is no longer justified.
- After an interruption, explain what state or output was preserved, diagnose the likely cause,
  and choose a narrower retry, a different tool, a smaller unit of work, or an explicit blocker.
- Never rerun the same unchanged failure, and do not add a polling service, background job, timer,
  or other infrastructure merely to satisfy this rule.
- Keep termination thresholds task-specific. Workflow-specific wait tools and user-input
  boundaries remain authoritative.

## Before editing

1. Check applicable instructions, Git status, and the current branch.
2. Search for the behavior, callers, tests, contracts, and nearby patterns; read only the chunks the change needs.
3. Distinguish verified facts, reasonable inferences, and unknowns, and define the source of truth before changing data or state.
4. When the project records an upstream or reference project, consult it before planning. When
   this project solves the problem differently, document the divergence and its reason.
5. Make a short plan only for complex, risky, ambiguous, or multi-file work.

## Scope, reuse, and implementation

- Keep changes scoped to the requested result: no unrelated cleanup, redesign, dependency updates, broad refactors, or future work. Preserve behavior outside the task and unrelated or uncommitted user changes.
- Reuse existing code, tokens, configuration, tests, and platform capabilities before creating new ones.
- Follow the patterns this project already repeats. When a change would break a recorded pattern or establish a new one, stop and ask first, naming the existing pattern, the proposed one, and why the existing one does not fit. Deviating is allowed; deviating silently is not.
- Mailbell's recorded patterns: one persistence path; no hardcoded dimension, new dependency, polling, view logic, backend, or broader OAuth scope.
- Prefer the smallest correct, readable, reversible solution that is cheap to operate.
- Keep one owner and one source of truth for each business rule, state, default, and copy value, outside presentation and adapter layers. Derive values instead of storing synchronized copies; model invalid states explicitly.
- Add no dependency, service, layer, cache, timer, polling or background job without a current requirement and an owner.
- Deliver large changes in reviewable, executable increments. Implement errors, states, accessibility, and tests with the behavior.

## Data, security, and destructive operations

- Distinguish canonical data, reconstructible cache, transient state, and preferences. Persist or synchronize only data that must survive or cross devices; a cache never becomes a source of truth.
- Use stable application-owned identifiers, and validate data at input and persistence boundaries.
- Change a relational schema only through an explicit, tested, versioned migration, never manually in production. Use transactions or atomic writes when partial failure could leave inconsistent state.
- Request only necessary permissions and scopes. Keep credentials, keys, signing material, personal data, and sensitive payloads out of the repository and logs.
- Use structured subprocess arguments and validate destinations, redirects, and untrusted inputs.
- Resolve an exact target before deletion, overwrite, interruption, or another hard-to-recover action. A clear request authorizes its exact resolved operation; ask again when the target is ambiguous, loss is difficult to recover, or effects exceed the named scope.
- Prefer recoverable deletion. Never force-push or perform broad cleanup without explicit authorization.

## Product interface and accessibility

- Prefer native platform components and established patterns; custom UI must provide clear product value.
- Before creating or changing an interface, a style, or a visual asset, name what the product should communicate and how it should feel to the person using it, from the product definition and brand decisions, and judge visual and copy choices by that intent. When none is recorded, state the one you infer and ask before a consequential visual change.
- Define the layout and the loading, empty, error, disabled, and destructive states that apply. Include keyboard navigation, focus, screen-reader labels, scalable text, contrast, reduced motion, and non-color status cues in the same change.
- Accessibility evidence is automated. Manual screen-reader passes are not run; the owner accepted that gap in `docs/product.md` under `## Accepted evidence gaps` (martonpaulo/skill-deck#266), so a missing pass never blocks completion.
- Keep visible copy centralized and localized. Keep expensive work out of render paths and hot loops. Measure before claiming a performance problem.

## Code, comments, and documentation

- Write code, comments, commits, filenames, tests, configuration, and developer documentation in English; product copy follows the localization strategy. Write human-facing English in plain international English that non-native readers understand: precise verbs, no idioms, short sentences.
- Follow the existing formatter, linter, naming, layout, and architecture. Prefer clear types and simple control flow.
- Comment non-obvious constraints, linking official documentation when a workaround must stay visible.
- Update the smallest canonical documentation section when a durable contract changes; never create empty documentation.
- Record a consequential decision in the canonical document that owns the rule, with the deciding
  issue cited beside it as `Decided on #N`. No issue, wiki page or long-lived comment serves as a
  decision register. Index those decisions in a `## Decision index` section of the product definition, one row each, pointing to the rule.
- README: the recorded `Display name` is the H1. Links to the live project are allowed. The rest
  follows the `project-setup` skill's `references/public-surface-style.md`.
- Every fenced code block you create or materially edit has an explicit language identifier.
- Preserve third-party licenses and notices in `NOTICE.md`. Maintain `CHANGELOG.md` when the project has public releases.

## Durable project learning

At wrap-up, propose recording a learning only when it is verified, specific to this project, likely
to recur, and not already recorded, as the `project-setup` skill's `references/durable-learning.md`
defines. A command that failed twice for the same cause qualifies: record the cause and working form.

## Output shape

Shape every message so it can be acted on at once, including by a reader with ADHD. Adapted from
[ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd) (MIT, Ayoub Ghriss).

1. **Lead with the next action.** A command, path or snippet comes first; prose follows, if at all.
2. **Number multi-step work.** One bounded action per step, the fewest steps that work.
3. **End with one concrete next action** doable in under two minutes, when anything is left open.
4. **Suppress tangents.** Finish the first thing; offer the second as a separate question.
5. **Restate the state every turn**: what is done and what is next.
6. **Give time estimates in concrete units**, never "some work".
7. **Make completed work visible**: what now works and how to see it.
8. **State errors plainly**: the cause, then the fix.
9. **Keep lists short**: grouped, most relevant first, at most five per group, none dropped.
10. **No preamble, no recap, no closing pleasantries.**

The shape gives way for an explanation the user asks for, before a destructive action (confirm
first), after repeated failures (name the doubtful assumption, ask one question), for real
ambiguity or options (one question; two to four ranked options), and for a required format such
as an attention card, an execution plan, a completion report, or machine-read output.

## User attention cards

When the user must notice and respond to a proposed follow-up, a material choice, a permission
boundary, or a blocker, use exactly one of the four attention cards below. Their templates and
full rules are in the `skd-grilling` skill's `references/attention-cards.md`. Never hide one inside a
general summary, ordinary bullet list, or vague "human review" note.

Render every visible heading, field label, explanation, option, recommendation, and reply token in
the language already used with the user. Follow a later explicit change of language.
Surround every card with a Markdown horizontal rule: a standalone `---` before its heading and
another after its final response line. The emoji supplements the descriptive heading and never
replaces it. Use one card per request, ending with an exact reply format.

A card alone ends the turn without asking: also ask through the client's structured-question
tool when it has one (`AskUserQuestion` in Claude Code). When several
decisions are pending and the client can publish interactive HTML, the decision page that
`skd-grilling` defines asks them instead.

- **Proposed issue**: an evidence-backed improvement outside the accepted scope, not already
  tracked. The card proposes backlog capture; it never authorizes creating or publishing the issue.
- **Decision needed**: materially different outcomes. Show options and tradeoffs, recommend one.
- **Approval needed**: one preferred action across a permission, publication, destructive, cost,
  privacy, or external boundary. Name the exact target, expected change, risk, reversibility, and recovery path.
- **Action needed**: work blocked by one user action. State what is blocked, why the agent cannot continue, the smallest unblocking action, and the observable condition for resumption.

## Configuration and repository hygiene

- Ignore secrets, local environments, logs, caches, and build output. Keep `.env.example` with every variable and a safe placeholder, and secrets only in the platform's secure store.
- Add CI, dependency updates, release workflows, and signing only when distribution or risk requires them.
- Workflows are `validate.yml` (`Validate`), `deploy.yml` (`Deploy`, started by Validate through `workflow_run`) and `release.yml` (`Release`), plus the macOS app's `notary-check.yml`; any other is a recorded exception. Do not add an image-optimisation bot.
- The agent rules live in `AGENTS.md`, the one real file, at most 24,000 bytes (the most Antigravity CLI loads; `make validate` checks it); `CLAUDE.md` is a symlink to it. Do not create `GEMINI.md`, `.gemini/rules/agents.md`, or any other alias, and never commit `.claude/settings.local.json`.
- Change the repository `homepage` only as the `project-setup` skill's `references/github-settings.md` describes.

## Tests and validation

- Add or update focused tests for changed behavior, regressions, persistence, migrations, security, and critical accessibility, at stable seams.
- A behavioral bug fix includes a regression test proven to fail without the fix: run it against the unfixed code and see it fail before committing.
- Run the smallest relevant check while iterating. Before each commit, run the full suite and repository validation when the full suite takes about 90 seconds or less; otherwise run the suites that cover a change or list its directory, let CI run the full suite, read its result before reporting done, and require zero failures and zero warnings. Use a real integration only when local tests cannot prove the contract.
- When a change alters behavior, run the real application with its native diagnostics and observe the changed behavior. Green tests are not seeing it run.
- Never claim a check passed unless it ran. Report skips, blockers, residual risk, what was verified manually, and what remains unverified.
- A piped check reports the last command's status: `npm run lint | tail -3` exits 0 when lint fails. Run a gating check unpiped or with `set -o pipefail`. A check whose exit code you did not observe has not run.
- Local browser tests (Playwright or similar) run one project and the targeted tests while iterating (`--project=<name> -g "<pattern>"`), always pass `--workers=1`, and do not launch one while the 1-minute load average is above 8; run the full browser suite only as the final step before commit. They apply to local runs, not to CI on dedicated runners.

## Artifacts and processes

- Temporary is the default; retention is an explicit exception. Remove only temporary files the current task created, keeping deliverables and failure evidence, never pre-existing artifacts, fixtures, baselines, or logs, and never version caches, logs, coverage, or build output.
- Before ending the turn, stop every server, watcher, browser, simulator, container, worker, and other process the session started. Do not stop the user's pre-existing processes.

## Agent skill paths

- Product definition: `docs/product.md`
- Domain glossary: `CONTEXT.md` (optional; create only when useful)
- ADRs: `docs/adr/` (only for hard-to-reverse, non-obvious decisions)
- Research notes: `docs/research/` (create only when persisting research)
- Handoffs: `.scratch/handoffs/`
- Prototypes: `.scratch/prototypes/`

## Git and releases

- Follow the recorded branch, commit, push, and version policies. Check status and branch before editing and before the final report; leave unrelated changes untouched.
- Use English Conventional Commits, one per concern, ending with the issue number, never the pull request's: `feat: add the export button (#54)`.
- Merge with every commit: `gh pr merge <number> --merge --delete-branch`. Never squash.
- Read the exact payload before a commit, push, published text, or release upload. Stop on a
  credential, key, signing material, or sensitive personal value, never print it, and refuse a
  plaintext secret even on request. A published value is revoked or rotated; deleting it does not
  unpublish it. `skd-github-publishing-conventions` owns the gate.
- Never force-push. If commit or push fails, report the exact failure.
- Close an issue resolved as `completed` only with one signed closing comment on the issue that names the resolving commit, what was verified (checks, tests, manual runs), and what was not verified.
- Release or change a version only when the task and recorded policy authorize it, through `project-release`.

## Completion report

Lead with the outcome, in the output shape above, and include:

- what changed and why, and the files touched;
- validation commands and results, with warnings, skips, and remaining risks;
- what running the application verified, and what remains unverified;
- each issue closed, with the resolving commit its closing comment names;
- temporary artifacts kept or removed, commit, branch, push, and worktree status, and unrelated dirty files.
