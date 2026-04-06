# Contributing

Thanks for your interest in claudeline.

## Development Setup

```bash
git clone https://github.com/s-b-e-n-s-o-n/claudeline.git
cd claudeline
```

Dependencies: `bash` (5.x), `jq`, `git`, `perl` (5.14+ with JSON::PP).

## Running Tests

```bash
for f in tests/*.sh; do bash "$f" || exit 1; done
```

## Linting

```bash
shellcheck -x statusline.sh lib/statusline_display.sh lib/statusline_usage.sh
perl -c lib/jsonl_parser.pl
```

## Updating Pricing

When Anthropic releases new models or changes pricing:

```bash
perl scripts/update_anthropic_pricing.pl    # regenerate lib/anthropic_pricing.json
perl scripts/check_anthropic_model_coverage.pl  # verify all models are covered
```

## Commit Style

Emoji conventional commits: `<emoji> <type>(scope): <description>`

| Emoji | Type |
|-------|------|
| ✨ | feat |
| 🐛 | fix |
| 🔄 | refactor |
| ⚡ | perf |
| 📝 | docs |
| 🧪 | test |
| 🔧 | config |
| 🔒 | security fix |
| 🗑️ | remove |
