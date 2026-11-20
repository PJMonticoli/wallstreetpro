# WallStreetPro

A rules-based swing trading analysis system that runs on Claude Code, and the backtest that showed its rules had no edge.

Once a week, Claude reads live chart data from TradingView through an MCP server, checks a short list of rules and answers with one of two words: BUY or NO BUY, with the entry order, the stop and the exit date. A person places every order by hand. Nothing in this repo connects to a broker.

The part I would point a reviewer to is the backtest. After several versions of adding rules, I ran the system over 5,533 simulated trades and it failed every pass condition I had written down beforehand. Its alpha against SPY was indistinguishable from zero. Version 5 is what was left after deleting every rule the data did not support.

## How it works

```
                    WALLSTREETPRO_START.bat
                             |
          +------------------+-------------------+
          |                                      |
  TradingView Desktop                      screener.ps1
  started with the debug port       TradingView public scanner API
          |                                      |
   CDP on port 9222                   watchlist_screener.md
          |                                      |
  TradingView MCP server  <---- MCP ---->  Claude Code
  (third party)                              reads CLAUDE.md, trading_system.md,
          |                                  daily_brief.md, wiki/context.md
  WallStreetPro v3 Unified (Pine)                |
  ADR20, EMAs and distance to EMA50              v
  exposed in the data window          BUY / NO BUY + entry, stop, exit date
                                                 |
                                   the operator places the order by hand


  backtest/backtest_wsp.py   offline and separate: measures the rules on 2015-2026 daily bars
```

- **Claude Code** is the runtime. `CLAUDE.md` holds the operating instructions, `trading_system.md` the full rules, and `daily_brief.md` the script of the weekly check.
- **TradingView MCP** ([tradingview-mcp-jackson](https://github.com/LewisWJackson/tradingview-mcp-jackson), third party) lets Claude read quotes, bars and indicator values from the TradingView Desktop app.
- **The screener** (`screener.ps1`) queries TradingView's public scanner API and writes about 30 candidates that pass the universe filters: price, liquidity, volatility, uptrend, earnings distance.
- **The Pine indicator** (`wallstreetpro_v3_unified.pine`) computes ADR20, the EMAs and the distance to EMA50 in one place, so those numbers are never worked out by hand.
- **The backtest** (`backtest/`) replays the rules bar by bar and reports expectancy in R, alpha against SPY and the cost of each rule.

## Requirements

- Windows 10 or 11. The launcher and the setup are a `.bat` and Windows PowerShell 5.1 scripts.
- [TradingView Desktop](https://www.tradingview.com/desktop/) and a TradingView account. The MCP server's own README says real-time data needs a paid plan.
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code/setup), installed and logged in.
- [Node.js](https://nodejs.org/) 18 or later, for the MCP server.
- [Git](https://git-scm.com/download/win).
- [Python](https://www.python.org/downloads/) 3.10 or later, only for the backtest. Tested on 3.13.

The MCP server is not included in this repo. It is someone else's project under its own license, and the setup script clones it from its source. Read its disclaimer before using it: it drives TradingView Desktop through the Chrome DevTools Protocol, and staying within TradingView's terms of use is on you.

## Setup

Clone the repo, then double-click `SETUP.bat` or run:

```powershell
powershell -ExecutionPolicy Bypass -File setup.ps1
```

The script does five things, and skips whatever is already done, so it is safe to run again:

1. Checks that git, Node.js, Claude Code, Python and TradingView Desktop are installed, and tells you where to get whatever is missing.
2. Clones the TradingView MCP server into `%USERPROFILE%\tradingview-mcp-jackson` and runs `npm install` there.
3. Registers that server with Claude Code under the name `tradingview`, scoped to this folder (`claude mcp add tradingview -- node ...\src\server.js`).
4. Creates `backtest\.venv` and installs `requirements.txt`.
5. Copies the templates to your personal files: `wiki/context.md`, `wiki/index.md` and `wiki/log.md` from their `.example.md` versions, `trade_log.md` and `backtest/averaging_config.json`. All of them are gitignored.

Options: `-McpPath D:\somewhere` to put the MCP server elsewhere, `-SkipBacktest`, `-SkipMcp`, and `-DryRun` to see what it would do without changing anything.

Two things are left to do by hand, once:

1. Open TradingView Desktop and log in. Open the Pine Editor, paste the contents of `wallstreetpro_v3_unified.pine`, save it and add it to a chart.
2. Open `wiki/context.md` and replace the example numbers (USD 10,000 of trading capital, no positions) with your own.

## Running the weekly check

The rules call for one analysis a week, on Monday after the New York close.

Run `WALLSTREETPRO_START.bat`. It closes any open TradingView window, restarts it with `--remote-debugging-port=9222`, waits for the port, runs the screener and opens Claude Code in this folder with the first message already typed: `Read daily_brief.md and run it end to end`.

Claude then checks the market regime on SPY, reads your state file, looks for a name that closed above its 10-session high, runs the five guardrails and prints a short report. If the verdict is BUY, the report includes the exact order to enter at your broker. You place it. Claude never does.

Other prompts that work inside that session: `Analyze <TICKER>`, `How is <TICKER> doing?`, `Can I buy today?`.

The screener's sizing columns default to the example capital. To use your own numbers, set `WSP_CAPITAL` and `WSP_CASH` in your environment, or run `screener.ps1 -Capital 25000 -CashAvail 8000`.

## How the project remembers: an LLM wiki

Claude Code starts every session with no memory, so the project keeps one for it in `wiki/`, following Andrej Karpathy's "LLM Wiki" pattern. `CLAUDE.md` is the schema. `wiki/context.md` is the only page loaded in every session, with a hard budget of 6,000 characters: capital, positions, resting orders, deadlines. Everything else lives in one page per position or study, listed in `wiki/index.md`, with the dated history in an append-only `wiki/log.md` that Claude Greps instead of reading.

At the end of a session with something new, Claude updates the page, the index, the log and, only if every future session needs it, the context. Corrections are dated and propagated to the index and the context, so a stale claim stops being the one that gets loaded. `python wiki/lint.py` checks links, orphan pages, the budget and frontmatter.

Everything you write under `wiki/` is gitignored; the repo ships only the templates and the lint. The design, the community ideas it borrows and why: [docs/llm-wiki.md](docs/llm-wiki.md).

## The averaging check

The one rule people most want to break is C8, never average down. `backtest/averaging_check.py` answers "should I add to this loser, and at what price?" with numbers instead of hope:

```powershell
backtest\.venv\Scripts\python.exe backtest\averaging_check.py PLUG
```

It finds every past episode, in a universe of similar names, that was in the same state as your position today (far below its EMA50, deep under its 252-day high, in a Death Cross). On each one it replays doing nothing, several buy plans (limits, tranches by drop size, buying on an EMA21 reclaim, buying at market) and several exit plans, and compares every outcome with putting the same money in an index fund. It also prints the one-year trough distribution, the technicals of the day and how the RSI at entry changed the result.

The verdict follows a criterion written into the code before the first run. A plan is opportune only if, in every cohort with at least 30 episodes, it beats a fair bet (buy price divided by the new breakeven) by 5 points, beats the index fund after a 10% bankruptcy haircut, and helps more often than it hurts. The position and the plans to test go in `backtest/averaging_config.json`; the example is made up.

Two limits are printed with every result: the cohorts contain only survivors, and overlapping episodes make the effective sample smaller than the count.

## Running the backtest

```powershell
backtest\.venv\Scripts\python.exe backtest\backtest_wsp.py
```

It downloads daily bars for the 468 symbols in `backtest/universe.txt` from Yahoo Finance, simulates the system as written at v4.5 plus 36 variants, prints the results as JSON and writes them to `backtest/results.json`. A full run takes about 7 minutes. Bars are cached in `backtest/.cache`, so a second run is offline. `--help` lists the options.

It ends by checking the baseline against the pass criterion, which is hardcoded:

```
Verdict for A_system_v45_as_written:
  [FAIL] expectancy > +0.15R with n >= 1000: exp -0.1063R, n 5650
  [FAIL] t > 2: t -5.15
  [FAIL] alpha > +0.10R: alpha -0.151R
  [FAIL] positive in 8 of 12 years: 2 of 12
  => SYSTEM FAILS
```

That output is from my run on 16 November 2026. The numbers quoted in the next section are from the original audit run on 4 September 2026, which used the JavaScript engine in `backtest/backtest_wsp_browser.js`. The two runs agree on every conclusion and differ in the second decimal, mostly because Yahoo restates history. `docs/backtest-findings.md` has both side by side.

## What the backtest showed, and how it led from v4.5 to v5

By v4.5 the system had ten guardrails, two entry patterns and a three-step exit. Each rule had a reason, usually one bad trade. A backtest gate had been on the to-do list for two months, and two versions shipped without it.

When it finally ran, over 5,533 trades on 446 tickers from 2015 to 2026:

| Pass condition, written before the run | Needed | Measured |
|:---|---:|---:|
| Expectancy net of costs | > +0.15R | -0.096R |
| Student's t | > 2 | -4.47 |
| Alpha against SPY over the same holding period | > +0.10R | -0.139R |
| Years with positive expectancy | 8 of 12 | 3 of 12 |

Losing was not the main finding. Three others were:

- **Alpha was zero everywhere.** Across 12 combinations of stop width and holding period, alpha ranged from -0.023R to +0.018R, with a standard error of 0.03 to 0.05R. Whatever the system earned in its better configurations was market beta.
- **The control beat the system.** Buying any name from the screener at the next open, with no pattern and no guardrails, returned +0.216R. The full rule set returned less than no rules at all.
- **The filters selected the wrong side.** Names with "clean air" above them, the ones the ceiling rules approved, returned -0.167R. Names the rules vetoed returned +0.269R.

The run also priced each rule separately:

| Rule | Cost per trade |
|:---|---:|
| Buy-stop entry above yesterday's high, against a market-on-open order | 0.085R |
| Time-based partial exit | 0.137R |
| Stop moved to breakeven | 0.025R |
| Trailing stop at 2.5x ADR | 0.088R |

So v5 is mostly deletions:

| | v4.5 | v5 |
|:---|:---|:---|
| Entry | Buy-stop above yesterday's high, two patterns | Market-on-open the next session, one pattern |
| Stop | 0.5 to 1.0x ADR, vetoed if wider than 1.5x ADR or 8% | Fixed at 1.5x ADR, never moved |
| Exit | Partial, then breakeven, then trailing stop | The stop, or a sale on a fixed date 20 sessions out |
| Guardrails | 10 | 5 |
| Cadence | One analysis and one review a week | One analysis a week, about 20 minutes |

What stayed is what the audit measured as useful or correct: the screener and its universe, the SPY regime filter, the limit on distance from EMA50, the earnings filter and the rule against averaging down.

v5 measures +0.073R per trade with an alpha of +0.003R. That is not an edge, and the docs say so. The system now runs as a test of execution: the primary metric is the share of approved orders that actually reach the broker, and there is a kill criterion at 20 closed trades. The reason to keep it is that a zero-alpha system with a stop and a calendar date still beats buying on impulse.

The full write-up, with the method, the limitations and the declared biases, is in [docs/backtest-findings.md](docs/backtest-findings.md). The versioned changelog (C1 to C8, D1 to D10, E1 to E5) is at the top of [trading_system.md](trading_system.md).

## Repository layout

| Path | What it is |
|:---|:---|
| `CLAUDE.md` | Operating instructions Claude Code loads at the start of every session |
| `trading_system.md` | The full rules and the changelog |
| `daily_brief.md` | The script of the weekly check. The name is historical: the check was daily until v4.1 |
| `indicator_visual_guide.md` | How to read the chart and the indicator |
| `wiki/` | The project's memory: templates (`*.example.md`) for the context, index, log and a sample page, and `lint.py`. Your own pages stay local |
| `trade_log.example.md` | Template for your trade log |
| `wallstreetpro_v3_unified.pine` | The TradingView indicator |
| `screener.ps1` | The universe screener |
| `setup.ps1`, `SETUP.bat` | One-time setup |
| `WALLSTREETPRO_START.bat` | Weekly launcher |
| `backtest/` | Python engine, the original JavaScript engine, the universe file, and the averaging check with its example config |
| `docs/backtest-findings.md` | The audit behind v5 |
| `docs/llm-wiki.md` | How the wiki works and where its ideas come from |
| `.claude/settings.json` | Pre-approves the TradingView MCP tools and file reads, so the check runs without a permission prompt per call |

`CLAUDE.md` and `.claude/settings.json` are committed on purpose. The system is a Claude Code project, and those two files are part of how it runs. The permission list covers the MCP server's chart and UI automation tools as well as its read tools. If you have a broker connected inside TradingView, review that list before using it.

## Notes and known gaps

- **Windows only for the automation.** The backtest is plain Python and runs anywhere. The screener should run under PowerShell 7 on macOS or Linux, and the MCP server ships its own launch scripts for those systems, but I have not tested either.
- **The screener still prints two things from before v5:** a first ranking by closeness to the 6-month high, and a `Pat` hint column. v5 uses the universe, the `ADR` column and the `Coil` ranking. The script header documents each decision.
- **The backtest has optimistic biases:** survivorship in the universe, a universe chosen with current data, and no earnings filter. The system fails with those in its favor.
- **The signal is not automated.** "Closed above the 10-session high" is checked by Claude on the bars of each candidate, not by the screener.
- This is a cleaned-up publication of a private project. State files, trade history and broker data are not here, and the Git history starts at this release.

## Author and license

Pablo Monticoli. Released under the [MIT License](LICENSE).

## Disclaimer

This project is for educational purposes. It is not financial or investment advice, and nothing here is a recommendation to buy or sell any security. The system never executes trades: it has no broker connection and no code that places, modifies or cancels an order, and every trade is a manual decision by the person using it. The backtest in this repo found that the strategy has no measurable edge. Trading involves risk of loss, and you are responsible for your own decisions.
