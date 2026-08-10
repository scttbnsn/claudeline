# Contributing

Thanks for your interest in claudeline.

## Development Setup

```bash
git clone https://github.com/scttbnsn/claudeline.git
cd claudeline
```

Dependencies: `bash` (5.x), `jq`, `git`, `perl` (5.14+).

## Running Tests

```bash
for f in tests/*.sh; do bash "$f" || exit 1; done
```

## Linting

```bash
shellcheck -x statusline.sh lib/statusline_display.sh lib/statusline_usage.sh
```

## Commit Style

Conventional Commits, no emoji: `<type>(scope): <description>`

Scope is optional. Mark breaking changes with `!` before the colon (e.g. `feat(cli)!: drop legacy flag`) or a `BREAKING CHANGE:` footer.

| Type | Usage |
|------|-------|
| feat | New features |
| fix | Bug fixes (including security fixes) |
| refactor | Refactoring |
| perf | Performance improvements |
| docs | Documentation |
| test | Tests |
| build | Dependency/build changes |
| ci | CI/deploy changes |
| chore | Config and other maintenance |
| style | Formatting |
| revert | Reverting a previous commit |
