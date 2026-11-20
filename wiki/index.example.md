# Wiki index

One line per page, 200 characters at most: `- [Title](relative/path.md): summary, **status** (updated YYYY-MM-DD)`. Claude reads this file before opening any page. `python wiki/lint.py` reports pages missing from it.

> Template. `setup.ps1` copies it to `wiki/index.md` (gitignored). The page below is an example; delete it when you add your own.

## Live

- [context.md](context.md): capital, positions, resting orders, key dates, gotchas; loaded every session, **live** (updated 2026-01-05)

## Positions

- [example-position.example.md](example-position.example.md): what a position page looks like, made-up data, **example** (updated 2026-01-05)

## Research

## Raw (immutable sources, original language, Grep only)

- `raw/`: broker statements, exported notes, anything you never edit
