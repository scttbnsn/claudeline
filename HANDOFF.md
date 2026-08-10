# Handoff

State of the spend segment and what's still open. Written 2026-08-10, after
`feat(statusline): add opt-in enterprise spend segment` shipped.

## What shipped

An opt-in `spend` segment showing usage against a monthly enterprise cap.

```
🌱 ██░░░░░░░░  ·  claudeline/main*  ·  Opus 5  ·  🧠high  ·  💳 69%
  109.9K/400K  ·  ⏱️ 1h1m
```

- Percentage only. An earlier draft rendered `$1,675 of $2,500 / 67%` in the
  style of the desktop app; that was cut in favour of the percentage alone.
- `💰` by default, configurable with `spend_icon` / `CLAUDELINE_SPEND_ICON`.
- `💀` appended at 100% or when `spend_limit_reached` flips.
- `💰 ∞` when `monthly_limit` is null, which means unlimited rather than zero.
- Renders nothing when the feature is disabled, the token is missing or
  expired, or the response isn't 200.

Config keys: `spend` (off by default), `spend_icon`, `extra_usage_ttl`,
`no_network`. All read from `~/.claude/claudeline.conf`.

Layout changed with it: model and effort moved up to line 1, pace and burst
down to line 2.

### Colour scale

Its own 11-band scale in `SPEND_BAND_*`, one colour per 10%, deliberately not
the burst scale. Burst splits 0–100 into eighths and hits red at 64%, which is
correct for a five-hour rate-limit window and wrong for a monthly budget.

```
0-9 cyan · 10-19 teal · 20-29 green · 30-39 lime · 40-49 yellow
50-59 orange · 60-69 coral · 70-79 red · 80-89 hot pink
90-99 magenta · 100+ white-hot
```

`BURST_BAND_*` is untouched and still drives the burst indicator.

## Constraints to preserve

**The token is read-only, on purpose.** The keychain entry is read, never
written, and no refresh is attempted. Claude Code refreshes it already, and the
refresh response can rotate the refresh token — a second writer racing it can
invalidate the credential and log the user out. If the segment turns out to
blank often in practice, that's the thing to revisit, and the choice is between
refresh-without-persist and refresh-and-write-back. Don't reach for either
without deciding deliberately.

**The fetch never sits on the render path.** Cached with a 10-minute TTL,
serve-stale-while-revalidate, mkdir lock so concurrent panes don't stampede.
The status line runs on every update; a synchronous call is not acceptable.

**`CLAUDELINE_NO_NETWORK` is a hard kill switch.** `refactor(statusline)!`
claimed claudeline made no network calls at all and deleted the flag. This
brought back one optional call and the flag with it. Its check inside
`lib/statusline_usage.sh` has to stay a self-contained inline `case`, not a
call to `is_truthy_flag` — the no-network test sources the lib standalone.

**This repo is public.** No real spend figures, org identifiers, or employer
names in tests, fixtures, or comments. Test values are synthetic.

## Open threads

### 1. Pace-aware colouring

The scale colours by how much of the cap is gone, not by whether spend is ahead
of pace. 69% on the 10th of the month is very different from 69% on the 25th,
and the current scale can't tell them apart.

Blocked on not knowing whether the usage payload carries a cycle reset date.
Nobody has looked. `bash scripts/probe-usage-sources.sh` dumps the response;
check for a reset or period-start field on `extra_usage` or alongside it. If one
exists, compare elapsed fraction of the cycle against `utilization` and colour
on the gap. If not, this isn't buildable from this endpoint.

### 2. The `spend` object

The usage response has a top-level `spend` object sitting next to
`extra_usage`. It has never been inspected. It might be a better source than
`extra_usage`, or carry the reset date thread 1 needs. One look would settle it.

Other top-level keys present and unused: `seven_day_opus`, `seven_day_sonnet`,
`seven_day_cowork`, `seven_day_oauth_apps`, `seven_day_omelette`,
`member_dashboard_available`, and several codenamed ones (`amber_ladder`,
`cinder_cove`, `nimbus_quill`, `tangelo`, `omelette_promotional`,
`iguana_necktie`).

### 3. Payload fields the status line ignores

`fast_mode`, `session_name`, `output_style`, `exceeds_200k_tokens`. `fast_mode`
looks like it belongs next to the model segment.

Confirmed **not** in the status line payload: `model_scoped`,
`subscription_type`, `rate_limits_available`, anything Fable. Those live on
other Claude Code surfaces. The payload carries `five_hour` and `seven_day`
only.

## Notes for whoever picks this up

**Run the suite twice.** CI runs Linux and macOS; a lot of this code branches on
`$OSTYPE`. A macOS-only test passed locally and failed CI for exactly that
reason.

```
for f in tests/*.sh; do bash "$f" || exit 1; done
for f in tests/*.sh; do OSTYPE=linux-gnu bash "$f" || exit 1; done
```

**Update `install.sh` checksums** for every shipped file you change. lefthook's
`sha256-check` and the install tests both fail loudly otherwise.

**`install.sh` pulls from GitHub `main`**, so it can't install uncommitted work.
To test locally, copy `statusline.sh` and `lib/*.sh` into `~/.claude/`
directly. The status line only reloads in a new session.

**Enterprise usage-based seats have no rate-limit windows.** `five_hour`,
`seven_day` and `limits[]` come back null or empty, so pace and burst render
nothing and line 2 is short. That's the documented behaviour of
`rate_limits_available`, not a bug.
