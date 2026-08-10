# Handoff

Where things stand and what's still open. Written 2026-08-10.

## Current shape

```
🌱 █░░░░░░░░░  ·  claudeline/main*  ·  🔥↓  ·  💥▁
   74.3K/400K  ·  Opus 5  ·  🧠high  ·  ⏱️ 5m
```

The design rule behind the recent cuts: claudeline is the **glance** layer.
Orca sits a little further down the screen and shows the actual numbers, so
anything claudeline duplicated got removed. The context token count stayed
because it's the one figure Orca doesn't show and the one you act on.

Claudeline now makes no network calls at all.

## Open: showing enterprise usage

The goal is a segment showing spend against an enterprise limit, e.g. the
`$1,675 of $2,500 / 67%` the desktop app displays.

### What the data looks like

It's the `extra_usage` object on the usage response:

```json
{
  "extra_usage": {
    "is_enabled": true,
    "monthly_limit": 250000,
    "used_credits": 200000,
    "utilization": 67,
    "currency": "USD",
    "disabled_reason": null
  }
}
```

Two things to get right:

- **Values are in cents.** The desktop app divides by 100 before formatting
  as currency. `250000` is $2,500.
- **`monthly_limit: null` means unlimited**, not zero. Claude Code renders
  the word "Unlimited" rather than a percentage in that case.

This schema was read independently out of the Claude Code 2.1.226 binary and
the Claude Desktop bundle. They agree field for field.

### Where to get it

| Endpoint | Auth | Used by |
|---|---|---|
| `GET /api/oauth/usage` | `Authorization: Bearer` + `anthropic-beta: oauth-2025-04-20` | Claude Code, Orca |
| `GET /api/organizations/{org_uuid}/usage?skip_spend=1` | web session cookie | Claude Desktop |

The org endpoint returns 403 `account_session_invalid` for a bearer token, so
it isn't reachable from a shell script. **`/api/oauth/usage` is the one to
use.** Its `limits[]` array also carries per-model weekly windows — Orca finds
Fable by matching `kind == "weekly_scoped"` and
`scope.model.display_name == "fable"`.

Claudeline used to parse `.extra_usage.utilization` from this exact endpoint.
That went out with the credit segment in `refactor(statusline)!`. Restoring it
is a revert plus reading `monthly_limit`/`used_credits` for the dollar figure.

### Blocker 1: the access token expires

The keychain token (`security find-generic-password -s "Claude Code-credentials"`)
expires and nothing in claudeline renews it. It was 6 days stale during this
work, which is why both probes returned 401.

Orca refreshes it:

- `POST https://platform.claude.com/v1/oauth/token`
- client id `9d1c250a-e61b-44d9-88ed-5944d1962f5e`
- 5 minute expiry buffer

**Hazard, untested on purpose:** the refresh response can rotate the refresh
token. A second independent writer racing Orca or Claude Code could invalidate
the credential and log you out of Claude Code. Decide between read-only,
refresh-and-write-back, and refresh-without-persist before implementing. This
is the reason no refresh code exists yet.

### Blocker 2: the work machine is unverified

Run this there:

```
bash scripts/probe-usage-sources.sh
```

It prints account type, credential source and expiry, auth env vars, and both
endpoint responses. It never prints tokens.

The unknown it resolves: whether that seat's credentials carry the
`user:profile` scope. Without it `/api/oauth/usage` returns 403 and there is
no path to the number from a script. Note that env-var and setup-token
sessions default to `user:inference` only.

## Why pace and burst are blank on a no-subscription seat

Not a bug in claudeline or Orca. Claude Code's own schema:

> `rate_limits_available`: False when plan rate limits do not apply (API key,
> Bedrock, Vertex, or missing profile scope) — rate_limits will be null.

No subscription means no 5-hour or weekly windows exist, so there's no
percentage to render. Usage-based billing has monthly **spend caps** and
per-minute **rate limits** (RPM/ITPM/OTPM) instead. Claude Code parses only
the `anthropic-ratelimit-unified-*` headers, which are the subscription
system; it never captures the API-mode headers, so nothing downstream can
show them.

On such a machine the meaningful signal is spend rate, which is what the
deleted JSONL cost tracking computed from local transcripts with no auth at
all. If that's wanted back, it's in git history rather than gone.

## Payload fields not currently read

Found while capturing a live status line payload: `fast_mode`, `session_name`,
`output_style`, `exceeds_200k_tokens`. `fast_mode` looks like it belongs next
to the model.

Confirmed **not** in the payload: `model_scoped`, `subscription_type`,
`rate_limits_available`, anything Fable. Those live on other Claude Code
surfaces. The status line gets `five_hour` and `seven_day` only.
