# Claude Code Status Line

A cute, informative status line for Claude Code with rotating environmental metrics.

```
✨ ████░░░░░░  ·  myrepo/main*  ·  +50/-20  ·  👌→  ·  💥▃  ·  💳25%  ·  ⏱️ 45m
│  └────┬────┘     └─────┬─────┘   └───┬──┘   └─┬──┘  └─┬┘   └─┬──┘    └──┬───┘
│    context          repo/branch     lines    pace  burst  credit    duration
│    bar              + git status    changed  trend
└─ context icon (✨💭🧠🔥💾 or ✨💭💾🪫⚠️)

    73.5K/168K  ·  🍕 3 joe's®  ·  Opus 4.5
    └────┬────┘    └─────┬─────┘   └───┬───┘
      context         rotating       model
      tokens          metric
```

## Features

- **Context bar** adapts to your auto-compact setting (reads `~/.claude.json`):
  - **Auto-compact ON** (default): scales to 168K (the compression trigger, ~75% of 220K window)
  - **Auto-compact OFF**: scales to 220K (full context window)
  - 6-tier color gradient with mode-aware icons at high tiers:

  | Range | Color | Icon (auto-compact ON) | Icon (auto-compact OFF) |
  |-------|-------|----------------------|------------------------|
  | 0-17% | Cyan | ✨ | ✨ |
  | 18-34% | Lime | ✨ | ✨ |
  | 35-49% | Yellow | 💭 | 💭 |
  | 50-67% | Orange | 🧠 | 💾 compact hint |
  | 68-87% | Coral | 🔥 | 🪫 running low |
  | 88%+ | Red | 💾 about to auto-compact | ⚠️ hard wall ahead |
- **24-bit true color** palette (vibey 2025 colors)
- **Repo/branch** with git status indicators (`*`=unstaged, `+`=staged, `↑↓`=ahead/behind)
- **Lines changed** (+added/-removed)
- **Rotating environmental metrics** (10-cycle pattern, 10s each):
  - 💧 Standard water (cups, gallons, etc.)
  - ⚡ Standard power (watt-hours, kilowatt-hours)
  - 🔌💡🏠🏢🚗✈️🪨☢️ Fun power (phone, hue-light, home, 395-hudson, 4xe, a320neo, coal, reactor)
  - 🎟️ Token count, 💰 Cost, 📡 Data
  - ☕🍕🌮... Fun cost (34 normal items)
  - 🚐🧟🏝️🏪🚁☕ Absurd items (7 items, all-time only)
  - **Rotation:** 4 session → 1 all-time normal 🏆 → 4 session → 1 all-time absurd 🏆
- **Session duration**
- **Smart pace indicator** with trend arrows showing where you're headed:
  - **Pace:** ❄️🧊🙂👌♨️🥵🔥🚨 (8-tier scale based on actual/expected ratio)
  - **Trend:** ↑ heating fast, ↗ warming, → stable, ↘ cooling, ↓ cooling fast
  - Combined display: `👌→` (on pace, stable) or `🔥↑` (hot, getting hotter)
  - Trend uses **rolling window** with linear regression for accurate direction detection
  - At limit shows reset countdown: `🚨 -1.2d`
  - Alternates with raw % every 10th update
- **Burst indicator** (💥) with colored 8-level bar (▁▂▃▄▅▆▇█) for 5-hour rate limit, reset countdown at 88%+
- **Credit indicator** (💳) showing remaining overage balance, only when at weekly limit
- **Model name** (dimmed, at end)

## Environmental Impact

The rotating metrics help visualize the environmental cost of AI inference:

| Metric | Rate | Source |
|--------|------|--------|
| 💧 Water | 1 gal = 760k tokens | [arxiv:2304.03271](https://arxiv.org/pdf/2304.03271), updated 2026 |
| ⚡ Power | 1 kWh = 240k tokens | [arxiv:2505.09598](https://arxiv.org/html/2505.09598v1), updated 2026 |
| 💰 Cost | Built-in | Claude Code API |

### Dynamic Units

- **Water:** drops → teaspoons → tablespoons → fluid-ounces → cups → pints → quarts → gallons
- **Power:** watt-hours → kilowatt-hours → megawatt-hours
- **Tokens:** raw → k → m → b → t (scales with usage)

### Fun Cost Conversions

The cost metric rotates through fun items (NY/NJ 2026 prices). Values < 1 use 2 significant digits (e.g., 0.33, 0.1, 0.045).

Many items have **multi-unit scaling** - they pick the appropriate unit based on cost:
- Joe's: bite ($0.33) → joe's ($4)
- Nathan's: bite ($1) → dog ($6) → joey-chestnut ($456)
- Starbucks: sip ($0.31) → starbucks ($5.50)
- Yuengling: sip ($0.37) → yuengling ($7) → keg ($200)

**Normal Items (34)** - shown in session + all-time normal:

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

**Absurd Items (7)** - all-time only, decimal chasing 1:

| Emoji | Item | Price |
|-------|------|-------|
| 🚐 | sprinters® | $50,000 |
| 🧟 | thrillers® | $1,600,000 |
| 🏝️ | private-islands® | $18,000,000 |
| 🏪 | chipotle-franchises® | $1,000,000 |
| 🚁 | h130s® | $3,500,000 |
| ☕ | starbucks-franchises® | $315,000 |
| ☕ | starbucks-ceo-pays® | $57,000,000 |

Multi-unit items scale up through thresholds. So instead of `💰 $12.50`, you might see:
- `🍕 3 joe's®` or `🍕 6 bites @ joe's®`
- `🌭 2 dogs @ nathan's®` or `🌭 0.022 joey-chestnuts @ nathan's®`
- `🍺 2 yuenglings®` or `🍺 0.5 kegs @ yuengling®`

### Fun Power Conversions

The power metric shows equivalent device runtime, distance, or mass:

| Emoji | Item | Rate | Example |
|-------|------|------|---------|
| 🔌 | phone-charging | 5W | `🔌 833h phone-charging` |
| 💡 | hue-light® | 10W | `💡 417h hue-light®` |
| 🏠 | home-power | 1kW | `🏠 4.2h home-power` |
| 🏢 | 395-hudson® | 2MW | `🏢 7.5s 395-hudson®` |
| 🚗 | 4xe® | 1.45 mi/kWh | `🚗 6.0mi 4xe®` |
| ✈️ | a320neo® | 0.019 mi/kWh | `✈️ 421ft a320neo®` |
| 🪨 | coal | ~1 lb/kWh | `🪨 4.2 lbs coal` (scales to tons at 2000 lbs) |
| ☢️ | reactor-output | 1GW | `☢️ 15ms reactor-output` |

Session displays phone, hue-light, home, 395-hudson, 4xe, and a320neo. Coal and reactor are all-time only.

Each terminal window shows different metrics and fun items simultaneously (based on time), so the display rotates through all options.

## All-Time Tracking

The statusline tracks cumulative usage across all sessions by scanning JSONL files in `~/.claude/projects/`.

The 🏆 trophy indicates all-time totals. The 10-cycle rotation shows:
- **Cycles 0-3, 5-8:** Session metrics (no trophy)
- **Cycle 4:** All-time normal with 🏆 — 15-item rotation: 10 fun cost items + coal + reactor + tokens + cost + data
- **Cycle 9:** All-time absurd item with 🏆 (e.g., `🏝️ 0.0015 private-islands® 🏆`)

## Smart Pace Indicator

Compares your actual weekly usage against where you *should* be based on time elapsed in the 7-day rolling window. Uses the Anthropic OAuth API to fetch real-time usage data.

**The math:** Two signals, take the worse one:
- **Burn rate** (velocity): `(pct / days_elapsed) × 7 / 100` — how fast you're going
- **Pressure** (position): `days_remaining / budget_remaining_in_days` — remaining runway

`effective = max(burn_rate, pressure)`

Both signals agree on over/under pace (`> 1.0` = over, `< 1.0` = under), but pressure amplifies urgency when budget is thin. For example, at 91% on Monday 8pm with reset Thursday 1pm: burn rate is 1.48 (🥵) but pressure is 4.29 — you have 9% left for 2.7 days (🚨).

**Pace emoji** (where you are):

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

**Trend arrow** (where you're headed):

Tracks **usage% velocity** - how fast you're burning tokens compared to the sustainable rate (100% / 7 days ≈ 0.01%/min).

| Velocity | Arrow | Meaning |
|----------|-------|---------|
| > 3x sustainable | ↑ | Heating fast (burning tokens quickly) |
| 1.5-3x sustainable | ↗ | Warming up |
| 0.5-1.5x sustainable | → | Stable (on pace) |
| 0.1-0.5x sustainable | ↘ | Cooling down (light usage) |
| < 0.1x sustainable | ↓ | Cooling fast (idle) |

**Why velocity-based?** Unlike ratio-based tracking, this is equally responsive regardless of where you are in the week. Hammering Claude will show ↗/↑, taking a break shows ↘/↓.

**History retention:**
- Last 15 minutes: dense samples (every ~30 sec)
- 15 min to 24 hours: sparse anchors (1 per 4-hour block)
- Older than 24 hours: pruned

Combined display: `👌→` (on pace, stable) or `🔥↑` (hot, getting hotter)

When at 100% limit, shows time until reset: `🚨 -1.2d`

The display alternates between emoji+arrow (9 cycles) and raw percentage (1 cycle) every 10 seconds.

## Burst & Credit Indicators

**💥 Burst** (5-hour rate limit) - Colored bar mapped directly to API utilization %, only shown when > 0%

| Range | Bar | Color |
|-------|-----|-------|
| 1-12% | ▁ | cyan |
| 13-24% | ▂ | teal |
| 25-37% | ▃ | green |
| 38-49% | ▄ | yellow |
| 50-62% | ▅ | orange |
| 63-74% | ▆ | red |
| 75-87% | ▇ -135m | magenta + reset countdown |
| 88%+ | █ -90m | bright magenta + reset countdown |

At 75%+, a dimmed countdown shows minutes until the 5-hour window resets.

**💳 Credit** (overage balance) - Only shown when weekly usage hits 100%. Displays remaining dollars and % of monthly cap: `💳$465/$500 (7%)`

## Installation

**One command:**

```bash
curl -fsSL https://raw.githubusercontent.com/s-b-e-n-s-o-n/claudeline/main/install.sh | bash
```

Then restart Claude Code. That's it.

<details>
<summary>Manual installation</summary>

1. Copy the script to your Claude config:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/s-b-e-n-s-o-n/claudeline/main/statusline.sh -o ~/.claude/statusline.sh
   chmod +x ~/.claude/statusline.sh
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

## Performance

Typical execution time with warm caches:

| Scenario | Time |
|----------|------|
| Warm caches (typical) | ~250ms |
| Best case | ~190ms |
| Cold API cache | +700ms (network) |
| Cold JSONL cache | +2.5s (file scan) |

Caching keeps things fast:
- **API cache:** 60 seconds (usage data from Anthropic)
- **JSONL cache:** 5 minutes (all-time totals from project files)

The script optimizes subprocess calls - the trend velocity calculation uses a single awk call instead of 10+ shell commands (head, tail, wc, grep, sort, bc, etc.).

## Requirements

- `jq` (for JSON parsing)
- `bc` (for cost calculation)
- `git` (for branch detection)
- `perl` (for JSONL parsing)
