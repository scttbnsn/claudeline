# Claude Code Status Line

A cute, informative status line for Claude Code with rotating environmental metrics.

```
✨ ████░░░░░░  ·  myrepo/main*  ·  +50/-20  ·  👌→  ·  💥▃  ·  💳25%  ·  ⏱️ 45m
│  └────┬────┘     └─────┬─────┘   └───┬──┘   └─┬──┘  └─┬┘   └─┬──┘    └──┬───┘
│    context          repo/branch     lines    pace  burst  credit    duration
│    bar              + git status    changed  trend
└─ context icon (✨💭🧠💾)

    73.5K/150K  ·  🍕 3 joe's®  ·  Opus 4.5
    └────┬────┘    └─────┬─────┘   └───┬───┘
      context         rotating       model
      tokens          metric
```

## Features

- **Context bar** scaled to auto-compact threshold (~75% of context window):
  - ✨ Green (0-29%) - plenty of room
  - 💭 Yellow (30-59%) - getting cozy
  - 🧠 Orange (60-89%) - consider compacting
  - 💾 Red (90%+) - about to auto-compact
- **24-bit true color** palette (vibey 2025 colors)
- **Repo/branch** with git status indicators (`*`=unstaged, `+`=staged, `↑↓`=ahead/behind)
- **Lines changed** (+added/-removed)
- **Rotating environmental metrics** (10-cycle pattern, 10s each):
  - 💧 Standard water (cups, gallons, etc.)
  - 🪣🛁🏊 Fun water (bucket, bathtub, pool)
  - ⚡ Standard power (watt-hours, kilowatt-hours)
  - 🔌💡🏠🚗🏢🪨☢️ Fun power (phone, hue-light, home, 4xe, 395-hudson, coal, reactor)
  - 🎟️ Token count, 💰 Cost, 📡 Data
  - ☕🍕🌮... Fun cost (40 normal items)
  - 🚐🧟🏝️🚢🏪💀🚁✈️ Absurd items (8 items, all-time only)
  - **Rotation:** 4 session → 1 all-time normal 🏆 → 4 session → 1 all-time absurd 🏆
- **Session duration**
- **Smart pace indicator** with trend arrows showing where you're headed:
  - **Pace:** ❄️🧊🙂👌♨️🥵🔥🚨 (8-tier scale based on actual/expected ratio)
  - **Trend:** ↑ heating fast, ↗ warming, → stable, ↘ cooling, ↓ cooling fast
  - Combined display: `👌→` (on pace, stable) or `🔥↑` (hot, getting hotter)
  - Trend uses **rolling window** with linear regression for accurate direction detection
  - At limit shows reset countdown: `🚨 -1.2d`
  - Alternates with raw % every 10th update
- **Burst indicator** (💥) with colored 8-level bar (▁▂▃▄▅▆▇█) for 5-hour rate limit, only when > 0%
- **Credit indicator** (💳) showing monthly extra usage percentage
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

The cost metric rotates through fun items (NY/NJ 2026 prices). Values < 1 snap to easy fractions (1/2, 1/3, 1/4, 1/5, 1/10, 1/20, etc.).

Many items have **multi-unit scaling** - they pick the appropriate unit based on cost:
- Joe's: bite ($0.33) → slice ($4) → pie ($32)
- Nathan's: bite ($1) → dog ($6) → joey-chestnut ($456)
- Starbucks: sip ($0.31) → venti ($5.50) → franchise ($315K) → ceo-pay ($57M)
- Blood: drop ($0.02) → tsp → tbsp → oz → cup → pint → gallon ($1,600)

**Normal Items (40)** - shown in session + all-time normal:

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
| 📚 | strands® | $17 |
| 🧻 | charmins® | $1 |
| 🖍️ | crayolas® | $0.11 |
| 🥑 | haas® | $2 |
| 🍦 | ample-hills® | $7 |
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
| 🥜 | nuts4nuts® | $5 |
| 📰 | nytimes® | $7 |
| 🌯 | chipotles® | $12 |
| 🧃 | juice-presses® | $11 |
| 🍟 | pommes-frites® | $9 |
| 🛴 | razors® | $35 |
| 🚋 | njts® | $5.90 |
| 🖱️ | magic-mice® | $99 |
| 📱 | iphones® | $999 |
| 🩸 | pints-o-blood® | drop→tsp→tbsp→oz→cup→pint→gallon |
| 🧸 | paddingtons® | $30 |
| 🥐 | cronuts® | $7.75 |
| 🎵 | apple-music® | $0.004/stream |

**Absurd Items (8)** - all-time only, fraction chasing 1:

| Emoji | Item | Price |
|-------|------|-------|
| 🚐 | sprinters® | $50,000 |
| 🧟 | thrillers® | $1,600,000 |
| 🏝️ | private-islands® | $18,000,000 |
| 🚢 | supertankers® | $150,000,000 |
| 🏪 | chipotle-franchises® | $1,000,000 |
| 🩸 | body of blood® | $2,000 |
| 🚁 | h130s® | $3,500,000 |
| ✈️ | g550s® | $60,000,000 |

Multi-unit items scale up through thresholds. So instead of `💰 $12.50`, you might see:
- `🍕 3 slices @ joe's®` or `🍕 1.5 pies @ joe's®`
- `🌭 2 dogs @ nathan's®` or `🌭 1/10th joey-chestnut @ nathan's®`
- `🩸 5 cups @ blood®` or `🩸 1 pint @ blood®`

### Fun Water Conversions

The water metric also rotates through relatable comparisons:

| Emoji | Item | Tokens |
|-------|------|--------|
| 🪣 | buckets (5 gal) | 3.8M |
| 🛁 | bathtubs (50 gal) | 38M |
| 🏊 | swimming-pools (20k gal) | 15B |

So instead of `💧 2.5 gallons`, you might see `🪣 1/2 bucket` or `🛁 1/10th bathtub`!

### Fun Power Conversions

The power metric shows equivalent device runtime (or mass for coal):

| Emoji | Item | Power | Example |
|-------|------|-------|---------|
| 🔌 | phone-charging | 5W | `🔌 833h phone-charging` |
| 💡 | hue-light® | 10W | `💡 417h hue-light®` |
| 🏠 | home-power | 1kW | `🏠 4.2h home-power` |
| 🚗 | 4xe® | 7kW | `🚗 36m 4xe®` |
| 🏢 | 395-hudson® | 2MW | `🏢 7.5s 395-hudson®` |
| 🪨 | coal | ~1 lb/kWh | `🪨 4.2 lbs coal` |
| ☢️ | reactor-output | 1GW | `☢️ 15ms reactor-output` |

This shows how long a device would run (or generate) the energy your session consumed. Coal is special - it shows mass burned instead of time.

Each terminal window shows different metrics and fun items simultaneously (based on time), so the display rotates through all options.

## All-Time Tracking

The statusline tracks cumulative usage across all sessions by scanning JSONL files in `~/.claude/projects/`.

The 🏆 trophy indicates all-time totals. The 10-cycle rotation shows:
- **Cycles 0-3, 5-8:** Session metrics (no trophy)
- **Cycle 4:** All-time normal item with 🏆 (e.g., `🍕 39 joe's® 🏆`)
- **Cycle 9:** All-time absurd item with 🏆 (e.g., `🏝️ 1/100Kth private-island® 🏆`)

## Smart Pace Indicator

Compares your actual weekly usage against where you *should* be based on time elapsed in the 7-day rolling window. Uses the Anthropic OAuth API to fetch real-time usage data.

**The math:** `ratio = actual% / expected%` where `expected = (days_elapsed / 7) * 100`

For example, if you're at 27% usage with 1.2 days elapsed:
- Expected: (1.2/7) × 100 = 17%
- Ratio: 27/17 = 1.58 → 🔥 (running hot)

**Pace emoji** (where you are):

| Ratio | Emoji | State |
|-------|-------|-------|
| < 0.3 | ❄️ | Way under pace |
| 0.3-0.6 | 🧊 | Under pace |
| 0.6-0.8 | 🙂 | Comfortable |
| 0.8-1.1 | 👌 | On pace |
| 1.1-1.3 | ♨️ | Slightly hot |
| 1.3-1.5 | 🥵 | Hot |
| 1.5-2.0 | 🔥 | Very hot |
| ≥ 2.0 | 🚨 | Critical |

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

**💥 Burst** (5-hour rate limit) - Colored bar indicator, only shown when > 0%

| Range | Bar | Color |
|-------|-----|-------|
| 1-12% | ▁ | cyan |
| 13-25% | ▂ | teal |
| 26-37% | ▃ | green |
| 38-50% | ▄ | yellow |
| 51-62% | ▅ | orange |
| 63-75% | ▆ | red |
| 76-87% | ▇ | magenta |
| 88%+ | █ | bright magenta |

**💳 Credit** (monthly extra usage) - Only shown when > 0%

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
