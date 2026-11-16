# WEEKLY CHECK: WallStreetPro v5 "Fewer rules, measured"

ONE analysis a week, Monday after the close, about 20 minutes.
The file is still called `daily_brief.md` because the check was daily until v4.1.

**Why everything changed** (`trading_system.md` §0.2): the backtest in §BT ran over 5,533 trades (2015 to 2026). v4.5 failed all four pass conditions: expectancy -0.096R, t -4.47, alpha -0.139R, 3 of 12 years positive. Across 12 configurations, ALPHA is zero. The system did not select, it took beta. Measured control: buying any screener name at the open, with NO pattern and NO guardrails, returns +0.216R.

- E1 Entry: `MKT` order with `TIF = OPG`. The buy-stop is deleted (it cost 0.085R).
- E2 Pattern A deleted (alpha -0.062R over 27,213 signals). One pattern is left.
- E3 Exit: only a GTC STOP plus a sale on a fixed date 20 sessions out. Partial, breakeven and trailing are deleted (together they destroyed 0.250R per trade).
- E4 Guardrails 10 to 5. Deleted: R/R to the ceiling, D8, D9, stop-width veto, volume, anti-chase.
- E5 Stop fixed at 1.5x ADR20. No 8% cap, no 0.5x floor, no veto for width.

v5 measures +0.073R with alpha +0.003R. It is NOT a source of return. It is an EXECUTION TEST with a kill criterion at 20 trades (§MET).

---

## CADENCE: one analysis a week

**Monday after the New York close (16:00 ET).** Volume and the day's high are closed and final.

- **No Thursday review.**
- **No daily check.**
- **Never with the market open.** In one real case the analysis ran mid-session, the decision was made three hours later, and the 1R per share had grown by 33% in the meantime.

**Why there is nothing to do between Monday and Monday:** one possible order, a GTC stop placed at the fill and a fixed exit date. No book to requote, no partial to watch, no moving average to look at.

---

## INSTRUCTION FOR CLAUDE CODE

Run the steps in order. Do not wait for further instructions.
SOURCE: TradingView MCP (CDP 9222). Run `tv_health_check` before the first data point.

> **Before using the data window, validate the crosshair.** `data_get_study_values` reads the data window, **which follows the cursor**. Mandatory check: `EMA50 val` consistent with `quote_get`. If they do not agree, read again. And `chart_set_symbol` does not change the symbol `quote_get` reports until the chart is ready.

---

## STEP 1: DOES THE MARKET ALLOW TRADING? (SPY)

`tv_health_check`, then `chart_set_symbol("SPY")`, then `data_get_study_values`.

| Data | Value |
|:---|:---|
| SPY, EMA50, EMA200 | $ / $ / $ |
| Regime | GREEN: SPY > EMA50 > EMA200. RED: anything else |

- **RED: THE WEEK IS SKIPPED ENTIRELY.** The check ends here. Report the regime and the state of the open position, and nothing else.
- GREEN: continue.

> It is the **only filter the audit measured as adding anything**, because what the system earns is beta and the regime is the only thing that modulates it. That is why it is binary and has no yellow zone.

---

## STEP 2: LOAD THE STATE

Read `current_state.md`: the open position (if any) with its 20-session sale date, available trading cash, 1R in dollars, legacy positions, key dates.

---

## STEP 3: IS THERE A SIGNAL?

Read `watchlist_screener.md` (the `.bat` regenerates it). The universe already comes filtered by D10 and is not touched.

**The signal, and nothing else:**

> **Did any name CLOSE TODAY above the high of the previous 10 sessions?**

If there is more than one, break the tie by **`Coil`** (1-month range divided by ADR), **lowest first**. Ranking by clean air is gone: it selected the subset with an expectancy of **-0.167R**.

Confirm the 10-session high and the close of the candidate with `data_get_ohlcv(11)`.

### The 5 guardrails (§2.4). All of them, or NO BUY

| # | Guardrail | Pass? |
|:--|:---|:--|
| 1 | SPY > EMA50 > EMA200 (already checked in step 1) | |
| 2 | Stop = **1.5x ADR20** below the fill (ADR from the screener or the Pine indicator, **never by hand**) | |
| 3 | No earnings in about 5 days (stocks; ETFs have none) | |
| 4 | dist EMA50 <= 15% | |
| 5 | Not averaging anything down (C8), not a legacy position on impulse, nothing leveraged or inverse | |

### The trade sheet

| Field | Value |
|:---|:---|
| Ticker, today's close | |
| High of the previous 10 sessions (the one it broke) | $ |
| **ADR20 %** (from the screener or the Pine indicator) | % |
| **1R per share = 1.5 x ADR20 x price** | $ |
| **Shares = 1R in dollars (from `current_state.md`) / 1R per share**, rounded down | |
| Estimated notional (close x shares) **plus the 20% cushion** | $ |
| Does it fit in the available trading cash? | yes / no |
| Earnings | days |
| dist EMA50 | % |
| **VERDICT** | **BUY / NO BUY** |

> **If the notional does not fit in the cash, the name is SKIPPED.** The stop is never tightened to make it fit.
> **There is no WAIT category.** Either the signal is there and it passes the 5, or there is no trade this week.

**If it is a BUY, the order is placed TODAY, in the same session.** An analysis that ends in a file and not at the broker is worth zero. Update the execution scoreboard in `current_state.md` (§MET).

### The order, exactly as it is entered at the broker

```
BUY  <n> sh <TICKER>   Order type: MKT   TIF: OPG      <- entry, for tomorrow's open
```

- **The fill price is not known in advance.** That is what the 20% cushion is for.
- Check that it is routed so that it takes part in the opening auction.
- **A bracket IS allowed on this order**, because it is an ENTRY. Never on a position already held.

---

## STEP 4: AT THE FILL (Tuesday, 2 minutes)

1. **Place the GTC `STOP`** at `fill - 1.5x ADR20`, for the full quantity.
2. **Write the 20-session sale date on the calendar.**
3. **Open the row in `trade_log.md`** with entry, stop, ADR20, the ADR multiple and the table of levels in R.

Nothing else. **The stop is never moved: not down, not to breakeven, not to a trailing stop.**

---

## STEP 5: OPEN POSITION AND LEGACY POSITIONS

**Open position (if any):** price against the fill, distance to the stop, **days elapsed of the 20**. Nothing to decide: the only possible action is to sell on day 20.

**On closing (by stop or by date):** add the row to `trade_log.md` with MAE and MFE in R, realized R, commission and process violations. **Then recompute the expectancy against the kill criterion (§MET): at 20 closed trades, if it is negative, the trading capital is closed and everything goes to a broad index ETF.**

**Legacy positions (if `current_state.md` lists any):** price and distance to their resting sell orders. **Averaging is PROHIBITED (C8).** A re-buy is only possible as a new trade that passes v5 in full, ignoring the average price and the existing shares (§EC).

---

## STEP 6: CALENDAR OF THE WEEK

| Day | Event (FOMC, CPI, NFP, holiday, earnings) | Action |
|:---|:---|:---|

No events: "Clean week."

---

## OUTPUT TEMPLATE: the ONLY thing that gets printed

> **Length:** no trade, at most 120 words. With a trade, at most 250.
> **Order:** by the DECISION, not by the steps. No "STEP 1-6" headings in the output.
> **Verdict:** on the first line, before the nuances. If it needs two `AGAINST` lines, it is a NO BUY.

```
=== WSP v5 <date> <time ET> ===
REGIME   GREEN/RED SPY <price> (EMA50 <x> / EMA200 <y>)
ACTION   <"NOTHING" | "PLACE: <TICKER> MKT/OPG <n> sh" | "AT THE FILL: GTC stop $Y + sell on <date>">
```

**If ACTION = NOTHING, stop here. Two more lines at most:**

```
POSITION <TICKER: +X.X%, stop $Y, day <n>/20, sells on <date>>  |  no positions
DISCARDS <n> names, dominant reason: <one>
```

**If ACTION = PLACE, one line per field:**

```
VERDICT  BUY <ticker>: closed $<c> above the 10-session high $<p>
ORDER    BUY <n> sh, MKT, TIF OPG  (estimated fill ~$<c>, 20% cushion)
STOP     $Y = 1.5x ADR20 (<adr>%) -> 1R = $<r> per share, $<R> total
EXIT     GTC stop $Y  +  sell at market on <date, 20 sessions>
AGAINST  <the one real objection, one line. If there are two, it is a NO BUY.>
```

**What does NOT go in the report:** the list of discards with reasons (one aggregate line), a justification paragraph per candidate, a P&L snapshot (that is state, not news), tables with more than 5 columns.

---

> **v5 REMINDER.** The goal of this stage **is not to make money**: the measured edge is under 1R a year. The goal is to **execute 20 complete trades** and answer the one question the backtest left open: whether the operator can execute a system, any system. The second reason to keep it is that a zero-alpha system **is still worth having if it prevents impulse buying**.
