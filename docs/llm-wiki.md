# The LLM wiki: how this project remembers

Claude Code starts every session with no memory of the last one. This project used to solve that with one state file that Claude read first. It worked until it did not: every session appended a dated block, and in my own copy the file passed 150 KB. Each session paid to load it, the newest facts competed with stale ones, and a correction written in one block did not stop an older block from being quoted.

The fix is the "LLM Wiki" pattern from Andrej Karpathy's [idea file](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f): instead of re-reading raw history every time, the model maintains a small, interlinked set of markdown pages between you and the sources.

## Three layers, four loading levels

- **Raw sources** (`wiki/raw/`): broker statements, exports, anything you never edit.
- **The wiki** (`wiki/*.md`): pages Claude writes and keeps current.
- **The schema** (`CLAUDE.md`, section WIKI): how the wiki is organized and maintained.

| Level | What | Budget | When it is read |
|:---|:---|:---|:---|
| L0 | `CLAUDE.md` | | every session |
| L1 | `wiki/context.md` | 6,000 characters | every session, imported from `CLAUDE.md` |
| L2 | `wiki/index.md` and the matching pages | as needed | on demand |
| L3 | `wiki/log.md` and `wiki/raw/` | never whole | Grep only |

What goes in L1 is decided by one question: would it be dangerous or embarrassing if Claude did not know it? An open position, a resting order, a deadline: yes, L1. The full history of a position, a study, a list of past rebounds: a page, with a one-line pointer.

## Three operations

- **Ingest:** when a session produces something new (an order placed, a fill, a decision, a study), update the page, its line in `index.md`, add a log entry, and touch `context.md` only if every future session needs it.
- **Query:** `context.md`, then `index.md`, then Grep, then open only the matching pages. A reusable answer is filed back as a page.
- **Lint:** `python wiki/lint.py` checks broken links, pages missing from the index, the context budget, oversized logs, pages without frontmatter and em dashes. Then a manual pass for contradictions.

## Rules that mattered in practice

- **Corrections are dated and propagated.** "corrected 2026-11-20: ..." goes in the page, and the same fix goes to `index.md` and `context.md`. Otherwise the old claim keeps winning, because it is the one that gets loaded.
- **Write what is verified; mark the rest.** An agent that summarizes its own summaries compounds errors.
- **No credentials or account numbers in pages.** Say where they are found.
- **Personal content never reaches the repo.** `.gitignore` ignores everything under `wiki/` except the `*.example.md` templates and the lint. `setup.ps1` copies the templates once.

## Ideas taken from the community

| Source | Idea | Where it shows up |
|:---|:---|:---|
| Comment by bluewater8008 on the gist | An explicit loading budget per layer | The L0 to L3 table and the 6,000-character cap |
| [ScrapingArt/Karpathy-LLM-Wiki-Stack](https://github.com/ScrapingArt/Karpathy-LLM-Wiki-Stack) | "Dangerous or embarrassing if missing?" as the test for what is always loaded | The routing between `context.md` and pages |
| [cablate/llm-atomic-wiki](https://github.com/cablate/llm-atomic-wiki) | Lint in two layers: programmatic checks first, then a model review | `wiki/lint.py`, then the manual pass |
| [ignromanov/llm-obsidian-wiki](https://github.com/ignromanov/llm-obsidian-wiki) | Provenance, typed pages, next steps in the log | Frontmatter `type` and `status`, sources cited in pages |
| Comments by laphilosophia, frosk1 and Jwcjwc12 on the gist | Truth maintenance: errors compound, so cite first and review corrections | Dated corrections that must also fix the index and the context |

## Files

| File | Role |
|:---|:---|
| `wiki/context.example.md` | Template of the L1 page: capital, positions, orders, scoreboard, dates, gotchas |
| `wiki/index.example.md`, `wiki/log.example.md` | Templates of the index and the log |
| `wiki/example-position.example.md` | What a position page looks like, with made-up data |
| `wiki/lint.py` | The programmatic lint, standard library only |
