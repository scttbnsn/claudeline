#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

updater="$repo_root/scripts/update_anthropic_pricing.pl"
checker="$repo_root/scripts/check_anthropic_model_coverage.pl"

[ -f "$updater" ] || {
    printf 'FAIL: expected updater script %s\n' "$updater" >&2
    exit 1
}

[ -f "$checker" ] || {
    printf 'FAIL: expected coverage checker script %s\n' "$checker" >&2
    exit 1
}

assert_eq() {
    local expected=$1
    local actual=$2
    local label=$3

    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

pricing_html="$tmpdir/pricing.html"
generated_manifest="$tmpdir/anthropic_pricing.json"
covered_models="$tmpdir/covered_models.json"
uncovered_models="$tmpdir/uncovered_models.json"

cat > "$pricing_html" <<'EOF'
<table>
  <thead>
    <tr>
      <th>Model</th>
      <th>Base Input Tokens</th>
      <th>5m Cache Writes</th>
      <th>1h Cache Writes</th>
      <th>Cache Hits &amp; Refreshes</th>
      <th>Output Tokens</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>Claude Opus 4.6</td>
      <td>$5 / MTok</td>
      <td>$6.25 / MTok</td>
      <td>$10 / MTok</td>
      <td>$0.50 / MTok</td>
      <td>$25 / MTok</td>
    </tr>
    <tr>
      <td>Claude Opus 4.5</td>
      <td>$5 / MTok</td>
      <td>$6.25 / MTok</td>
      <td>$10 / MTok</td>
      <td>$0.50 / MTok</td>
      <td>$25 / MTok</td>
    </tr>
    <tr>
      <td>Claude Opus 4.1</td>
      <td>$15 / MTok</td>
      <td>$18.75 / MTok</td>
      <td>$30 / MTok</td>
      <td>$1.50 / MTok</td>
      <td>$75 / MTok</td>
    </tr>
    <tr>
      <td>Claude Opus 4</td>
      <td>$15 / MTok</td>
      <td>$18.75 / MTok</td>
      <td>$30 / MTok</td>
      <td>$1.50 / MTok</td>
      <td>$75 / MTok</td>
    </tr>
    <tr>
      <td>Claude Sonnet 4.6</td>
      <td>$3 / MTok</td>
      <td>$3.75 / MTok</td>
      <td>$6 / MTok</td>
      <td>$0.30 / MTok</td>
      <td>$15 / MTok</td>
    </tr>
    <tr>
      <td>Claude Sonnet 4.5</td>
      <td>$3 / MTok</td>
      <td>$3.75 / MTok</td>
      <td>$6 / MTok</td>
      <td>$0.30 / MTok</td>
      <td>$15 / MTok</td>
    </tr>
    <tr>
      <td>Claude Sonnet 4</td>
      <td>$3 / MTok</td>
      <td>$3.75 / MTok</td>
      <td>$6 / MTok</td>
      <td>$0.30 / MTok</td>
      <td>$15 / MTok</td>
    </tr>
    <tr>
      <td>Claude Sonnet 3.7 (<a href="/docs/en/about-claude/model-deprecations">deprecated</a>)</td>
      <td>$3 / MTok</td>
      <td>$3.75 / MTok</td>
      <td>$6 / MTok</td>
      <td>$0.30 / MTok</td>
      <td>$15 / MTok</td>
    </tr>
    <tr>
      <td>Claude Haiku 4.5</td>
      <td>$1 / MTok</td>
      <td>$1.25 / MTok</td>
      <td>$2 / MTok</td>
      <td>$0.10 / MTok</td>
      <td>$5 / MTok</td>
    </tr>
    <tr>
      <td>Claude Haiku 3.5</td>
      <td>$0.80 / MTok</td>
      <td>$1 / MTok</td>
      <td>$1.6 / MTok</td>
      <td>$0.08 / MTok</td>
      <td>$4 / MTok</td>
    </tr>
    <tr>
      <td>Claude Opus 3 (<a href="/docs/en/about-claude/model-deprecations">deprecated</a>)</td>
      <td>$15 / MTok</td>
      <td>$18.75 / MTok</td>
      <td>$30 / MTok</td>
      <td>$1.50 / MTok</td>
      <td>$75 / MTok</td>
    </tr>
    <tr>
      <td>Claude Haiku 3</td>
      <td>$0.25 / MTok</td>
      <td>$0.30 / MTok</td>
      <td>$0.50 / MTok</td>
      <td>$0.03 / MTok</td>
      <td>$1.25 / MTok</td>
    </tr>
  </tbody>
</table>
EOF

perl "$updater" \
    --pricing-html "$pricing_html" \
    --output "$generated_manifest" \
    --generated-at "2026-04-05T00:00:00Z"

haiku_input_units=$(perl -MJSON::PP=decode_json -e '
    use strict;
    use warnings;
    local $/;
    my $doc = decode_json(<>);
    print $doc->{pricing}{"claude-haiku-4-5"}{input_cost_units};
' < "$generated_manifest")
assert_eq "100" "$haiku_input_units" "updater writes Haiku pricing into the generated manifest"

default_fallback=$(perl -MJSON::PP=decode_json -e '
    use strict;
    use warnings;
    local $/;
    my $doc = decode_json(<>);
    print $doc->{fallback_pricing_keys}{default};
' < "$generated_manifest")
assert_eq "claude-sonnet-4-6" "$default_fallback" "updater writes the default fallback bucket"

cat > "$covered_models" <<'EOF'
{"data":[{"id":"claude-opus-4-6"},{"id":"claude-haiku-4-5-20251001"}]}
EOF

perl "$checker" --manifest "$generated_manifest" --models-json "$covered_models" > "$tmpdir/covered.out"

cat > "$uncovered_models" <<'EOF'
{"data":[{"id":"claude-opus-4-6"},{"id":"claude-future-9"}]}
EOF

if perl "$checker" --manifest "$generated_manifest" --models-json "$uncovered_models" > "$tmpdir/uncovered.out" 2>&1; then
    echo "FAIL: coverage checker should fail when the models list contains an uncovered id" >&2
    exit 1
fi

grep -Fq 'claude-future-9' "$tmpdir/uncovered.out" || {
    echo "FAIL: coverage checker should report uncovered model ids" >&2
    exit 1
}

printf 'ok\n'
