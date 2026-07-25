## What does this change?

<!-- One or two sentences. Link the issue if there is one. -->

## Checklist

- [ ] `make check` passes (build, lint, tests, repository validation)
- [ ] Business-rule changes come with tests in `Tests/MailbellTests`
- [ ] Every user-facing behavior declares its default and configurability decision
- [ ] New preferences use the centralized defaults, preserve existing values, and are reset by Restore Defaults
- [ ] Non-configurable behavior is justified (bug/security/internal/accessibility/single valid outcome)
- [ ] No private Apple APIs, no new dependencies, no polling while idle
- [ ] No credentials, tokens, or signing material added to the repository
- [ ] No new network destination beyond Gmail and the Sparkle appcast
- [ ] Documentation updated if behavior changed
