<div align="center">

<h1>claudeline</h1>

**A compact, informative status line for Claude Code with spend, cache, and usage signals.**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Bash](https://img.shields.io/badge/bash-3.2+-4EAA25?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Claude Code](https://img.shields.io/badge/Claude_Code-status_line-000?logo=anthropic&logoColor=white)](https://claude.ai/)

</div>

```
✨ ████░░░░░░  ·  myrepo/main*  ·  👌→  ·  42¢/m ↗ 1.3x  ·  +50/-20  ·  💥▃  ·  💳25%
│  └────┬────┘     └─────┬─────┘   └─┬──┘   └─────┬─────┘   └───┬──┘   └─┬┘   └─┬──┘
│    context          repo/branch    pace      cost rate      lines    burst  credit
│    bar              + git status   trend   + arrow + fold   changed
└─ context icon (✨🌱💭🧠⚡🔥🌡️🫠💀💾)

    73.5K/168K  ·  🗄️90%  ·  🔥max  ·  🧱💰 $4.50  ·  ⏱️ 45m
    └────┬────┘    └─┬──┘    └┬┘      └────┬────┘    └──┬──┘
      context       cache   effort      scoped       duration
      tokens        reuse                metric
```

<div align="center">
<img src="docs/assets/claudeline-screenshot.png" alt="claudeline in action" width="900">
</div>

<hr>

<h2 align="center">📑 Contents</h2>

- [🚀 Quick Start](#quick-start)
- [✨ Features](#features)
- [💰 Spend, Cache & Effort](#spend-cache-effort)
- [📊 Smart Pace Indicator](#smart-pace-indicator)
- [💥 Burst & Credit Indicators](#burst--credit-indicators)
- [🌍 Environmental Impact](#environmental-impact)
- [🏆 All-Time Tracking](#all-time-tracking)
- [⚡ Performance](#performance)
- [🔒 Privacy & Network Access](#privacy--network-access)
- [🔧 Requirements](#requirements)
- [🗑 Uninstall](#uninstall)

<hr>

<h2 align="center" id="quick-start">🚀 Quick Start</h2>

**One command:**

```bash
curl -fsSL https://raw.githubusercontent.com/s-b-e-n-s-o-n/claudeline/main/install.sh | bash
```

> **Tip:** Review the [install script](install.sh) before running. The installer verifies SHA-256 checksums of all downloaded files before installing them.

Then restart Claude Code. That's it.

<details>
<summary>Optional: create a config file</summary>

Create `~/.claude/claudeline.conf` to customize without env vars:

```bash
# ~/.claude/claudeline.conf
theme=nord
segments=context,git,pace,duration,tokens,cache,effort,throughput,metric
no_network=0
```

Env vars override config file values. All keys are optional.

Available keys: `theme`, `segments`, `no_network`, `no_color`, `debug`, `debug_log`, `jsonl_cache_ttl`, `extra_usage_ttl`, `spend_cache_ttl`, `spend_block_seconds`, `trend_window`, `trend_history_max_age`, and the `cost_rate_*` knobs listed below.

</details>

<details>
<summary>Manual installation</summary>

1. Download the runtime files:
   ```bash
   mkdir -p ~/.claude/lib
   curl -fsSL https://raw.githubusercontent.com/s-b-e-n-s-o-n/claudeline/main/statusline.sh -o ~/.claude/statusline.sh
   curl -fsSL https://raw.githubusercontent.com/s-b-e-n-s-o-n/claudeline/main/lib/statusline_themes.sh -o ~/.claude/lib/statusline_themes.sh
   curl -fsSL https://raw.githubusercontent.com/s-b-e-n-s-o-n/claudeline/main/lib/statusline_display.sh -o ~/.claude/lib/statusline_display.sh
   curl -fsSL https://raw.githubusercontent.com/s-b-e-n-s-o-n/claudeline/main/lib/statusline_usage.sh -o ~/.claude/lib/statusline_usage.sh
   curl -fsSL https://raw.githubusercontent.com/s-b-e-n-s-o-n/claudeline/main/lib/jsonl_parser.pl -o ~/.claude/lib/jsonl_parser.pl
   curl -fsSL https://raw.githubusercontent.com/s-b-e-n-s-o-n/claudeline/main/lib/anthropic_pricing.json -o ~/.claude/lib/anthropic_pricing.json
   chmod 700 ~/.claude/statusline.sh
   ```

2. Add to your `~/.claude/settings.json`:
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "~/.claude/statusline.sh",
       "padding": 0
     }
   }
   ```

3. Restart Claude Code

</details>

<hr>

<h2 align="center" id="features">✨ Features</h2>

<table>
<tr>
<td align="center" width="33%">
<h3>10-Tier Context Bar</h3>
Adapts to auto-compact setting — scales to 168K (ON) or 200K (OFF), or 1M on extended context models, with color gradient and emoji icons
</td>
<td align="center" width="33%">
<h3>Smart Pace Indicator</h3>
Dual-signal weekly pace (burn rate + pressure) with 8-tier emoji scale and velocity-based trend arrows
</td>
<td align="center" width="33%">
<h3>Burst & Credit</h3>
8-level colored bar for 5-hour rate limit with reset countdown, plus overage credit tracking
</td>
</tr>
<tr>
<td align="center">
<h3>Environmental Metrics</h3>
Rotating display of water, power, cost, tokens, and data with dynamic unit scaling
</td>
<td align="center">
<h3>Scoped Usage</h3>
Session, today, 5-hour block, project, and all-time metrics share one compact rotation
</td>
<td align="center">
<h3>All-Time Tracking</h3>
Cumulative usage across all sessions from JSONL files, shown with the 🏆 scope marker
</td>
</tr>
<tr>
<td align="center" width="33%">
<h3>Git Integration</h3>
Repo/branch with status indicators — unstaged, staged, ahead/behind, stash count
</td>
<td align="center" width="33%">
<h3>5 Built-in Themes</h3>
Vibey (default), Dark, Light, Nord, and Gruvbox — plus NO_COLOR support
</td>
<td align="center" width="33%">
<h3>Cost-Rate Indicator</h3>
Account-wide cents/min (API-active time) over the current working window, with a red/dim/green arrow and symmetric fold change (e.g. <code>↑ 3.2x</code> for 3.2× faster, <code>↓ 2.0x</code> for half-speed) against your recent baseline. Shows <code>◌</code> while current/baseline data is still warming.
</td>
</tr>
<tr>
<td align="center" width="33%">
<h3>Spend Windows</h3>
Folds today, 5-hour block, project, and all-time token/cost totals into the metric slot
</td>
<td align="center" width="33%">
<h3>Cache Efficiency</h3>
Shows cache-read share (<code>🗄️90%</code>) or cache-write spikes (<code>🗄️✍️5K</code>) from the live statusline payload
</td>
<td align="center" width="33%">
<h3>Thinking Effort</h3>
Shows the active thinking tier with five distinct states: <code>🌱low</code>, <code>💭med</code>, <code>🧠high</code>, <code>⚡xhi</code>, <code>🔥max</code>
</td>
</tr>
</table>

<hr>

<h2 align="center" id="spend-cache-effort">💰 Spend, Cache & Effort</h2>

**Scoped metrics** — line 2 keeps one metric slot and rotates scope + metric:

| Display | Meaning |
|---------|---------|
| `💧 1 tablespoons` | Current session water estimate |
| `📅💰 $18.00` | Today's local-calendar spend |
| `🧱🎟️ 1.2M` | Tokens inside the active rolling block window (5h by default) |
| `📁📡 4.7MB` | Current project data estimate |
| `💰 $123.45 🏆` | All-time account spend |

The metric types are fixed and sober: `💧` water, `⚡` power, `💰` cost, `🎟️` tokens, and `📡` data. Window totals are computed from local JSONL transcripts in a background refresh and cached in `.spend-cache`, so the statusline stays fast.

**Cache efficiency** — `🗄️90%` means most prompt/context input came from cache reads. `🗄️✍️5K` means cache writes are currently larger than cache reads, which is usually the interesting cost spike when a new setup, hook, or context load causes fresh cache creation.

**Thinking effort** — the effort segment maps the current Claude Code effort level to five compact states: `🌱low`, `💭med`, `🧠high`, `⚡xhi`, `🔥max`. If thinking is enabled but no effort level is present, it shows `💭think`.

<hr>

<h2 align="center" id="smart-pace-indicator">📊 Smart Pace Indicator</h2>

Compares your actual weekly usage against where you *should* be based on time elapsed in the 7-day rolling window.

**The math:** Two signals, take the worse one:
- **Burn rate** (velocity): `(pct / days_elapsed) × 7 / 100` — how fast you're going
- **Pressure** (position): `days_remaining / budget_remaining_in_days` — remaining runway

`effective = max(burn_rate, pressure)`

Both signals agree on over/under pace (`> 1.0` = over, `< 1.0` = under), but pressure amplifies urgency when budget is thin. For example, at 91% on Monday 8pm with reset Thursday 1pm: burn rate is 1.48 (🥵) but pressure is 4.29 — you have 9% left for 2.7 days (🚨).

Combined display: `👌→` (on pace, stable) or `🔥↑` (hot, getting hotter). At 100%, shows reset countdown: `🚨 -1.2d`. Alternates with raw % every 10th update.

<details>
<summary><strong>Pace emoji tiers</strong></summary>

| Effective Rate | Emoji | State |
|-------|-------|-------|
| < 0.3 | ❄️ | Way under pace |
| 0.3-0.6 | 🧊 | Under pace |
| 0.6-0.85 | 🙂 | Comfortable |
| 0.85-1.15 | 👌 | On pace |
| 1.15-1.4 | ♨️ | Warming |
| 1.4-1.8 | 🥵 | Hot |
| 1.8-2.5 | 🔥 | Very hot |
| ≥ 2.5 | 🚨 | Critical |

</details>

<details>
<summary><strong>Trend arrows</strong></summary>

Tracks **usage% velocity** — how fast you're burning tokens compared to the sustainable rate (100% / 7 days ≈ 0.01%/min).

| Velocity | Arrow | Meaning |
|----------|-------|---------|
| > 3x sustainable | ↑ | Heating fast |
| 1.5-3x sustainable | ↗ | Warming up |
| 0.5-1.5x sustainable | → | Stable |
| 0.1-0.5x sustainable | ↘ | Cooling down |
| < 0.1x sustainable | ↓ | Cooling fast |

**History retention:** Last 15 min dense (every ~30s), 15min–24h sparse anchors (1 per 4h), older pruned.

</details>

<hr>

<h2 align="center" id="burst--credit-indicators">💥 Burst & Credit Indicators</h2>

**💥 Burst** (5-hour rate limit) — colored bar mapped directly to API utilization %, only shown when > 0%. Alternates to raw percent (`💥25%`) on the same cycle style as the pace indicator.

| Range | Bar | Color |
|-------|-----|-------|
| 1-12% | ▁ | cyan |
| 13-24% | ▂ | teal |
| 25-37% | ▃ | green |
| 38-49% | ▄ | yellow |
| 50-62% | ▅ | orange |
| 63-74% | ▆ | red |
| 75-87% | ▇ -135m | magenta + countdown |
| 88%+ | █ -90m | bright magenta + countdown |

A dimmed countdown shows minutes until the 5-hour window resets whenever usage is 75%+ *or* the reset is under an hour away.

**💳 Credit** (overage balance) — only shown when weekly or burst usage hits 100% with active credit spend.

<hr>

<h2 align="center" id="environmental-impact">🌍 Environmental Impact</h2>

The rotating metrics visualize the environmental cost of AI inference:

| Metric | Rate | Source |
|--------|------|--------|
| 💧 Water | 1 gal = 760k tokens | [arxiv:2304.03271](https://arxiv.org/pdf/2304.03271) |
| ⚡ Power | 1 kWh = 240k tokens | [arxiv:2505.09598](https://arxiv.org/html/2505.09598v1) |
| 💰 Cost | Built-in | Claude Code API |

**Dynamic units:** Water scales drops → tsp → tbsp → oz → cups → pints → quarts → gallons. Power scales Wh → kWh → MWh.

<hr>

<h2 align="center" id="all-time-tracking">🏆 All-Time Tracking</h2>

Cumulative usage across all sessions by scanning JSONL files in `~/.claude/projects/` and `~/.config/claude/projects/`.

The `🏆` suffix indicates all-time totals in the scoped metric rotation. The same five metrics are used for every scope: water, power, cost, tokens, and data.

<details>
<summary><strong>Context bar tiers</strong></summary>

**Auto-compact ON** (10 tiers, scaled to 168K):

| Range | Color | Icon | Meaning |
|-------|-------|------|---------|
| 0-9% | Cyan | ✨ | Fresh |
| 10-19% | Lime | 🌱 | Growing |
| 20-34% | Yellow | 💭 | Thinking |
| 35-49% | Orange | 🧠 | Working hard |
| 50-61% | Coral | ⚡ | Heating up |
| 62-73% | Red | 🔥 | Hot |
| 74-83% | Hot Pink | 🌡️ | Running hot |
| 84-91% | Magenta | 🫠 | Melting — compact soon |
| 92-96% | Violet | 💀 | Critical |
| 97%+ | White Hot | 💾 | About to auto-compact |

**Auto-compact OFF** (8 tiers, scaled to 200K):

| Range | Color | Icon | Meaning |
|-------|-------|------|---------|
| 0-14% | Cyan | ✨ | Fresh |
| 15-29% | Lime | 🌱 | Growing |
| 30-49% | Yellow | 💭 | Thinking |
| 50-64% | Orange | 🧠 | Working hard |
| 65-74% | Coral | 🔥 | Hot |
| 75-84% | Red | 💾 | Compact zone |
| 85-94% | Hot Pink | 🫠 | Past compact zone |
| 95%+ | Magenta | 💀 | Near hard wall |

</details>

<hr>

<h2 align="center" id="performance">⚡ Performance</h2>

| Scenario | Time |
|----------|------|
| Fully warm (typical) | ~180ms |
| Stale cache (async refresh in background) | ~180ms |
| Best case | ~175ms |
| First-ever run, no state file | ~6s (10K+ files, 1.2GB) |

**Cost breakdown** (warm, ~180ms total):

| Phase | Time | Tool |
|-------|------|------|
| Git status | ~90ms | 3 git calls |
| jq parse | ~16ms | 1 jq call |
| Trend/pace | ~20ms | 1 awk call |
| JSONL cache read | ~5ms | bash read |
| Formatting | ~22ms | 1 awk + bash math |
| Source libs + rest | ~27ms | bash |

Rate limit data comes directly from the Claude Code status line JSON — zero network calls during normal operation. The first-ever run uses a fast streaming pipeline (`xargs cat | perl`) to build initial state, then subsequent refreshes only process appended bytes per file. Once state exists, stale caches are served immediately and the refresh runs in a **disowned background subshell** (guarded by `.refresh.lock.d`) so the render path never blocks on a rescan — even on a multi-gigabyte transcript backlog.

<hr>

<h2 align="center" id="privacy--network-access">🔒 Privacy & Network Access</h2>

claudeline makes **one optional API call** to `https://api.anthropic.com/api/oauth/usage` — a `GET` request with only an `Authorization` header. No telemetry, no tracking, no data sent in the request body. This call only triggers when weekly or burst rate limits reach 100%, to fetch overage/credit utilization.

The OAuth token is read from:
- **macOS:** macOS Keychain via `security find-generic-password`
- **Linux:** `~/.config/claude/credentials.json`

claudeline also reads `~/.claude.json` to detect the auto-compact setting (controls context bar scaling).

The API call runs in a **non-blocking background subshell** so it never stalls the status line.

| Variable | Effect |
|----------|--------|
| `CLAUDELINE_THEME=nord` | Theme: `vibey` (default), `dark`, `light`, `nord`, `gruvbox` |
| `CLAUDELINE_SEGMENTS=context,git,pace` | Show only listed segments. Default keeps `model` and standalone `spend` off for a shorter line. Available: `context`, `git`, `lines`, `pace`, `burst`, `duration`, `credit`, `tokens`, `spend`, `cache`, `effort`, `metric`, `throughput`, `model` |
| `NO_COLOR=1` | Disables all color output ([spec](https://no-color.org)) |
| `CLAUDELINE_NO_NETWORK=1` | Disables all network access — the API call is skipped entirely |
| `CLAUDELINE_DEBUG=1` | Enables debug logging to `$TMPDIR/claudeline-statusline-debug.log` |
| `CLAUDELINE_DEBUG_LOG=/path` | Custom debug log path (requires `CLAUDELINE_DEBUG=1`) |
| `JSONL_CACHE_TTL=300` | JSONL cache lifetime in seconds (default: 300) |
| `EXTRA_USAGE_TTL=600` | Extra usage / credit cache lifetime in seconds (default: 600) |
| `SPEND_CACHE_TTL=600` | Spend window cache lifetime in seconds (default: 600). Stale values render immediately while a background refresh runs. |
| `SPEND_BLOCK_SECONDS=18000` | Rolling active block spend window in seconds (default: 5h). |
| `TREND_WINDOW=900` | Trend arrow sample window in seconds (default: 900) |
| `TREND_HISTORY_MAX_AGE=86400` | Max age for trend history entries in seconds (default: 86400) |
| `COST_RATE_CURRENT_WINDOW=3600` | Current account-wide cost-rate window, in wall-clock seconds (default: 1h). Rates divide only by API-active time inside the window, so idle time does not lower the pace. `COST_RATE_WINDOW` is still accepted as a legacy alias. |
| `COST_RATE_BASELINE_WINDOW=86400` | Baseline lookback before the current window, in wall-clock seconds (default: 24h). If this is thin, retained history up to `COST_RATE_HISTORY_MAX_AGE` is used. |
| `COST_RATE_BUCKET_SECONDS=60` | Account-wide cost-rate bucket size, in seconds (default: 60). |
| `COST_RATE_MIN_CURRENT_API_MS=300000` | Minimum active API time in the current window before the arrow leaves the warming marker (default: 5 min). |
| `COST_RATE_MIN_BASELINE_API_MS=1800000` | Minimum active API time in the baseline before the arrow leaves the warming marker (default: 30 min). |
| `COST_RATE_HISTORY_MAX_AGE=604800` | How long `.cost-rate-history` buckets and `.cost-rate-state` rows are retained before pruning, in seconds (default: 7d). |
| `COST_RATE_TREND_HOT_X100=150` | Hot threshold: current active rate ≥1.50× baseline (default: 150) |
| `COST_RATE_TREND_WARM_X100=115` | Warm threshold: current active rate ≥1.15× baseline (default: 115) |
| `COST_RATE_TREND_COOL_X100=85` | Cool threshold: current active rate ≤0.85× baseline (default: 85) |
| `COST_RATE_TREND_COLD_X100=50` | Cold threshold: current active rate ≤0.50× baseline (default: 50) |

**Local data stored** in `~/.claude-usage.d/` (created with `chmod 700`):

| File | Purpose |
|------|---------|
| `.jsonl-cache` | Cached all-time token/cost totals (5-min TTL; stale values are served immediately while a background refresh runs) |
| `.jsonl-state` | Per-file JSONL scan state for incremental refreshes |
| `.refresh.lock.d/` | Lock directory to prevent concurrent background JSONL refreshes |
| `.spend-cache` | Cached today, rolling-block, and current-project token/cost totals |
| `.spend-refresh.lock.d/` | Lock directory to prevent concurrent spend scans |
| `.usage-history` | Rolling 24h usage samples for trend arrows |
| `.cost-rate-history` | Account-wide `(bucket_epoch, cost_delta_cents, api_delta_ms)` buckets for the cost-rate slot, pruned to 7d |
| `.cost-rate-state` | Last-seen per-session cumulative totals used to turn session counters into account-wide cost-rate buckets |
| `.extra-usage-cache` | Cached overage/credit data |
| `.extra-usage-fetch.lock/` | Lock directory to prevent concurrent API calls |
| `.claude-config-auto-compact` | Cached auto-compact setting |

<hr>

<h2 align="center" id="requirements">🔧 Requirements</h2>

<div align="center">

[![jq](https://img.shields.io/badge/jq-JSON_parsing-C9A227)](https://jqlang.github.io/jq/)
[![git](https://img.shields.io/badge/git-branch_detection-F05032?logo=git&logoColor=white)](https://git-scm.com/)
[![perl](https://img.shields.io/badge/perl-JSONL_parsing-39457E?logo=perl&logoColor=white)](https://www.perl.org/)
[![curl](https://img.shields.io/badge/curl-install_%2B_API-073551?logo=curl&logoColor=white)](https://curl.se/)

</div>

<hr>

<h2 align="center" id="uninstall">🗑 Uninstall</h2>

```bash
# Remove statusline files
rm -f ~/.claude/statusline.sh
rm -rf ~/.claude/lib/statusline_themes.sh ~/.claude/lib/statusline_display.sh ~/.claude/lib/statusline_usage.sh ~/.claude/lib/jsonl_parser.pl ~/.claude/lib/anthropic_pricing.json

# Remove the statusLine key from settings.json
jq 'del(.statusLine)' ~/.claude/settings.json > ~/.claude/settings.json.tmp && mv ~/.claude/settings.json.tmp ~/.claude/settings.json

# Remove cached data (optional)
rm -rf ~/.claude-usage.d
```

Then restart Claude Code.

---

<div align="center">

**[MIT License](LICENSE)**

</div>
