# CLAUDE.md: WallStreetPro v5 "Fewer rules, measured"

Trading analysis system. Rules last changed on 4 September 2026.

**What happened on that date:** the backtest that §BT had been asking for was finally run. 5,533 simulated trades, 2015 to 2026, 446 tickers, commissions and slippage modelled from real fills. Report: `docs/backtest-findings.md`. Code: `backtest/backtest_wsp.py`.

v4.5 failed all FOUR pass conditions, which were written inside the code before running it:
expectancy -0.096R (needed > +0.15R), t -4.47 (needed > 2), alpha -0.139R (needed > +0.10R), 3 of 12 years positive (needed 8 of 12).

**The central finding is not that it loses.** Across the 12 configurations of stop and holding period that were tested, ALPHA against SPY ranges from -0.023R to +0.018R: all indistinguishable from zero. And the control (buy any screener name at the open, with NO pattern and NO guardrails) returns +0.216R, BETTER than the full system. The system selected nothing: it took beta, loaded it with costs and degraded it with its exits. An index ETF delivers that same beta with none of it.

**Changes v4.5 to v5** (one line each, detail in `trading_system.md` §0.2):

- **E1 Entry:** `MKT` order with `TIF = OPG` at the next open. The buy-stop is DELETED (it cost 0.085R and filled at the 64th percentile of the day's range; the order at the open fills at the 53rd).
- **E2 Pattern A (pullback) DELETED:** alpha -0.062R over 27,213 signals. One pattern is left, the breakout.
- **E3 Exit:** only a GTC STOP plus a sale on a fixed date, 20 sessions out. DELETED: the time-based partial (0.137R), the breakeven stop (0.025R) and the 2.5x ADR trailing stop (0.088R). Together they destroyed 0.250R per trade.
- **E4 Guardrails from 10 to 5.** DELETED: R/R to the first ceiling, D8, all of D9, the stop-width veto, the volume filter and anti-chase (D4).
- **E5 Stop FIXED at 1.5x ADR20.** No 8% cap, no 0.5x floor, no veto for width.

**KEPT, because the audit measured it as useful or correct:** the screener and the universe (D10), the SPY > EMA50 > EMA200 regime (the only filter that adds anything), dist EMA50 <= 15%, no earnings within 5 days, C8 never average down (sacred), the ban on leveraged and inverse products, D3 (ETF with ADR < 2% gets a stop of at least 2x ADR), and all the arithmetic of ADR, EMAs, pivots and capital.

**The honest part about v5:** it measures +0.073R with alpha +0.003R, under 1R a year at one position at a time. IT IS NOT A SOURCE OF RETURN. It is run as an EXECUTION TEST with a kill criterion at 20 trades, and because a zero-alpha system is still worth having if it prevents impulse buying.

---

## TYPE OF PROJECT: READ FIRST

This is NOT a software project. It is a personal trading analysis system.

Claude's role: run the weekly check and give an unambiguous **BUY / NO BUY** verdict, with a concrete entry, stop and exit date. The operator places EVERY trade by hand at their broker. Claude NEVER executes trades and never accesses accounts.

---

## v5 PHILOSOPHY: THE SYSTEM DOES NOT MAKE YOU WIN, IT KEEPS YOU FROM LOSING

1. **The primary metric is EXECUTION, not P&L.** Approved orders that reached the broker divided by approved orders. With the measured variance, P&L over 8 weeks distinguishes nothing (it would take 1,097 trades). The execution rate is measured with n = 10. The scoreboard is in `current_state.md`.
2. **No decision with the market open.** Everything is decided after the close and executed with resting orders. In one real case, deliberating for three hours with the market open raised the risk per share by 33%.
3. **Fewer rules, not more.** Every bad result used to add a veto (D8, D9 and D10 each came out of a single case) and none was ever removed. That is how the system reached 10 guardrails that produced 1 approval a week on a ONE-position account, and the one that got through was the most extended of the group.
4. **NEVER average down (C8).** Your own average price is not an input to a buy. It is the one rule that real losses prove beyond discussion.
5. **One position at a time.** Cash account, T+1. The "book of up to 3 resting orders" was fiction and was deleted.

---

## DATA SOURCE: CRITICAL

TradingView MCP: tools named `mcp__tradingview__*`, served by the third-party `tradingview-mcp-jackson` bridge over CDP on port 9222.

- TradingView Desktop is launched by `WALLSTREETPRO_START.bat`. Run `tv_health_check` before the first data point.
- Indicator: title `WallStreetPro v3 Unified` (source in `wallstreetpro_v3_unified.pine`). For `pine_open`, use the name it was saved under in the operator's TradingView account.
- It exposes in the data window: **`ADR20 %`**, `RSI`, `MACD hist`, `Vol ratio med x`, `Dist EMA50 %`, `EMA21 val`, `EMA50 val`, `EMA200 val`.
- **ADR20 is NEVER computed by hand.** It comes from the `ADR` column of `watchlist_screener.md` or from the `ADR20 %` field of the indicator. `data_get_ohlcv` is used only for the 10-session high.
- **Validate the crosshair before using the data window.** `data_get_study_values` follows the cursor. Mandatory check: `EMA50 val` consistent with `quote_get`. Also, `chart_set_symbol` does not change the symbol `quote_get` reports until the chart is ready: it has returned the previous ticker's quote labelled as the new one.

---

## v5 CADENCE: ONE analysis a week

**Monday after the New York close (16:00 ET).** Nothing else.

- No Thursday review. No daily check. Never with the market open.
- Between Monday and Monday **there is nothing to decide**: one possible order, a GTC stop at the fill and a fixed exit date 20 sessions out.

---

## PROJECT FILES

| File | Purpose |
|:---|:---|
| `current_state.md` | **Volatile data: capital, 1R, open position, resting orders, dates. ALWAYS read it first.** Gitignored; created from `current_state.example.md` |
| `trading_system.md` | Full v5 rules. §0.2 changelog, §2.3 entry, §2.4 guardrails, §2.6 exit, §BT, §MET |
| `daily_brief.md` | Script of the weekly check, runnable end to end. The name is historical: the check was daily until v4.1 |
| `docs/backtest-findings.md` | **The audit that produced v5. The source of every number in this file** |
| `backtest/` | `backtest_wsp.py` (reproducible engine), `backtest_wsp_browser.js`, `universe.txt` |
| `indicator_visual_guide.md` | How to read the chart and the indicator |
| `wallstreetpro_v3_unified.pine` | The single indicator (Pine) |
| `screener.ps1` -> `watchlist_screener.md` | Wide-funnel screener (§2.7, D10 intact). The output is gitignored |
| `trade_log.md` | **Closed trades with MAE/MFE. The basis of the kill criterion (§MET).** Gitignored; created from `trade_log.example.md` |

Capital, 1R, the open position and key dates are in `current_state.md`. Read it at the start of every session. Do not duplicate it here.

---

## THE v5 SETUP: ONE SIGNAL, ONE ORDER

**Pre-filter:** SPY > EMA50 > EMA200 (if not, the week is skipped entirely), price > EMA50 > EMA200, dist EMA50 <= 15%.

### The only signal: continuation breakout
- **Price closes above the high of the previous 10 sessions.** Read on the closed candle. Nothing else.
- **RSI and volume are context, never a veto.** No floor and no ceiling.
- If there is more than one candidate, break the tie by **`Coil`** (1-month range divided by ADR), lowest first. **Ranking by clean air is gone:** it selected the subset with an expectancy of -0.167R.

### Entry
- **`MKT` order with `TIF = OPG`** (market-on-open) for the next session, placed on Monday after the close.
- The fill price **is not known in advance**: size on Monday's close with a **20% cushion**.
- A bracket IS allowed on this order, because it is an entry. NEVER on a position already held: some brokers generate the attached legs on the wrong side.

---

## THE GUARDRAILS: FIVE, NOT TEN

1. **SPY above EMA50 and EMA50 above EMA200.** If not, the week is skipped entirely.
2. **STOP = 1.5x ADR20 below the fill**, as a GTC `STOP`, placed the same day. No 8% cap, no 0.5x floor, no veto for width. **It is NEVER moved: not down, not to breakeven, not to a trailing stop.**
   Exception D3: ETF with ADR < 2% (broad index, gold) gets at least 2.0x ADR or the 5-10 session swing low, whichever is farther.
3. **No earnings in the next 5 days or so** (stocks). ETFs have none.
4. **dist EMA50 <= 15%.**
5. **NEVER AVERAGE DOWN (C8)**, on any position. That includes legacy positions bought on impulse (§EC) and every leveraged or inverse ETF.

Signal plus the 5 = **BUY**. One missing = **NO BUY**. **There is no WAIT category.**

### Guardrails DELETED on 4-Sep-2026, with the number that killed each

| Deleted | Measurement |
|:---|:---|
| **R/R >= 1.5 to the first real ceiling** | it only let through names in clean air, the **-0.167R** subset; the ones it vetoed returned **+0.269R** |
| **D8 (rejected multi-year high)** | same criterion, inverted. Kept as a context note, not as a veto |
| **D9 (ceiling on three scales: monthly, weekly, daily)** | half an hour per name in the service of an inverted criterion |
| **Veto on a stop wider than 1.5x ADR or 8% absolute** | it blocked 80% of the signals; wider stops do better |
| **D2 (0.5x ADR floor and widening)** | the stop is fixed at 1.5x ADR: nothing to widen |
| **D4 (anti-chase by pattern)** | it depended on pattern A and on the buy-stop, both deleted |
| **Volume >= 1.3x the median** | never executable on the candle that fills |
| **Book of 3 resting orders and 6% aggregate risk (D5)** | cash account, T+1: **one position at a time**. The book was fiction |

---

## THE EXIT: TWO ORDERS AND NOTHING ELSE

1. **At the fill: GTC `STOP` at 1.5x ADR20 below the fill.** That same day.
2. **At 20 sessions: sell at market, on a fixed date**, written on the calendar on the day of the fill.

**DELETED:** partial of 1/2 on day 3-5 (**cost 0.137R**), stop to breakeven (**0.025R**), 2.5x ADR trailing stop (**0.088R**), time stop at 8-10 sessions. **The first three destroyed 0.250R per trade, more than any entry generates.**

> **Breakeven was the one that hurt most in practice.** On a name with an ADR of 4-5%, a stop at the entry price is inside the noise of a normal day: it takes you out on the first pullback and turns winners into zeros.

---

## v5 VALIDATION LOOP: four points, not eight

1. SPY > EMA50 > EMA200? If not, the week ends here.
2. Did any name close above the high of its previous 10 sessions, with price > EMA50 > EMA200 and dist EMA50 <= 15%?
3. Does it pass the 5 guardrails? Does the notional, with the 20% cushion, fit in the available cash?
4. Are the stop (1.5x ADR) and the sale date (20 sessions) defined?

All four YES = **BUY**, and the order is placed TODAY. Any NO = **NO BUY**.

---

## COMMON ERRORS: NEVER DO THESE

- Forgetting `tv_health_check` at the start.
- **Using v4.x rules.** If something in an older passage contradicts §2.3, §2.4, §2.6, §BT or §MET of `trading_system.md`, **it is repealed**. The changelogs are history, not rules.
- **Looking for ceilings on the monthly or weekly chart to compute an R/R.** DELETED: the criterion was inverted.
- **Placing a buy-stop above yesterday's high.** DELETED: it fills high in the range and costs 0.085R.
- **Taking a partial, moving the stop to breakeven or adding a trailing stop.** DELETED: 0.250R per trade.
- **Rejecting a trade because the stop is wide.** The stop is fixed at 1.5x ADR and is not up for a vote.
- **Ranking by "clean air" or by distance to the 6-month high.** It selects the negative-expectancy subset.
- **Giving a WAIT verdict.** It does not exist: BUY or NO BUY.
- Running the analysis with the market open. Running the check every day. Doing a Thursday review.
- Computing ADR20 by hand.
- Using the data window without validating the crosshair against `quote_get`.
- Moving the stop down. Averaging down (C8). Buying within about 5 days of earnings.
- Re-buying a legacy position by looking at its average price instead of analyzing it as a new trade (§EC).
- Gating a trade on a minimum capital. The operator decides the amounts.
- **Leaving the analysis in a file without placing the order at the broker.** Execution is the primary metric of the system (§MET), not an administrative detail.
- Running a backtest by reasoning about past prices instead of running `backtest/backtest_wsp.py`.

---

## TRIGGER COMMANDS

| What the operator types | What Claude does |
|:---|:---|
| "Read daily_brief.md and run it end to end" | The full weekly check (Monday after the close) |
| "Analyze [TICKER]" | Pre-filter, did it close above the 10-session high, 5 guardrails, order, stop and date |
| "How is [TICKER] doing?" | Price against the fill, distance to the stop, day n of 20 |
| "Can I buy today?" | SPY regime and available trading cash |
