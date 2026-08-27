#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

git check-ignore -q .claude/ || fail ".gitignore should ignore the complete .claude directory"

expected_lint='shellcheck -x -e SC2034 -S warning statusline.sh lib/statusline_themes.sh lib/statusline_display.sh lib/statusline_usage.sh'
grep -Fxq "$expected_lint" CONTRIBUTING.md || fail "documented lint command should match CI and lefthook"
grep -Fq 'Dependencies: `bash` (3.2+)' CONTRIBUTING.md || fail "documented Bash requirement should match README"

expected_spend_table='| Range | Color |
|-------|-------|
| 0-9% | cyan |
| 10-19% | teal |
| 20-29% | green |
| 30-39% | lime |
| 40-49% | yellow |
| 50-59% | orange |
| 60-69% | coral |
| 70-79% | red |
| 80-89% | hot pink |
| 90-99% | magenta |
| 100%+ | white-hot |'
spend_table=$(awk '
    /id="spend-indicator"/ { in_section=1 }
    in_section && /^\| Range \| Color \|$/ { capture=1 }
    capture && /^$/ { exit }
    capture { print }
' README.md)
[ "$spend_table" = "$expected_spend_table" ] || fail "spend color guidance should match all 11 runtime tiers"

expected_git_guidance='Repo/branch with status indicators — unstaged, staged, ahead/behind, stash presence'
grep -Fxq "$expected_git_guidance" README.md || fail "Git guidance should describe the stash presence marker"
if grep -Fq 'stash count' README.md; then
    fail "Git guidance should not claim that the status line counts stashes"
fi

expected_burst_table='| Range | Bar | Color |
|-------|-----|-------|
| 1-12% | ▁ | cyan |
| 13-24% | ▂ | teal |
| 25-37% | ▃ | green |
| 38-49% | ▄ | yellow |
| 50-62% | ▅ | orange |
| 63-74% | ▆ | red |
| 75-87% | ▇ -135m | magenta + countdown |
| 88-99% | █ -90m | bright magenta + countdown |
| 100%+ | 🤑 -45m | limit + countdown |'
burst_table=$(awk '
    /id="burst-indicator"/ { in_section=1 }
    in_section && /^\| Range \| Bar \| Color \|$/ { capture=1 }
    capture && /^$/ { exit }
    capture { print }
' README.md)
[ "$burst_table" = "$expected_burst_table" ] \
    || fail "burst guidance should distinguish the 88-99 and 100+ bar phases"

grep -Fq 'On bar-display ticks, a dimmed countdown shows minutes until the 5-hour window resets whenever usage is 75%+ *or* the reset is under an hour away.' README.md \
    || fail "burst guidance should scope countdowns to bar-display ticks"
grep -Fq 'Raw-percent ticks omit the countdown.' README.md \
    || fail "burst guidance should describe the tested raw-percent phase"

expected_uninstall='curl -fsSL https://raw.githubusercontent.com/scttbnsn/claudeline/main/uninstall.sh | bash'
grep -Fxq "$expected_uninstall" README.md || fail "README should use the safe uninstall helper"
grep -Fq 'The helper honors an exported `CLAUDE_CONFIG_DIR`' README.md \
    || fail "uninstall guidance should cover custom profiles"
if grep -Fq "jq 'del(.statusLine)'" README.md; then
    fail "README should not publish a settings-link-destroying uninstall command"
fi

printf 'ok\n'
