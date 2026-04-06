#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

parser="$repo_root/lib/jsonl_parser.pl"
checker="$repo_root/scripts/check_anthropic_model_coverage.pl"
bad_manifest="$tmpdir/bad-manifest.json"
models_json="$tmpdir/models.json"

cat > "$bad_manifest" <<'EOF'
{
  "pricing": {
    "claude-sonnet-4-6": {
      "display_name": "Claude Sonnet 4.6",
      "input_cost_units": 300,
      "cache_write_cost_units": 375,
      "cache_write_1h_cost_units": 600,
      "cache_read_cost_units": 30,
      "output_cost_units": 1500
    }
  },
  "rules": [
    {
      "pricing_key": "claude-sonnet-4-6",
      "match_kind": "regex",
      "match_value": "^(?{ die q(pwned) })$"
    }
  ],
  "fallback_pricing_keys": {
    "default": "claude-sonnet-4-6",
    "opus": "claude-sonnet-4-6",
    "sonnet": "claude-sonnet-4-6",
    "haiku": "claude-sonnet-4-6"
  }
}
EOF

cat > "$models_json" <<'EOF'
{"data":[{"id":"claude-sonnet-4-6"}]}
EOF

if STATUSLINE_PRICING_MANIFEST="$bad_manifest" perl "$parser" cold-scan >"$tmpdir/parser.out" 2>"$tmpdir/parser.err" <<<''
then
    echo "FAIL: jsonl parser should reject unsafe manifest regex rules" >&2
    exit 1
fi

grep -Fq 'invalid regex rule' "$tmpdir/parser.err" || {
    echo "FAIL: jsonl parser should explain invalid manifest regex rules" >&2
    cat "$tmpdir/parser.err" >&2
    exit 1
}

if perl "$checker" --manifest "$bad_manifest" --models-json "$models_json" >"$tmpdir/checker.out" 2>"$tmpdir/checker.err"
then
    echo "FAIL: coverage checker should reject unsafe manifest regex rules" >&2
    exit 1
fi

grep -Fq 'invalid regex rule' "$tmpdir/checker.err" || {
    echo "FAIL: coverage checker should explain invalid manifest regex rules" >&2
    cat "$tmpdir/checker.err" >&2
    exit 1
}

printf 'ok\n'
