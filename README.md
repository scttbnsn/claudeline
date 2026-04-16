<div align="center">

<h1>claudeline</h1>

**A cute, informative status line for Claude Code with rotating environmental metrics.**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Bash](https://img.shields.io/badge/bash-3.2+-4EAA25?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Claude Code](https://img.shields.io/badge/Claude_Code-status_line-000?logo=anthropic&logoColor=white)](https://claude.ai/)

</div>

```
✨ ████░░░░░░  ·  myrepo/main*  ·  👌→  ·  ↗ 1h +0.2%/h  ·  +50/-20  ·  💥▃  ·  💳25%
│  └────┬────┘     └─────┬─────┘    └┬┘       └────┬────┘    └───┬──┘    └┬┘    └─┬─┘
│    context          repo/branch   pace        burn-rate       lines   burst  credit
│    bar              + git status  trend       indicator       changed
└─ context icon (✨🌱💭🧠⚡🔥🌡️🫠💀💾)

    73.5K/168K  ·  🍕 3 joe's®  ·  ⏱️ 45m  ·  Opus 4.6
    └────┬────┘    └─────┬─────┘    └──┬──┘    └───┬───┘
       context        rotating      session       model
       tokens         metric        duration
```

<div align="center">
<img src="docs/assets/claudeline-screenshot.png" alt="claudeline in action" width="900">
</div>

<hr>

<h2 align="center">📑 Contents</h2>

- [🚀 Quick Start](#quick-start)
- [✨ Features](#features)
- [📊 Smart Pace Indicator](#smart-pace-indicator)
- [📈 Progressive Burn-Rate](#progressive-burn-rate)
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

> **Migration note:** the `throughput` segment now renders a progressive burn-rate indicator — a rotating series of frames showing your current %/h burn plus deltas vs. 1h / 1d / 1w / 2w ago. Horizons unlock automatically as history accumulates, so day-0 shows just the raw rate and by week 2 you see the full comparison set. The segment key stays `throughput` for config compatibility.

<details>
<summary>Optional: create a config file</summary>

Create `~/.claude/claudeline.conf` to customize without env vars:

```bash
# ~/.claude/claudeline.conf
theme=nord
segments=context,git,pace,duration,tokens,throughput,model
no_network=0
```

Env vars override config file values. All keys are optional.

Available keys: `theme`, `segments`, `no_network`, `no_color`, `debug`, `debug_log`, `jsonl_cache_ttl`, `extra_usage_ttl`, `trend_window`, `trend_history_max_age`

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
Adapts to auto-compact setting — scales to 168K (ON) or 200K (OFF) with color gradient and emoji icons
</td>
<td align="center" width="33%">
<h3>Smart Pace Indicator</h3>
Dual-signal weekly pace (burn rate + pressure) with 8-tier emoji scale and velocity-based trend arrows
</td>
<td align="center" width="33%">
<h3>Progressive Burn-Rate</h3>
Current %/h plus rotating deltas vs. 1h / 1d / 1w / 2w ago — horizons unlock as history accumulates so it never goes blank
</td>
</tr>
<tr>
<td align="center">
<h3>Environmental Metrics</h3>
Rotating display of water, power, and data usage with dynamic unit scaling (drops → gallons, Wh → MWh)
</td>
<td align="center">
<h3>Fun Cost Conversions</h3>
34 normal + 7 absurd items with multi-unit scaling — see your session cost in joe's pizza slices or joey-chestnuts
</td>
<td align="center">
<h3>All-Time Tracking</h3>
Cumulative usage across all sessions from JSONL files, shown with 🏆 trophy on rotating cycle
</td>
</tr>
<tr>
<td align="center" width="33%">
<h3>Burst & Credit</h3>
8-level colored bar for 5-hour rate limit with reset countdown, plus overage credit tracking
</td>
<td align="center" width="33%">
<h3>Git Integration</h3>
Repo/branch with status indicators — unstaged, staged, ahead/behind, stash count
</td>
<td align="center" width="33%">
<h3>5 Built-in Themes + 1M Context</h3>
Vibey (default), Dark, Light, Nord, Gruvbox, NO_COLOR support, auto-detect extended 1M context windows
</td>
</tr>
</table>

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

**History retention:** Last 15 min dense (every ~30s), 15 min–4 h fine 10-min buckets (so the 1h burn-rate horizon has resolution), 4 h–15 d coarse 4-h buckets with a fine-bucketed band around 1 week ago, older than 15 d pruned. Same `.usage-history` file powers both the pace trend arrow and the progressive burn-rate indicator.

</details>

<hr>

<h2 align="center" id="progressive-burn-rate">📈 Progressive Burn-Rate</h2>

Answers *"am I burning through my weekly limit faster than I was before?"* in a single glance. The segment is designed to **always render something** given any usable history, and to **get more informative as data accumulates**.

**What it shows:** the current weekly-% per hour burn rate, plus deltas comparing that rate to what it was 1 hour / 1 day / 1 week / 2 weeks ago. At steady state the segment rotates through every 5 seconds:

```
1.2%/h   →   ↗ 1h +0.3%/h   →   ↘ 1d −0.2%/h   →   → 1w +0.0%/h   →   ↑ 2w +0.8%/h
```

**Horizons unlock as history accumulates** — no blank days on day zero:

| Elapsed since install | Segment shows |
|-----------------------|---------------|
| minute 1 | raw `1.2%/h` only |
| hour 2 | raw + `↘ 1h ±...` |
| day 2 | raw + 1h + `↘ 1d ±...` |
| day 8 | raw + 1h + 1d + `↘ 1w ±...` |
| day 15 | raw + 1h + 1d + 1w + `↘ 2w ±...` |

**Arrow colors** reuse the pace-trend palette so visual language is consistent:

| Delta (milli%/h) | Arrow | Meaning |
|---|---|---|
| ≥ +500 | `↑` hot | burning ~85% faster than the comparison window |
| ≥ +150 | `↗` warm | ~25% faster |
| ±150 | `→` stable | within sustainable-rate noise |
| ≤ −150 | `↘` cool | ~25% slower |
| ≤ −500 | `↓` cold | ~85% slower |

*(Sustainable rate ≈ 595 milli%/h, i.e. 100% per 7-day window.)*

**Reset-aware:** if all history samples are above the current weekly %, the segment treats the most recent pre-reset sample as the weekly reset point and extrapolates the raw rate forward — so within seconds of a weekly reset you see something like `33%/h` instead of a blank slot. Delta frames are suppressed during that fallback window since they'd compare an extrapolation to a real measurement.

Configurable via `BURN_RATE_WINDOW` (slope window, default 2h), `BURN_RATE_ROTATION_SECONDS` (frame rotation, default 5s), and per-horizon tolerances (`BURN_RATE_TOL_HR`, `BURN_RATE_TOL_DAY`, `BURN_RATE_TOL_WEEK`, `BURN_RATE_TOL_2WEEK`).

<hr>

<h2 align="center" id="burst--credit-indicators">💥 Burst & Credit Indicators</h2>

**💥 Burst** (5-hour rate limit) — colored bar mapped directly to API utilization %, only shown when > 0%.

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

At 75%+, a dimmed countdown shows minutes until the 5-hour window resets.

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

<details>
<summary><strong>Fun cost conversions (34 normal + 7 absurd)</strong></summary>

Many items have **multi-unit scaling** — they pick the appropriate unit based on cost:
- Joe's: bite ($0.33) → joe's ($4)
- Nathan's: bite ($1) → dog ($6) → joey-chestnut ($456)
- Starbucks: sip ($0.31) → starbucks ($5.50)
- Yuengling: sip ($0.37) → yuengling ($7) → keg ($200)

**Normal Items (34)** — shown in session + all-time normal:

| Emoji | Item | Price |
|-------|------|-------|
| ☕ | starbucks® | $5.50 |
| 🍕 | joe's® | $4 |
| 🌮 | tacorias® | $4.60 |
| 🍺 | yuenglings® | $7 |
| 🍔 | shackburgers® | $9 |
| 🍌 | chiquitas® | $0.30 |
| 🍿 | alamos® | $18 |
| 🎮 | gta6s® | $70 |
| 🧻 | charmins® | $1 |
| 🖍️ | crayolas® | $0.11 |
| 🥑 | haas® | $2 |
| 🥨 | auntie-annes® | $5 |
| 🦪 | blue-points® | $3.50 |
| 🌭 | nathans® | $6 |
| 🥯 | ess-a-bagels® | $4 |
| 🍣 | nami-noris® | $8 |
| 🥩 | lugers® | $65 |
| 🛢️ | exxon-valdezs® | $75 |
| 🥤 | big-gulps® | $2.50 |
| 🍝 | carbones® | $40 |
| 🦞 | redlobsters® | $30 |
| 🥗 | sweetgreens® | $15 |
| 🏋️ | equinoxs® | $260 |
| 🚴 | soulcycles® | $38 |
| 🍪 | levains® | $5 |
| 🌯 | chipotles® | $12 |
| 🧃 | juice-presses® | $11 |
| 🍟 | pommes-frites® | $9 |
| 🛴 | razors® | $35 |
| 🚋 | njts® | $5.90 |
| 🖱️ | magic-mice® | $99 |
| 📱 | iphones® | $999 |
| 🥐 | cronuts® | $7.75 |
| 🎵 | apple-musics® | $0.004 |

**Absurd Items (7)** — all-time only, decimal chasing 1:

| Emoji | Item | Price |
|-------|------|-------|
| 🚐 | sprinters® | $50,000 |
| 🧟 | thrillers® | $1,600,000 |
| 🏝️ | private-islands® | $18,000,000 |
| 🏪 | chipotle-franchises® | $1,000,000 |
| 🚁 | h130s® | $3,500,000 |
| ☕ | starbucks-franchises® | $315,000 |
| ☕ | starbucks-ceo-pays® | $57,000,000 |

</details>

<details>
<summary><strong>Fun power conversions (8 items)</strong></summary>

| Emoji | Item | Rate | Example |
|-------|------|------|---------|
| 🔌 | phone-charging | 5W | `🔌 833h phone-charging` |
| 💡 | hue-light® | 10W | `💡 417h hue-light®` |
| 🏠 | home-power | 1kW | `🏠 4.2h home-power` |
| 🏢 | 395-hudson® | 2MW | `🏢 7.5s 395-hudson®` |
| 🚗 | 4xe® | 1.45 mi/kWh | `🚗 6.0mi 4xe®` |
| ✈️ | a320neo® | 0.019 mi/kWh | `✈️ 421ft a320neo®` |
| 🪨 | coal | ~1 lb/kWh | `🪨 4.2 lbs coal` |
| ☢️ | reactor-output | 1GW | `☢️ 15ms reactor-output` |

Session displays phone through a320neo. Coal and reactor are all-time only.

</details>

<hr>

<h2 align="center" id="all-time-tracking">🏆 All-Time Tracking</h2>

Cumulative usage across all sessions by scanning JSONL files in `~/.claude/projects/` and `~/.config/claude/projects/`.

The 🏆 trophy indicates all-time totals. The 8-cycle rotation (10s each) shows:
- **Cycles 0-2, 4-6:** Session metrics (no trophy)
- **Cycle 3:** All-time normal with 🏆 — 15-item rotation: 10 fun cost + coal + reactor + tokens + cost + data
- **Cycle 7:** All-time absurd with 🏆 (e.g., `🏝️ 0.0015 private-islands® 🏆`)

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
| `CLAUDELINE_SEGMENTS=context,git,pace` | Show only listed segments (default: all). Available: `context`, `git`, `lines`, `pace`, `burst`, `duration`, `credit`, `tokens`, `metric`, `throughput`, `model`. `throughput` is the compatibility key for the progressive burn-rate indicator. |
| `BURN_RATE_WINDOW=7200` | Sliding window (seconds) for the burn-rate slope measurement at each horizon. Shorter is twitchier (default: 2h) |
| `BURN_RATE_ROTATION_SECONDS=5` | Seconds per frame when the burn-rate segment rotates through available horizons (raw / 1h / 1d / 1w / 2w) |
| `NO_COLOR=1` | Disables all color output ([spec](https://no-color.org)) |
| `CLAUDELINE_NO_NETWORK=1` | Disables all network access — the API call is skipped entirely |
| `CLAUDELINE_DEBUG=1` | Enables debug logging to `$TMPDIR/claudeline-statusline-debug.log` |
| `CLAUDELINE_DEBUG_LOG=/path` | Custom debug log path (requires `CLAUDELINE_DEBUG=1`) |
| `JSONL_CACHE_TTL=300` | JSONL cache lifetime in seconds (default: 300) |
| `EXTRA_USAGE_TTL=600` | Extra usage / credit cache lifetime in seconds (default: 600) |
| `TREND_WINDOW=900` | Trend arrow sample window in seconds (default: 900) |
| `TREND_HISTORY_MAX_AGE=1296000` | Max age for trend/burn-rate history entries in seconds (default: 15d, needed for the 2w comparison horizon) |

**Local data stored** in `~/.claude-usage.d/` (created with `chmod 700`):

| File | Purpose |
|------|---------|
| `.jsonl-cache` | Cached all-time token/cost totals (5-min TTL; stale values are served immediately while a background refresh runs) |
| `.jsonl-state` | Per-file JSONL scan state for incremental refreshes |
| `.refresh.lock.d/` | Lock directory to prevent concurrent background JSONL refreshes |
| `.usage-history` | Rolling 24h usage samples for trend arrows |
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
