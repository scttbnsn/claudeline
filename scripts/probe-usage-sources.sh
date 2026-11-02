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
UNSAFE_AUTH_SEEN=0

read_creds() {
    # $1 = raw credentials JSON, $2 = label. Sets TOKEN/CRED_SOURCE on success.
    local raw=$1 label=$2 access_credential="" expires="" refresh=""
    local secs=0 now=0 now_ms=0

    if ! printf '%s' "$raw" | jq -e '
        .claudeAiOauth.accessToken
        | type == "string" and length > 0' >/dev/null 2>&1; then
        return 1
    fi
    if ! printf '%s' "$raw" | jq -e '
        .claudeAiOauth.accessToken
        | test("[[:cntrl:]]") | not' >/dev/null 2>&1; then
        UNSAFE_AUTH_SEEN=1
        return 1
    fi
    access_credential=$(printf '%s' "$raw" | jq -r '.claudeAiOauth.accessToken' 2>/dev/null) || return 1
    expires=$(printf '%s' "$raw" | jq -er '
        (.claudeAiOauth.expiresAt // "")
        | if type == "string" or type == "number" then tostring
          else error("invalid expiry shape")
          end' 2>/dev/null) || return 1
    refresh=$(printf '%s' "$raw" | jq -r '
        if (.claudeAiOauth.refreshToken // "") == "" then "no" else "yes" end' 2>/dev/null) || return 1
    if [ -n "$expires" ] && ! [[ "$expires" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    if [[ "$expires" =~ ^[0-9]+$ ]]; then
        now=$(date +%s)
        now_ms=$((now * 1000))
        [ "$expires" -gt "$now_ms" ] || return 1
        secs=$((10#$expires / 1000))
    fi

    printf 'source:            %s\n' "$label"
    printf 'access token:      present (%s chars)\n' "${#access_credential}"
    printf 'refresh token:     %s\n' "$refresh"
    if [ -n "$expires" ]; then
        printf 'expiresAt:         %s' "$(date -r "$secs" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || echo "$secs")"
        printf '  (valid)\n'
    fi
    printf 'scopes:            %s\n' \
        "$(printf '%s' "$raw" | jq -r 'if (.claudeAiOauth.scopes // null) == null then "<not recorded locally>" else (.claudeAiOauth.scopes | join(" ")) end' 2>/dev/null)"
    TOKEN=$access_credential
    return 0
}

decode_keychain_value() {
    local raw=$1 compact="" decoded=""

    compact=$(printf '%s' "$raw" | tr -d '[:space:]')
    if [[ -z "$compact" || ! "$compact" =~ ^[0-9a-fA-F]+$ ]]; then
        printf '%s' "$raw"
        return 0
    fi
    [ $(( ${#compact} % 2 )) -eq 0 ] || return 1
    command -v xxd >/dev/null 2>&1 || return 1
    decoded=$(printf '%s' "$compact" | xxd -r -p 2>/dev/null) || return 1
    printf '%s' "$decoded"
}

keychain_service="Claude Code-credentials"
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
    if command -v shasum >/dev/null 2>&1; then
        config_digest=$(printf '%s' "$CLAUDE_CONFIG_DIR" | shasum -a 256 2>/dev/null | cut -c1-8)
    elif command -v sha256sum >/dev/null 2>&1; then
        config_digest=$(printf '%s' "$CLAUDE_CONFIG_DIR" | sha256sum 2>/dev/null | cut -c1-8)
    else
        config_digest=""
    fi
    if [[ "${config_digest:-}" =~ ^[0-9a-f]{8}$ ]]; then
        keychain_service="$keychain_service-$config_digest"
    else
        printf 'no SHA-256 hasher; using the unsuffixed keychain service\n'
    fi
fi

if [ "$(uname -s)" = "Darwin" ]; then
    printf 'keychain service:  %s\n' "$keychain_service"
    keychain_found=0
    for keychain_account in "${USER:-}" ""; do
        if [ -n "$keychain_account" ]; then
            account_label="-a \$USER item"
            kc=$(security find-generic-password -s "$keychain_service" -a "$keychain_account" -w 2>/dev/null) || continue
        else
            account_label="account-less lookup"
            kc=$(security find-generic-password -s "$keychain_service" -w 2>/dev/null) || break
        fi
        keychain_found=1
        if decoded=$(decode_keychain_value "$kc"); then
            if read_creds "$decoded" "macOS keychain"; then
                printf 'keychain lookup:   %s\n' "$account_label"
                break
            fi
            printf 'keychain entry present (%s) but has no usable access credential\n' "$account_label"
        else
            printf 'keychain entry present (%s) but could not be decoded\n' "$account_label"
        fi
    done
    if [ "$keychain_found" -eq 0 ]; then
        printf 'no keychain entry for "%s"\n' "$keychain_service"
    fi
fi

if [ -z "$TOKEN" ]; then
    cred_file="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"
    if [ -r "$cred_file" ]; then
        read_creds "$(cat "$cred_file")" "$cred_file" || printf 'credentials file has no usable access credential\n'
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
            *KEY|*TOKEN)
                secret_value=${!var}
                printf '%s = <set, %s chars>\n' "$var" "${#secret_value}"
                ;;
            *)           printf '%s = %s\n' "$var" "${!var}" ;;
        esac
        found=1
    fi
done
[ "$found" -eq 1 ] || printf 'none set (plain claude.ai OAuth session)\n'

# --------------------------------------------------------------- endpoints ---
escape_curl_config_value() {
    local value=$1

    case "$value" in
        *$'\n'*|*$'\r'*) return 1 ;;
    esac
    if printf '%s' "$value" | LC_ALL=C grep -q '[^[:print:]]'; then
        return 1
    fi
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    printf '%s' "$value"
}

probe() {
    # $1 = label, $2 = url
    local label=$1 url=$2 body status escaped_credential=""
    printf '\n--- %s\n%s\n' "$label" "$url"
    if [ -z "$TOKEN" ]; then
        if [ "$UNSAFE_AUTH_SEEN" -eq 1 ]; then
            printf 'skipped: access credential contains unsupported characters\n'
        else
            printf 'skipped: no access token to present\n'
        fi
        return
    fi
    if ! escaped_credential=$(escape_curl_config_value "$TOKEN"); then
        printf 'skipped: access credential contains unsupported characters\n'
        return
    fi
    body=$({
        printf 'header = "Authorization: Bearer %s"\n' "$escaped_credential"
        printf 'header = "anthropic-beta: %s"\n' "$BETA_HEADER"
        printf 'user-agent = "%s"\n' "$USER_AGENT"
    } | curl -q --config - -sS --max-time 15 -w '\n%{http_code}' "$url" 2>&1)
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
