# Changelog

All notable changes to this project will be documented in this file.

## [2.1.0] - 2026-11-02

### Added
- A `cache` segment on line 2 shows a prompt-cache countdown (`♻️ 4m`, `<1m`, `1h`) from the `prompt_cache` payload field while the cache is warm, turns yellow under two minutes, and drops first on narrow terminals
- The spend segment now renders from `rate_limits.spend_limit` in the status line payload (Claude apps gateway) with no opt-in, credential, cache, or network work, and appends whole-dollar `used_usd/limit_usd` when the payload carries both
- The installer sets `refreshInterval: 30` on the status line so duration and reset countdowns stay current while idle, and keeps a positive value you already set

### Removed
- The model-name guess for a 1M context window. The status line now trusts `context_window_size` from Claude Code; the "1M context" suffix is still stripped from the displayed model name

### Fixed
- The Keychain lookup now asks for the item whose account is `$USER` first, so an old account-less or legacy "unknown" item can no longer shadow the live credential, and it uses the `Claude Code-credentials-<sha256 prefix>` service name Claude Code writes when `CLAUDE_CONFIG_DIR` is set instead of always reading the default profile's item

### Changed
- Context tokens come from `context_window.total_input_tokens` when Claude Code sends it, falling back to summing `current_usage`

### Performance
- Stash presence is read from `git status --show-stash`, dropping one git process per render on git 2.35 and later; older git keeps the `refs/stash` probe

## [2.0.0] - 2026-08-27

### Changed
- Focused the status line on context, Git state, weekly pace, burst usage, duration, model, effort, stale-build detection, and the opt-in enterprise spend signal
- Removed the legacy cost, environmental-metric, pricing-manifest, and JSONL accounting pipeline
- Moved theme values into data-driven palettes and made the layout responsive to terminal width
- Scoped spend caches, locks, retry state, and debug logs to explicit `CLAUDE_CONFIG_DIR` profiles

### Added
- Five built-in themes with `NO_COLOR` support
- Config-file and environment-based segment selection
- Auto-compact-window awareness and stale Claude Code build detection
- Opt-in enterprise spend usage with non-blocking refresh, cache, retry cooldown, and profile isolation
- Bash 3.2-compatible terminal-cell measurement for CJK, emoji, combining marks, variation selectors, flags, and joined emoji
- Transactional installation with custom profile support, symlink-preserving settings updates, rollback, and complete regression coverage

### Fixed
- Locale-dependent parsing of JSON decimal percentages
- Invalid numeric settings aborting or changing meaning through octal arithmetic
- Git branch and dirty-state parsing for unborn, detached, conflicted, type-changed, colored, and localized repositories
- Empty responsive layouts when only a later-priority segment is enabled
- Cache-directory failures aborting or leaking errors into otherwise usable renders
- Incorrect sub-hour reset countdowns and malformed spend output
- Keychain credential fallback, compact hexadecimal decoding, cache validation, and refresh-lock ownership races
- Installer destination handling, quoted custom-profile commands, settings symlink preservation, and activation rollback
- Vacuous hot-path regression guards and incomplete theme/runtime coverage

### Security
- Kept OAuth credentials out of process arguments and disabled ambient curl configuration for authenticated requests
- Moved default debug logs out of shared temporary paths and enforced private permissions
- Added end-to-end terminal-control sanitization coverage
- Ignored the complete `.claude/` local-state directory

### Performance
- Disabled untracked-file enumeration and optional Git index locks for status probes
- Reworked trend history maintenance to avoid repeated full-string copying and unchanged rewrites
- Added failed-refresh cooldowns to prevent repeated credential and network work

## [1.0.0] - 2026-04-05

### Added
- 10-tier context bar with auto-compact awareness (168K/200K scaling)
- Smart pace indicator with dual-signal math (burn rate + pressure) and trend arrows
- 8-level burst indicator with colored bar and reset countdown
- Credit indicator for overage tracking (triggers at 100% usage)
- Rotating environmental metrics: water, power, data, 34 fun cost items, 7 absurd items
- All-time usage tracking from JSONL files with incremental per-file state
- Hybrid cold scan: fast streaming pipeline (~6s) for first run
- External pricing manifest (`anthropic_pricing.json`) for per-model cost calculation
- `CLAUDELINE_NO_NETWORK=1` kill switch to disable all network access
- `CLAUDELINE_DEBUG=1` for debug logging
- SHA-256 verified installer with staged downloads
- GitHub Actions CI (ubuntu + macos)
- 42 test suites

### Architecture
- Pure bash integer math (no `bc` dependency)
- `$REPLY` return pattern to eliminate subshells in hot path
- Rate limit data from Claude Code status line JSON (no API call needed)
- `lib/` module split: `statusline_display.sh`, `statusline_usage.sh`, `jsonl_parser.pl`
- `set -euo pipefail` with comprehensive input validation
