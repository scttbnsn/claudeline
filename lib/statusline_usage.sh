# shellcheck shell=bash

# Calculate all-time usage from JSONL files (cached for 5 minutes)
# Uses persistent per-file running sums so cache misses do not trigger full rescans.
write_jsonl_cache() {
    local now=$1
    local summary=$2
    local total_tokens total_cost_units total_input total_output total_cw total_cr
    read -r total_tokens total_cost_units total_input total_output total_cw total_cr <<< "$summary"
    total_tokens=${total_tokens:-0}
    total_cost_units=${total_cost_units:-0}
    total_input=${total_input:-0}
    total_output=${total_output:-0}
    total_cw=${total_cw:-0}
    total_cr=${total_cr:-0}

    # Cost units are millionths of a cent to preserve fractional pricing exactly.
    local total_cost_cents=$(( (total_cost_units + 500000) / 1000000 ))
    printf '%s\n%s %s %s %s %s %s\n' \
        "$now" "$total_tokens" "$total_cost_cents" \
        "$total_input" "$total_output" "$total_cw" "$total_cr" > "$JSONL_CACHE"
}

restore_jsonl_cache_from_state() {
    local now=$1
    [ -f "$JSONL_STATE" ] || return 1

    local _state_time summary
    exec 3<"$JSONL_STATE" || return 1
    read -r _state_time <&3 || { exec 3<&-; return 1; }
    read -r summary <&3 || { exec 3<&-; return 1; }
    exec 3<&-

    if ! [[ "$summary" =~ ^[0-9]+[[:space:]][0-9]+[[:space:]][0-9]+[[:space:]][0-9]+[[:space:]][0-9]+[[:space:]][0-9]+$ ]]; then
        debug_log "Ignoring invalid JSONL state summary in $JSONL_STATE: ${summary:-<empty>}"
        return 1
    fi

    [ -n "$summary" ] || return 1
    write_jsonl_cache "$now" "$summary"
}

# Fast streaming scan for cold start (no per-file state, just global totals).
# Uses xargs cat pipeline (~2-3s) instead of per-file opens (~8-40s on 10K+ files).
cold_jsonl_scan() {
    local now=$1
    local summary
    summary=$(find "$HOME/.claude/projects" "$HOME/.config/claude/projects" \
        -name "*.jsonl" -type f -not -type l -print0 2>>"$STATUSLINE_DEBUG_LOG" \
        | xargs -0 cat 2>/dev/null | perl -e '
        use strict;
        my ($ti, $to, $tw, $tr, $tc) = (0, 0, 0, 0, 0);
        while (<STDIN>) {
            next unless /"message".*"usage"/;
            my $is_opus = /claude-opus|opus-4/ ? 1 : 0;
            my $in = /"input_tokens":(\d+)/ ? $1 : 0;
            my $out = /"output_tokens":(\d+)/ ? $1 : 0;
            my $cw = /"cache_creation_input_tokens":(\d+)/ ? $1 : 0;
            my $cr = /"cache_read_input_tokens":(\d+)/ ? $1 : 0;
            if ($is_opus) {
                $tc += $in * 1500 + $out * 7500 + $cw * 1875 + $cr * 150;
            } else {
                $tc += $in * 300 + $out * 1500 + $cw * 375 + $cr * 30;
            }
            $ti += $in; $to += $out; $tw += $cw; $tr += $cr;
        }
        my $tt = $ti + $to + $tw + $tr;
        printf "%d %d %d %d %d %d", $tt, $tc, $ti, $to, $tw, $tr;
    ' 2>>"$STATUSLINE_DEBUG_LOG") || return 1

    [ -n "$summary" ] || return 1
    write_jsonl_cache "$now" "$summary"
    # Write minimal state (totals only, no per-file records) so next refresh builds full state
    printf '%s\n%s\n' "$now" "$summary" > "$JSONL_STATE" 2>>"$STATUSLINE_DEBUG_LOG"
}

refresh_jsonl_state() {
    local now=$1

    # Cold start: no state file — use fast streaming pipeline
    if [ ! -f "$JSONL_STATE" ]; then
        debug_log "Cold JSONL scan: using fast streaming pipeline"
        cold_jsonl_scan "$now"
        return
    fi

    # Minimal state (2 lines = timestamp + totals, no per-file records):
    # full per-file state build needed, but we already have usable totals
    local line_count
    line_count=$(wc -l < "$JSONL_STATE" 2>/dev/null)
    if [ "${line_count:-0}" -le 2 ]; then
        debug_log "Building per-file JSONL state (one-time)"
    fi

    local tmp_state summary
    tmp_state=$(mktemp "${CACHE_DIR}/.jsonl-state-XXXXXX") || return 1

    summary=$(find "$HOME/.claude/projects" "$HOME/.config/claude/projects" \
        -name "*.jsonl" -type f -not -type l -print0 2>>"$STATUSLINE_DEBUG_LOG" | perl -e '
        use strict;
        use warnings;

        my ($state_path, $now, $out_path) = @ARGV;
        my %old;

        sub parse_usage {
            my ($path, $start_pos) = @_;
            my ($input, $output, $cache_write, $cache_read, $cost_units) = (0, 0, 0, 0, 0);

            open my $fh, "<", $path or die "open $path: $!";
            binmode $fh;
            seek($fh, $start_pos, 0) if $start_pos;

            while (my $line = <$fh>) {
                next unless $line =~ /"message".*"usage"/;
                my $is_opus = $line =~ /claude-opus|opus-4/ ? 1 : 0;
                my $in = $line =~ /"input_tokens":(\d+)/ ? $1 : 0;
                my $out = $line =~ /"output_tokens":(\d+)/ ? $1 : 0;
                my $cw = $line =~ /"cache_creation_input_tokens":(\d+)/ ? $1 : 0;
                my $cr = $line =~ /"cache_read_input_tokens":(\d+)/ ? $1 : 0;

                if ($is_opus) {
                    $cost_units += $in * 1500 + $out * 7500 + $cw * 1875 + $cr * 150;
                } else {
                    $cost_units += $in * 300 + $out * 1500 + $cw * 375 + $cr * 30;
                }

                $input += $in;
                $output += $out;
                $cache_write += $cw;
                $cache_read += $cr;
            }

            close $fh;
            return ($input + $output + $cache_write + $cache_read,
                $cost_units, $input, $output, $cache_write, $cache_read);
        }

        if (open my $state_fh, "<", $state_path) {
            scalar <$state_fh>;
            scalar <$state_fh>;
            while (my $line = <$state_fh>) {
                chomp $line;
                my ($mtime, $size, $tokens, $cost_units, $input, $output, $cw, $cr, $path) =
                    split /\t/, $line, 9;
                next unless defined $path;
                $old{$path} = {
                    mtime => $mtime + 0,
                    size => $size + 0,
                    tokens => $tokens + 0,
                    cost_units => $cost_units + 0,
                    input => $input + 0,
                    output => $output + 0,
                    cw => $cw + 0,
                    cr => $cr + 0,
                };
            }
            close $state_fh;
        }

        my $raw = do { local $/ = undef; <STDIN> // "" };
        my @paths = sort grep { length } split /\0/, $raw;
        my @records;
        my ($total_tokens, $total_cost_units, $total_input, $total_output, $total_cw, $total_cr) =
            (0, 0, 0, 0, 0, 0);

        for my $path (@paths) {
            my @stat = stat($path);
            next unless @stat;

            my ($mtime, $size) = ($stat[9], $stat[7]);
            my ($tokens, $cost_units, $input, $output, $cw, $cr);
            my $prev = $old{$path};

            if ($prev && $size == $prev->{size} && $mtime == $prev->{mtime}) {
                ($tokens, $cost_units, $input, $output, $cw, $cr) =
                    @{$prev}{qw(tokens cost_units input output cw cr)};
            } elsif ($prev && $size >= $prev->{size}) {
                my ($delta_tokens, $delta_cost_units, $delta_input, $delta_output, $delta_cw, $delta_cr) =
                    parse_usage($path, $prev->{size});
                $tokens = $prev->{tokens} + $delta_tokens;
                $cost_units = $prev->{cost_units} + $delta_cost_units;
                $input = $prev->{input} + $delta_input;
                $output = $prev->{output} + $delta_output;
                $cw = $prev->{cw} + $delta_cw;
                $cr = $prev->{cr} + $delta_cr;
            } else {
                ($tokens, $cost_units, $input, $output, $cw, $cr) = parse_usage($path, 0);
            }

            push @records, join("\t", $mtime, $size, $tokens, $cost_units, $input, $output, $cw, $cr, $path);
            $total_tokens += $tokens;
            $total_cost_units += $cost_units;
            $total_input += $input;
            $total_output += $output;
            $total_cw += $cw;
            $total_cr += $cr;
        }

        open my $out_fh, ">", $out_path or die "open $out_path: $!";
        print {$out_fh} "$now\n";
        print {$out_fh} "$total_tokens $total_cost_units $total_input $total_output $total_cw $total_cr\n";
        print {$out_fh} "$_\n" for @records;
        close $out_fh;

        print "$total_tokens $total_cost_units $total_input $total_output $total_cw $total_cr";
    ' "$JSONL_STATE" "$now" "$tmp_state" 2>>"$STATUSLINE_DEBUG_LOG") || {
        debug_log "Failed to refresh JSONL state from project logs; falling back to prior state if available"
        rm -f "$tmp_state"
        return 1
    }

    mv "$tmp_state" "$JSONL_STATE" 2>>"$STATUSLINE_DEBUG_LOG" || {
        debug_log "Failed to atomically update $JSONL_STATE"
        rm -f "$tmp_state"
        return 1
    }

    write_jsonl_cache "$now" "${summary:-0 0 0 0 0 0}"
}

get_jsonl_totals() {
    local now=${1:-${NOW:-$(date +%s)}}
    local cache_age=999999
    local state_age=999999

    # Check cache age
    if [ -f "$JSONL_CACHE" ]; then
        local cache_time
        cache_time=$(head -1 "$JSONL_CACHE" 2>>"$STATUSLINE_DEBUG_LOG" || echo 0)
        if ! [[ "$cache_time" =~ ^[0-9]+$ ]]; then
            debug_log "Ignoring invalid JSONL cache timestamp in $JSONL_CACHE: ${cache_time:-<empty>}"
            cache_time=0
        fi
        cache_age=$((now - cache_time))
    fi

    # Return cached values if fresh (300 seconds = 5 minutes)
    if [ "$cache_age" -lt 300 ] && [ -f "$JSONL_CACHE" ]; then
        cat "$JSONL_CACHE"
        return
    fi

    # If the transient cache file is gone but persistent state is fresh, rebuild from it.
    if [ -f "$JSONL_STATE" ]; then
        local state_time
        read -r state_time < "$JSONL_STATE" 2>>"$STATUSLINE_DEBUG_LOG" || state_time=0
        if ! [[ "$state_time" =~ ^[0-9]+$ ]]; then
            debug_log "Ignoring invalid JSONL state timestamp in $JSONL_STATE: ${state_time:-<empty>}"
            state_time=0
        fi
        state_age=$((now - state_time))
    fi

    if [ "$state_age" -lt 300 ] && restore_jsonl_cache_from_state "$now"; then
        cat "$JSONL_CACHE"
        return
    fi

    if refresh_jsonl_state "$now"; then
        cat "$JSONL_CACHE"
        return
    fi

    # Fall back to the last persistent state if refresh fails.
    if restore_jsonl_cache_from_state "$now"; then
        debug_log "Using prior JSONL state after refresh failure"
        cat "$JSONL_CACHE"
        return
    fi

    debug_log "JSONL totals unavailable; returning zeroed fallback"
    printf '%s\n0 0 0 0 0 0\n' "$now"
}

write_extra_usage_cache() {
    local now=$1
    local utilization=$2
    local tmp_cache

    tmp_cache=$(mktemp "${CACHE_DIR}/.extra-usage-XXXXXX") || return 1
    printf '%s\n%s\n' "$now" "$utilization" > "$tmp_cache" || {
        rm -f "$tmp_cache"
        return 1
    }

    mv "$tmp_cache" "$EXTRA_USAGE_CACHE" 2>>"$STATUSLINE_DEBUG_LOG" || {
        debug_log "Failed to atomically update $EXTRA_USAGE_CACHE"
        rm -f "$tmp_cache"
        return 1
    }
}

read_extra_usage_cache() {
    local now=$1
    local max_age=${2:-600}
    local cache_time cache_value cache_age

    EXTRA_USAGE_CACHE_VALUE=""
    EXTRA_USAGE_CACHE_IS_FRESH=0
    [ -f "$EXTRA_USAGE_CACHE" ] || return 1

    exec 3<"$EXTRA_USAGE_CACHE" || return 1
    read -r cache_time <&3 || {
        exec 3<&-
        return 1
    }
    read -r cache_value <&3 || cache_value=""
    exec 3<&-

    if ! [[ "$cache_time" =~ ^[0-9]+$ ]]; then
        debug_log "Ignoring invalid extra usage cache timestamp in $EXTRA_USAGE_CACHE: ${cache_time:-<empty>}"
        return 1
    fi

    case "$cache_value" in
        ""|_|null) EXTRA_USAGE_CACHE_VALUE="" ;;
        *)
            if ! [[ "$cache_value" =~ ^-?([0-9]+([.][0-9]+)?|[.][0-9]+)$ ]]; then
                debug_log "Ignoring invalid extra usage cache value in $EXTRA_USAGE_CACHE: ${cache_value:-<empty>}"
                return 1
            fi
            EXTRA_USAGE_CACHE_VALUE=$cache_value
            ;;
    esac

    cache_age=$((now - cache_time))
    [ "$cache_age" -lt "$max_age" ] && EXTRA_USAGE_CACHE_IS_FRESH=1
    return 0
}

read_claude_oauth_token() {
    local oauth_token="" creds="" cfg

    if [[ "$OSTYPE" == "darwin"* ]]; then
        creds=$(security find-generic-password -s "Claude Code-credentials" -w 2>>"$STATUSLINE_DEBUG_LOG") || {
            debug_log "Failed to read Claude Code credentials from macOS Keychain"
            creds=""
        }
        if [[ "$creds" =~ ^[0-9a-fA-F]+$ ]]; then
            creds=$(echo "$creds" | xxd -r -p)
        fi
        if [ -n "$creds" ] && ! oauth_token=$(echo "$creds" | jq -r '.claudeAiOauth.accessToken // empty' 2>>"$STATUSLINE_DEBUG_LOG"); then
            debug_log "Failed to extract OAuth token from Claude Code credentials"
            oauth_token=""
        fi
    else
        cfg="$HOME/.config/claude/credentials.json"
        if [ -f "$cfg" ] && ! oauth_token=$(jq -r '.claudeAiOauth.accessToken // empty' "$cfg" 2>>"$STATUSLINE_DEBUG_LOG"); then
            debug_log "Failed to parse Claude credentials at $cfg"
            oauth_token=""
        fi
    fi

    printf '%s\n' "$oauth_token"
}

refresh_extra_usage_cache_now() {
    local now=$1
    local oauth_token extra_usage_response extra_util

    oauth_token=$(read_claude_oauth_token)
    [ -n "$oauth_token" ] || return 1

    if ! extra_usage_response=$(curl -s --max-time 2 --config - \
        -H "Accept: application/json" \
        -H "anthropic-beta: oauth-2025-04-20" \
        "https://api.anthropic.com/api/oauth/usage" <<CURL_CONFIG
header = "Authorization: Bearer $oauth_token"
CURL_CONFIG
    2>>"$STATUSLINE_DEBUG_LOG"); then
        debug_log "Failed to fetch extra usage from Anthropic API"
        return 1
    fi

    if ! extra_util=$(printf '%s\n' "$extra_usage_response" | jq -r '.extra_usage.utilization // empty' 2>>"$STATUSLINE_DEBUG_LOG"); then
        debug_log "Failed to parse extra usage response from Anthropic API"
        return 1
    fi

    if ! [[ "$extra_util" =~ ^-?([0-9]+([.][0-9]+)?|[.][0-9]+)$ ]]; then
        debug_log "Ignoring invalid extra usage utilization from Anthropic API: ${extra_util:-<empty>}"
        return 1
    fi

    write_extra_usage_cache "$now" "$extra_util"
}

start_extra_usage_refresh() {
    local now=${1:-${NOW:-$(date +%s)}}

    mkdir "$EXTRA_USAGE_LOCK" 2>>"$STATUSLINE_DEBUG_LOG" || return 0
    (
        trap 'rmdir "$EXTRA_USAGE_LOCK" 2>>"$STATUSLINE_DEBUG_LOG" || true' EXIT
        refresh_extra_usage_cache_now "$now" >/dev/null
    ) </dev/null >>"$STATUSLINE_DEBUG_LOG" 2>&1 &
}

get_extra_usage_util_nonblocking() {
    local now=${1:-${NOW:-$(date +%s)}}

    if read_extra_usage_cache "$now" "${EXTRA_USAGE_TTL:-600}"; then
        if [ "$EXTRA_USAGE_CACHE_IS_FRESH" -eq 1 ]; then
            printf '%s\n' "$EXTRA_USAGE_CACHE_VALUE"
            return 0
        fi
    fi

    start_extra_usage_refresh "$now"
    printf '%s\n' "${EXTRA_USAGE_CACHE_VALUE:-}"
}

# Get trend arrow based on usage% velocity
# Tracks how fast you're burning tokens vs sustainable rate
# Sustainable rate = 100% / 7 days ≈ 0.01%/min
# Returns: ↑ (heating fast), ↗ (warming), → (stable), ↘ (cooling), ↓ (cooling fast)
get_trend_arrow() {
    local current_usage=$1  # Current usage percentage (0-100)
    local week_start=${2:-0}  # Epoch when current week started (optional)
    local now=${3:-$(date +%s)}  # Epoch timestamp (passed from caller)
    [[ "$current_usage" == .* ]] && current_usage="0$current_usage"

    # Single awk call: append, prune, calculate velocity, return arrow code
    # This replaces ~10 subprocess calls (tail, head, wc, 2x awk, sort, 4x bc) with 1
    # Data output goes to temp file via -v out variable (not stderr) to prevent
    # awk errors from corrupting history file
    local tmp
    tmp=$(mktemp "${CACHE_DIR}/.trend-XXXXXX") || return
    touch "$USAGE_HISTORY" 2>>"$STATUSLINE_DEBUG_LOG"
    local arrow_code
    if arrow_code=$(awk -F, -v now="$now" -v usage="$current_usage" \
        -v week_start="$week_start" -v trend_window="${TREND_WINDOW:-900}" \
        -v out="$tmp" '
    BEGIN {
        min_interval = 30
        max_age = now - 86400
        cutoff = now - trend_window
        anchor_interval = 14400
        sustainable = 0.00992
        first_time = 0; first_usage = 0
        last_time = 0; last_usage = 0
        count = 0
    }
    {
        # Skip entries before week start (handles weekly reset)
        if (week_start > 0 && $1 < week_start) next
        # Skip entries older than 24hr
        if ($1 < max_age) next

        # Smart pruning: keep recent samples, sparse anchors for older
        if ($1 < cutoff) {
            block = int((now - $1) / anchor_interval)
            if (block in seen) next
            seen[block] = 1
        }

        # Track first and last for velocity calc
        if (first_time == 0 || $1 < first_time) { first_time = $1; first_usage = $2 }
        if ($1 > last_time) { last_time = $1; last_usage = $2 }
        count++

        # Remember for append check
        most_recent_time = (most_recent_time > $1) ? most_recent_time : $1

        # Output kept lines to temp file (not stderr, to avoid corruption from awk errors)
        print >> out
    }
    END {
        # Append new entry if enough time passed
        if (now - most_recent_time >= min_interval) {
            print now "," usage >> out
            if (first_time == 0) { first_time = now; first_usage = usage }
            last_time = now; last_usage = usage
            count++
        }
        close(out)

        # Need 2+ points and 1+ minute elapsed
        if (count < 2) { print "stable"; exit }
        elapsed_min = (last_time - first_time) / 60
        if (elapsed_min < 1) { print "stable"; exit }

        # Calculate velocity ratio
        velocity = (last_usage - first_usage) / elapsed_min
        ratio = velocity / sustainable

        # Map to arrow code
        if (ratio > 3) print "hot"
        else if (ratio > 1.5) print "warm"
        else if (ratio < 0.1) print "cold"
        else if (ratio < 0.5) print "cool"
        else print "stable"
    }
    ' "$USAGE_HISTORY"); then
        # Replace history with pruned version only on success
        mv "$tmp" "$USAGE_HISTORY" 2>>"$STATUSLINE_DEBUG_LOG"
    else
        debug_log "Trend history update failed; falling back to stable arrow"
        rm -f "$tmp"
        arrow_code="stable"
    fi

    # Map code to colored arrow
    case "$arrow_code" in
        hot)    echo -e "${VEL_HOT}↑${RESET}" ;;
        warm)   echo -e "${VEL_WARM}↗${RESET}" ;;
        cold)   echo -e "${VEL_COLD}↓${RESET}" ;;
        cool)   echo -e "${VEL_COOL}↘${RESET}" ;;
        *)      echo -e "${VEL_STABLE}→${RESET}" ;;
    esac
}

# Get smart pace indicator using dual-signal approach:
#   burn_rate = velocity: how fast you're going (1.0 = on pace for reset)
#   pressure  = position: remaining time / remaining budget-days
#   effective = max(burn_rate, pressure) — take the worse signal
# Both agree on over/under (burn_rate > 1.0 ↔ pressure > 1.0), but pressure
# amplifies urgency when budget is thin (e.g., 9% left for 2.7 days → pressure 4.29)
# Uses 8-tier emoji scale: ❄️ → 🧊 → 🙂 → 👌 → ♨️ → 🥵 → 🔥 → 🚨
# Trend arrows: ↑ (heating fast), ↗ (warming), → (stable), ↘ (cooling), ↓ (cooling fast)
# If at limit (>=100%), shows time until reset: 🚨 -1.2d
# Alternates: emoji+arrow 9 times, then raw % once
get_smart_pace_indicator() {
    local usage=$1
    local resets_at=$2
    local now=${3:-$(date +%s)}
    [ -z "$usage" ] && echo "" && return
    local pct=$(printf "%.0f" "$usage" 2>>"$STATUSLINE_DEBUG_LOG")
    pct=${pct:-0}

    local reset_suffix=""
    local week_start=0
    local days_elapsed_x10k=70000  # 7 days * 10000 (default: full week elapsed)
    local burn_rate_x10k=10000     # 1.0 * 10000 (default: on pace)
    local pressure_x10k=10000      # 1.0 * 10000 (default: on pace)

    if [ -n "$resets_at" ] && [ "$resets_at" != "_" ] && [ "$resets_at" != "null" ]; then
        local reset_epoch="$resets_at"  # Already epoch seconds from status line JSON

        if [ -n "$reset_epoch" ] && [ "$reset_epoch" -gt "$now" ]; then
            local seconds_until_reset=$((reset_epoch - now))
            week_start=$((reset_epoch - 604800))  # 7 days before reset = week start

            # Use integer math: multiply by 10000 to preserve 4 decimal places
            # 86400 seconds = 1 day
            local days_until_x10k=$(( seconds_until_reset * 10000 / 86400 ))
            days_elapsed_x10k=$(( 70000 - days_until_x10k ))  # 7 * 10000

            # Calculate burn rate: (pct / days_elapsed) * 7 / 100
            # burn_rate_x10k = burn_rate * 10000 = pct * 7 * 10000 / days_elapsed / 100
            #                = pct * 700 / days_elapsed = pct * 7000000 / days_elapsed_x10k
            if [ "$days_elapsed_x10k" -gt 100 ]; then  # > 0.01 days
                burn_rate_x10k=$(( pct * 7000000 / days_elapsed_x10k ))
            elif [ "$pct" -gt 0 ]; then
                burn_rate_x10k=100000  # 10.0
            else
                burn_rate_x10k=0
            fi

            # Budget pressure: time_remaining / budget_remaining_in_days
            # Amplifies signal when budget is thin (e.g., 9% left for 2.7 days)
            local remaining=$((100 - pct))
            if [ "$remaining" -gt 0 ] && [ "$days_until_x10k" -gt 0 ]; then
                # pressure = days_until / (remaining * 7 / 100)
                # pressure_x10k = days_until_x10k * 100 / (remaining * 7)
                pressure_x10k=$(( days_until_x10k * 100 / (remaining * 7) ))
            fi

            # Format reset time suffix for when at limit (only place needing float)
            if [ "$days_until_x10k" -ge 10000 ]; then  # >= 1 day
                # Format: days_until_x10k / 10000 with 1 decimal
                local days_int=$(( days_until_x10k / 10000 ))
                local days_frac=$(( (days_until_x10k % 10000) / 1000 ))
                reset_suffix=" -${days_int}.${days_frac}d"
            else
                local hours_until=$(( days_until_x10k * 24 / 10000 ))
                reset_suffix=" -${hours_until}h"
            fi
        fi
    fi

    # Alternate display: emoji+arrow 7 times, then raw % 3 times (every 10 sec update)
    # Check cycle FIRST so raw % always shows on its cycles, regardless of alarm state
    local cycle=$(( (now / 10) % 10 ))
    if [ "$cycle" -ge 7 ]; then
        echo "${DIM}${pct}%${RESET}"
        return
    fi

    # If at/over limit, always show alarm with reset time
    if [ "$pct" -ge 100 ]; then
        echo "🚨${reset_suffix}"
        return
    fi

    # Get trend arrow based on usage% velocity
    local arrow
    arrow=$(get_trend_arrow "$usage" "$week_start" "$now")

    # Effective rate = max(burn_rate, pressure)
    # Burn rate captures velocity, pressure captures remaining runway
    local emoji
    local br=${burn_rate_x10k:-10000}
    if [ "${pressure_x10k:-10000}" -gt "$br" ]; then
        br=$pressure_x10k
    fi
    if [ "$br" -lt 3000 ]; then
        emoji="❄️"   # Way under - using < 30% of sustainable rate
    elif [ "$br" -lt 6000 ]; then
        emoji="🧊"   # Under pace - will use ~40-60% by reset
    elif [ "$br" -lt 8500 ]; then
        emoji="🙂"   # Comfortable - will use ~60-85% by reset
    elif [ "$br" -lt 11500 ]; then
        emoji="👌"   # On pace - will use ~85-115% by reset
    elif [ "$br" -lt 14000 ]; then
        emoji="♨️"   # Warming - will run out ~day 5-6
    elif [ "$br" -lt 18000 ]; then
        emoji="🥵"   # Hot - will run out ~day 4-5
    elif [ "$br" -lt 25000 ]; then
        emoji="🔥"   # Very hot - will run out ~day 3-4
    else
        emoji="🚨"   # Alarm - effective rate >= 2.5
    fi

    echo "${emoji}${arrow}"
}
