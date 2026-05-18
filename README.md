# MioIsland Stats Plugin

[![Plugin](https://img.shields.io/badge/MioIsland-plugin-CAFF00?style=flat-square)](https://github.com/MioMioOS/MioIsland)
[![macOS](https://img.shields.io/badge/macOS-15%2B-black?style=flat-square&logo=apple)](https://github.com/MioMioOS/MioIsland)
[![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)

Editorial-style daily and weekly API usage stats for [MioIsland](https://github.com/MioMioOS/MioIsland) — your Claude Code token consumption and cost rendered as a newspaper.

This is the source for the official `stats.bundle` plugin that ships with MioIsland v2.0+. It reads `~/.cc-switch/cc-switch.db` (SQLite) via the system `sqlite3` CLI to compute token usage, cache efficiency, and model cost breakdowns — all in a single Swift `.bundle` loaded by the host app.

## Features

- **Newspaper layout** — masthead, serif italic headlines, two-column body, hairline rules, no charts. Pure typography.
- **Day and week views** — switch via the masthead toggle. Both have their own narrative.
- **Token & cost tracking** — input/output tokens, cache hit rate, total API spend per day/week.
- **Per-model breakdown** — see which models consumed the most tokens and generated the highest cost.
- **Smart insights** — auto-detects high-volume days, premium model usage, excellent cache efficiency, streak milestones.
- **Full i18n** — respects MioIsland's `appLanguage` setting (zh / en / auto).

## Build

```bash
./build.sh              # → build/stats.bundle + build/stats.zip
./build.sh install      # also copies to ~/.config/codeisland/plugins/
```

Then restart MioIsland and the new build loads on next launch.

## How it works

`AnalyticsCollector` queries `~/.cc-switch/cc-switch.db` via `Process` + `sqlite3 -json` once per day, aggregating `proxy_request_logs` into per-day token/cost reports, and produces a 14-day window (`thisWeek` + `lastWeek` for comparison). Results are persisted to `~/Library/Application Support/CodeIsland/analytics_cache.json` so warm starts paint instantly.

`EditorsNoteService` invokes your installed `claude` CLI in non-interactive mode (`claude -p`) with an editorial-coach prompt. It looks for `claude` at `/opt/homebrew/bin/claude`, `/usr/local/bin/claude`, `~/.claude/local/claude`, and `~/.local/bin/claude`. The prompt only contains aggregate numbers (turns, focus minutes, tool counts, project names) — never source code — and the response is cached per day/week and per language so it doesn't burn credits on every view.

## License

MIT.
