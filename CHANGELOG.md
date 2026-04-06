# Changelog

All notable changes to this project will be documented in this file.

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
