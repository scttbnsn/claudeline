#!/usr/bin/env bash
# Probe which usage data sources this machine can actually reach.
#
# Prints account context, credential state, and the response shape from the two
# endpoints that carry usage numbers. Never prints tokens -- only whether they
# exist, where they came from, and when they expire.
#
#   bash scripts/probe-usage-sources.sh

set -uo pipefail

API_BASE="https://api.anthropic.com"
BETA_HEADER="oauth-2025-04-20"
USER_AGENT="claude-code/2.1.0"

for tool in jq curl; do
    command -v "$tool" >/dev/null 2>&1 || { printf 'need %s on PATH\n' "$tool" >&2; exit 1; }
done

rule() { printf '\n=== %s ===\n' "$1"; }

# ---------------------------------------------------------------- account ----
rule "account (~/.claude.json)"
config="$HOME/.claude.json"
if [ -r "$config" ]; then
    jq -r '.oauthAccount // {} |
        "emailAddress:      \(.emailAddress // "<none>")",
        "organizationUuid:  \(.organizationUuid // "<none>")",
        "organizationName:  \(.organizationName // "<none>")",
        "organizationType:  \(.organizationType // "<none>")",
        "billingType:       \(.billingType // "<none>")",
        "seatTier:          \(.seatTier // "<none>")",
        "organizationRole:  \(.organizationRole // "<none>")",
        "rateLimitTier:     \(.organizationRateLimitTier // "<none>")"' "$config"
    ORG_UUID=$(jq -r '.oauthAccount.organizationUuid // empty' "$config")
else
    printf 'not readable: %s\n' "$config"
    ORG_UUID=""
fi

# ------------------------------------------------------------ credentials ----
rule "oauth credentials"
TOKEN=""

read_creds() {
    # $1 = raw credentials JSON, $2 = label. Sets TOKEN/CRED_SOURCE on success.
    local raw=$1 label=$2 token expires refresh
    token=$(printf '%s' "$raw" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
    [ -n "$token" ] || return 1
    expires=$(printf '%s' "$raw" | jq -r '.claudeAiOauth.expiresAt // empty' 2>/dev/null)
    refresh=$(printf '%s' "$raw" | jq -r 'if (.claudeAiOauth.refreshToken // "") == "" then "no" else "yes" end' 2>/dev/null)
    printf 'source:            %s\n' "$label"
    printf 'access token:      present (%s chars)\n' "${#token}"
    printf 'refresh token:     %s\n' "$refresh"
    if [ -n "$expires" ]; then
        local secs now
        secs=$((expires / 1000))
        now=$(date +%s)
        printf 'expiresAt:         %s' "$(date -r "$secs" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || echo "$secs")"
        if [ "$secs" -lt "$now" ]; then
            printf '  <-- EXPIRED %s days ago\n' "$(( (now - secs) / 86400 ))"
        else
            printf '  (valid)\n'
        fi
    fi
    printf 'scopes:            %s\n' \
        "$(printf '%s' "$raw" | jq -r 'if (.claudeAiOauth.scopes // null) == null then "<not recorded locally>" else (.claudeAiOauth.scopes | join(" ")) end' 2>/dev/null)"
    TOKEN=$token
    return 0
}

if [ "$(uname -s)" = "Darwin" ]; then
    if kc=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null); then
        read_creds "$kc" "macOS keychain" || printf 'keychain entry present but has no accessToken\n'
    else
        printf 'no keychain entry for "Claude Code-credentials"\n'
    fi
fi

if [ -z "$TOKEN" ]; then
    cred_file="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"
    if [ -r "$cred_file" ]; then
        read_creds "$(cat "$cred_file")" "$cred_file" || printf 'credentials file has no accessToken\n'
    else
        printf 'no credentials file at %s\n' "$cred_file"
    fi
fi

# --------------------------------------------------------------- env auth ----
rule "auth-related environment"
found=0
for var in ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_OAUTH_TOKEN \
           CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX ANTHROPIC_BEDROCK_BASE_URL \
           ANTHROPIC_VERTEX_PROJECT_ID CLAUDE_CONFIG_DIR; do
    if [ -n "${!var:-}" ]; then
        case "$var" in
            *KEY|*TOKEN) printf '%s = <set, %s chars>\n' "$var" "${#var}" ;;
            *)           printf '%s = %s\n' "$var" "${!var}" ;;
        esac
        found=1
    fi
done
[ "$found" -eq 1 ] || printf 'none set (plain claude.ai OAuth session)\n'

# --------------------------------------------------------------- endpoints ---
probe() {
    # $1 = label, $2 = url
    local label=$1 url=$2 body status
    printf '\n--- %s\n%s\n' "$label" "$url"
    if [ -z "$TOKEN" ]; then
        printf 'skipped: no access token to present\n'
        return
    fi
    body=$(curl -sS --max-time 15 -w '\n%{http_code}' \
        -H "Authorization: Bearer $TOKEN" \
        -H "anthropic-beta: $BETA_HEADER" \
        -H "User-Agent: $USER_AGENT" \
        "$url" 2>&1)
    status=$(printf '%s' "$body" | tail -1)
    body=$(printf '%s' "$body" | sed '$d')
    printf 'HTTP %s\n' "$status"
    if [ "$status" = "200" ]; then
        printf 'top-level keys: %s\n' "$(printf '%s' "$body" | jq -r 'keys | join(", ")' 2>/dev/null)"
        printf '\nextra_usage (the $ spend limit):\n'
        printf '%s' "$body" | jq '.extra_usage // "<absent>"' 2>/dev/null
        printf '\nfive_hour / seven_day:\n'
        printf '%s' "$body" | jq '{five_hour, seven_day}' 2>/dev/null
        printf '\nlimits[] kinds (per-model windows live here):\n'
        printf '%s' "$body" | jq -r '(.limits // []) | map("\(.kind) \(.group // "") \(.scope.model.display_name // "") \(.percent)%") | join("\n") // "<absent>"' 2>/dev/null
    else
        printf '%s\n' "$body" | head -5
    fi
}

rule "endpoint probes"
probe "Claude Code / Orca source" "$API_BASE/api/oauth/usage"
if [ -n "$ORG_UUID" ]; then
    probe "desktop app source" "$API_BASE/api/organizations/$ORG_UUID/usage"
else
    printf '\n--- desktop app source\nskipped: no organizationUuid in ~/.claude.json\n'
fi

rule "verdict"
printf 'If extra_usage came back with monthly_limit + used_credits, claudeline can\n'
printf 'show the spend percentage. used_credits and monthly_limit are in CENTS.\n'
printf 'If both probes 401/403, the credentials need a refresh or lack user:profile.\n'
