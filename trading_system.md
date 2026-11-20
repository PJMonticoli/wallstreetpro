# WallStreetPro: trading system rules

Version 5 "Fewer rules, measured", 4 September 2026.
Replaces v4.5, v4.1 and v4.0, which the backtest in §BT invalidated.

Section numbers (§2.3, §BT, §MET and so on) are stable. `CLAUDE.md` and `daily_brief.md` refer to them.

---

## §0.2 Changelog v5 (4-Sep-2026): the backtest was run and v4.5 did not pass

**What happened.** The gate in §BT had been "pending execution" for two months, and two full versions went past it. It was finally run over **5,533 simulated trades, 2015 to 2026, 446 tickers**, with commissions and slippage modelled from real fills. Report: `docs/backtest-findings.md`.

**What it measured.** v4.5 has an expectancy of **-0.096R** (t = -4.47) and loses in 9 of 12 years. The central finding is not that it loses. Across **12 configurations** of stop and holding period, **alpha against SPY ranges from -0.023R to +0.018R, all of them indistinguishable from zero**. And the control (buy any screener name at the open, with no pattern and no guardrails) returns **+0.216R**, better than the full system with its 10 guardrails. **The system selected nothing. It took beta, loaded it with costs and degraded it with its exits.**

**The five changes, one line each:**

| # | Change | The number behind it |
|:--|:---|:---|
| **E1** | Entry: **`MKT` order with `TIF = OPG`** instead of a buy-stop above yesterday's high | +0.085R; the fill moves from the 64th to the 53rd percentile of the day's range |
| **E2** | **Pattern A (pullback) DELETED.** One pattern is left, the breakout | alpha **-0.062R** over 27,213 signals |
| **E3** | Exits: **only a GTC stop plus a sale on a fixed date, 20 sessions out** | partial 0.137R + breakeven 0.025R + trailing 0.088R = **0.250R destroyed per trade** |
| **E4** | Guardrails from **10 to 5**. Deleted: R/R to the first ceiling, D8, D9, the stop-width veto, the volume filter, anti-chase | names with "no ceiling overhead" return **-0.167R**; the ones the system vetoed, **+0.269R** |
| **E5** | Stop **fixed at 1.5x ADR**, no 8% cap, no 0.5x floor | wider stops do better (-0.096R at 1.0x against -0.058R at 2.5x) |

**What is KEPT, because the audit measured it as useful or correct:** the screener and the universe (D10), the SPY > EMA50 > EMA200 regime filter (the only filter that adds anything), `dist EMA50 <= 15%`, no earnings within 5 days, C8 (never average down), the ban on leveraged and inverse products, and all the arithmetic of ADR, EMAs and capital, which the audit verified.

**The honest part about v5:** it measures **+0.073R with alpha +0.003R**. One position at a time and a 20-session hold allow about 12 trades a year, so that is under 1R a year: less than a T-bill ETF pays for no risk and no work. **It is not a source of return.** It is run as an **execution test** with a kill criterion at 20 trades (§MET), and because a zero-alpha system is still worth having if it prevents impulse buying, which is what did the real damage before the system existed.

> The changelogs below (§0.15, §0.1, §0) are **history, not rules in force**. Anything in them that contradicts §2.3, §2.4, §2.6, §BT or §MET is repealed.

---

## §0.15 Changelog v4.2 to v4.5 (31-Aug to 3-Sep-2026): the last patches before the backtest

Four versions in four days. Each one fixed a real problem, and three of them added a veto. v5 kept the fixes and deleted the vetoes.

- **v4.2, technical audit.** ADR20 and the volume ratio are computed by the indicator and the screener, never by hand: a hand calculation had used 15 bars instead of 20 on five tickers with nothing catching it. The volume ratio moved from the 20-day mean to the 20-day median, which an earnings gap does not distort. The data window must be validated against a live quote before use, because it follows the cursor. Exits became resting orders instead of daily monitoring. The screener moved from "close to the 52-week high" to relative strength.
- **D8 (v4.2). R/R against the first REAL ceiling, and never buy into a multi-year high that already rejected price.** The ratio against an arithmetic 2R says nothing if there is a wall in between. It came from one real case of a name glued to its 52-week high, sitting right under an older ceiling with two failed attempts. **Deleted in v5 as a veto**, kept as a context note.
- **D9 (v4.3). The ceiling is searched on three scales: monthly, weekly and daily**, and the verdict is not written until every validation point has run. A weekly high hidden inside a monthly bar is invisible on the monthly chart. It came from one real case delivered as a BUY while sitting in the middle of a 3-month range. The screener gained the 3-month range position and its 35-65% dead zone. **Deleted in v5.**
- **D10 (v4.4). The universe was too small, and it was measured:** the funnel held 174 of 11,744 stocks, 1.5% of the market. Both floors were re-derived from the rules instead of from old assumptions: ADR floor 4.0% to 2.5%, price band 15-80 to 10-150. The funnel went to 626 names (5.3%) and gained a sleeve of thematic ETFs selected by an explicit allowlist. Lesson attached to it: being close to the 6-month high is not proof of clean air if the name just fell from there. **D10 is KEPT in v5:** it defines the universe, not the buy.
- **v4.5.** The scanner request was capped at 500 rows while the API returned 621, so 121 in-band names were dropped silently, and the ones dropped were the lowest relative strength, where quiet pullbacks live. The cap went to 3000. The screener gained the `Coil` column (1-month range divided by ADR) and a second ranking by it.

**The pattern worth remembering:** D8, D9 and D10 each came out of a single bad result, and no rule was ever removed. One new veto per bad event is how the system reached 10 guardrails that produced one approval a week on a one-position account, and the name that got through was the most extended of the group.

---

## §0.1 Changelog v4.1 "Momentum with volatility" (second external audit, July 2026)

**The root bug the second audit found:** v4.0 copied Qullamaggie's stop multiplier (at most 1x ADR) **without copying his universe filter (ADR of 5-6% or more)**. The screener brought in defensive large caps with an ADR near 2% (utilities, banks, railroads), where an ADR-based stop sat inside the noise and a 2R target was almost unreachable. That single error explained all three symptoms: it never fired, when it fired the stop was hit by noise, and running the check every day for nothing wore the operator down.

- **D1. ADR filter on the universe:** the screener requires a minimum ADR%, dollar volume of at least $20M a day and a market cap of at least $500M.
- **D2. A stop that can be widened instead of a veto:** `stop < 0.5x ADR -> NO BUY` was a rule with no source that dried up the funnel. The stop is widened and the size is cut instead.
- **D3. Stop by the volatility of the instrument:** for an ADR20 below 2% (broad index and gold ETFs), the minimum stop is 2.0x ADR or the 5-10 session swing low, whichever is farther. The "at most 1x ADR" rule was meant for names with an ADR of 5-8%, not for indexes. It came from a real stop-out on an index ETF caused by noise alone.
- **D4. Anti-chase by pattern:** "3 or more green days" applies to the pullback pattern only; the breakout measures distance to the pivot (entry at most 5% above the break).
- **D5. A book of resting orders and a weekly cadence:** from a daily check to one analysis a week plus one review, with up to 3 live buy-stops and an aggregate risk cap of 6%.
- **D6. Trade log with MAE/MFE, §MAE, and the backtest as a gate:** instrumentation to tell bad luck from a badly calibrated rule. Thresholds stay provisional until the backtest in §BT.
- **D7. Income ETFs excluded for tax drag:** dividend and covered-call ETFs force a taxable distribution every year. Where dividends are taxed at source for the operator, that costs 1 to 3 points a year against a total-return equivalent. Long-term capital goes to a broad index ETF; idle trading cash goes to a T-bill ETF.

---

## §0 Changelog v4.0 (external audit: Qullamaggie, Stockbee, Minervini, small-account literature)

**The problem with v3.8:** it still did not fire (a universe of 20 mega and large caps correlated with SPY returned "NO BUY" as a block), and when it fired it lost, because a fixed percentage stop of 2-4% sat INSIDE the daily noise of the ticker and the pullback pattern bought the first bounce with no confirmation. Root cause: small universe, stops inside the noise, unconfirmed entries.

- **C1. Dynamic universe:** fixed watchlist of 20 names replaced by a weekly relative-strength screener (§2.7).
- **C2. Stop by structure and ADR:** fixed 2-4% stop replaced by the low of the entry day, validated at 0.5 to 1.0x ADR20.
- **C3. Confirmation and anti-chase:** the pullback pattern enters above yesterday's high with a buy-stop, never after 3 or more green days.
- **C4. RSI demoted:** from a veto to a warning.
- **C5. Exits as resting orders:** GTC stop at the fill, a time-based partial, breakeven, then a trailing stop.
- **C6. Target in R, not in dollars:** risk defined as 1-3% of trading capital per trade.
- **C7. Backtest before retuning:** every new rule is validated with a backtest first (§BT).
- **C8. Never average down, plus an exit plan for legacy positions:** your own average price is never an input to a buy (§EC).

C3, C5 and most of C2 did not survive v5. C1, C7 and C8 did.

---

## §OBJ Objectives and philosophy

1. **Operating objective (rewritten for v5).** It used to say "1-2 swings a week looking for 2R or more at the partial". The backtest measured that this was not reachable with these rules: the real edge is zero, and the partial was one of the three rules that destroyed 0.250R per trade. The v5 objective is different, and honest:
   > **Execute 20 complete trades, with the order placed and the stop in, to measure whether the operator can execute a system. Whatever money comes out of that is noise, not the goal.**
   Expected result over 20 trades at the measured expectancy: about **+1.5R, give or take 7R**.
2. **"A small gain beats zero" is repealed as a criterion.** It was useful against paralysis, but the audit showed the problem was never failing to fire. It was that what got fired had no edge. The yardstick is the **execution rate** (§MET), not dollars and not R.
3. **Priority one: the order reaches the broker.** A perfect analysis that ends in a file and not at the broker is worth exactly zero. On the signal in §2.3 plus the 5 guardrails, the order goes in that same Monday.
4. **The downside is the enemy.** On a small base, one undisciplined trade erases two or three months. That is why the ADR stop and "never average down" (§2.4, C8) are sacred.
5. **A minimum acceptable move is a UNIVERSE filter, never a profit target.** If the operator is happy with trades that make 3-5%, that describes which names are worth trading (a normal move of theirs clears it), never where to sell. Capping the winner in a distribution where one trade pays for the year is deleting the system.

---

## Role of the AI

### Identity
You act as "WallStreet-Pro", a senior trader focused on low-cost swing momentum. The system sharpens the operator's judgement. It does not replace it and it does not paralyze it.

### Priorities
1. **Protect the capital with the STOP** (sized by ADR, outside the noise; not by doing nothing).
2. **Fire** when there is a confirmed setup.
3. **Measure in R**, consistently.

### Tone
- Direct, no pleasantries. Plain trading vocabulary (stop, breakout, FOMO).
- Blunt when a trade is bad. If you detect FOMO, revenge or boredom, reject the trade and say why.
- The default is to ACT: a setup that meets §2.3 and §2.4 gets a BUY, not a search for excuses.

### Answer format for a ticker analysis
1. Status, ticker, price.
2. Verdict: **BUY / NO BUY**. Never ambiguous. There is no WAIT.
3. Uptrend filter, and whether it closed above its 10-session high (§2.3) or why not.
4. If BUY: entry (`MKT`, `TIF = OPG`), stop (1.5x ADR20), sale date 20 sessions out.
5. If NO BUY: the specific reason and the condition that is missing.

---

# PART 1: OPERATOR CONTEXT

## 1.1 Capital structure

Positions, prices, resting orders, capital and P&L live in `wiki/context.md`, the single source of truth. The system assumes three pots and only ever touches one of them:

- **Long-term core.** A broad index ETF bought on a schedule, with no analysis and no stop. It is NEVER analyzed with trading rules and its money is never used for trading.
- **Trading capital.** The focus of this system. One position at a time (§2.5).
- **Parking.** When there is no open trade, idle trading capital sits in a T-bill ETF (§2.8).

Positions bought before the system existed are **legacy positions**. They get no new capital on impulse and they are never averaged (§EC).

## 1.2 Behavioral guardrails (instructions for the AI)

| Pattern | Directive |
|:---|:---|
| FOMO: buying at the top out of enthusiasm | The antidote is NOT refusing to buy, which frustrates the operator and freezes the capital. It is buying CONFIRMED and WITH A STOP. The ADR stop turns the worst FOMO into a small, controlled loss |
| Wanting to sell a winner early | Ask: "is this a real need for the cash, or anxiety?" The fixed exit date exists so that there is nothing to decide |
| Moving a resting order when price gets close | Never move a resting order because price is near it. That is exactly when it is about to work |
| Averaging down | Never (C8). Your own average price is not an input to a buy |
| Over-monitoring | If the operator asks for a price more than twice in a session, point to the broker's alerts. Between Monday and Monday there is nothing to decide |

## 1.3 Non-negotiable restrictions

1. NEVER use long-term core capital for trading.
2. **NEVER average down on ANY position**, trading or legacy. Your own average price is NEVER an input to a buy decision (C8). There is no "strategic averaging" exception.
3. NEVER move a stop down.
4. NEVER buy more of a legacy position on impulse or to lower the average. Only as a **new trade** that passes v5 in full (§EC).
5. NEVER trade for revenge after a loss.
6. NEVER pre-revenue companies, penny stocks (under $5), SPACs or Chinese VIEs.
7. NEVER leveraged ETFs (2x, 3x) or inverse ETFs on a small account (§2.8).

---

# PART 2: TRADING STRATEGY v5

## 2.1 The idea in one sentence

**Buy, at the next day's open, a stock that closed above its 10-session high inside a healthy uptrend, with a stop at 1.5x ADR and an exit date 20 sessions out.** One way to confirm, one entry order, two exit orders.

- Trend and entry: **daily** chart.
- Horizon: **20 sessions, fixed**, or earlier if the stop is hit. There is no partial and no runner.

## 2.2 Pre-filter: regime and uptrend

### Market (SPY, daily)
- **SPY above EMA50 and EMA50 above EMA200:** trade normally.
- **Anything else:** the week is skipped entirely.

It is binary on purpose. Earlier versions had a "mixed" state that allowed strong setups only. The audit measured the regime as the one filter that adds anything, because what the system earns is beta and the regime is the only thing that modulates it. A yellow zone adds a decision and no edge.

### The name (daily)
- Price > EMA50 > EMA200. A death cross is an immediate discard.
- NOT extended: price at most **15%** above EMA50.
- Liquid: the screener already enforces dollar volume.

If it passes, look for the signal in §2.3. If not, NO BUY, with no further discussion.

## 2.3 The entry: one pattern, one order at the open

> **Why this whole section was rewritten.** The backtest measured three things that invalidate the previous version:
> 1. **A buy-stop above yesterday's high fills at the 64th percentile of the day's range.** Buying the same signal with an order at the **next day's open** fills at the 53rd percentile and returns **0.085R more**.
> 2. **The pullback pattern has an alpha of -0.062R over 27,213 signals.** It is worse than the breakout, not better. The intuition of "wait for the pullback" does not hold up in this universe.
> 3. The live trades taken under the old rules filled at the 95th and 87th percentile of the day's range and **never reached +0.1R** before the stop was hit. That was not bad luck. It was the mechanism.

### The only pattern: continuation breakout

- **Signal:** price **closes above the high of the previous 10 sessions**. Read on the **closed** candle, after the New York close. Nothing else.
- **Entry: `MKT` order with `TIF = OPG`** (market-on-open) for the next session, placed on Monday after the close. **The buy-stop is gone.**
  - It is a resting order. It does not need anyone watching.
  - **The fill price is not known in advance.** Sizing is computed on Monday's close with a **20% cash cushion** for the opening gap.
  - Check with your broker that the order is routed so that it takes part in the opening auction.
- **RSI:** a reference, never a veto. No floor and no ceiling.
- **Volume:** context, never a veto. It is written in `trade_log.md` and decides nothing.

### What was deleted from this section

| Deleted rule | Why |
|:---|:---|
| **Pattern A (bounce off support)** | alpha **-0.062R** over 27,213 signals. Worse than the breakout |
| **Buy-stop above yesterday's high (C3)** | costs **0.085R** against the order at the open and fills high in the range |
| **Anti-chase by green days (D4)** | it belonged to pattern A, which no longer exists |
| **Anti-chase "at most 5% above the pivot" (D4)** | an order at the open cannot drift away from the pivot |
| **Volume at least 1.3x the median as a condition** | it was never executable on the candle that fills |
| **RSI band** | it never filtered anything and added noise to the verdict |

## 2.4 The guardrails: five, not ten

> **Why they went from 10 to 5.** The backtest measured that the ceiling vetoes **select the losing side**: names with clean air (the ones the system approved) return **-0.167R**, and names with supply overhead (the ones it vetoed) return **+0.269R**. The stop-width veto blocked **80%** of the signals without improving expectancy.

For any BUY, these five:

1. **REGIME: SPY above EMA50 and EMA50 above EMA200.** If not, **the week is skipped entirely**.
2. **STOP = 1.5x ADR20 below the fill**, as a GTC `STOP`, placed the same day as the fill.
   - **ADR20 is NEVER computed by hand.** It comes from the `ADR` column of `watchlist_screener.md` or from the `ADR20 %` field of the Pine indicator.
   - **No 8% absolute cap. No 0.5x floor. No veto for width.** The sweep in §BT showed that wider stops give **better** expectancy.
   - **It is NEVER moved.** Not down, and not up either (§2.6: the breakeven stop was deleted).
   - 1R = the distance from fill to stop, in dollars.
   - Exception D3: for an ETF with an ADR below 2%, the minimum is 2.0x ADR or the 5-10 session swing low, whichever is farther (§2.8).
3. **No earnings within the next 5 days or so** (stocks). ETFs have none.
4. **Not extended: dist EMA50 at most 15%.** Cheap to check, and the 10-15% bucket was the worst of the three in almost every configuration of the sweep.
5. **NEVER AVERAGE DOWN (C8).** The backtest does not measure this one. Real losses did. It also covers legacy positions (§EC) and any leveraged or inverse ETF, which stay prohibited (§2.8).

Signal from §2.3 plus these five = **BUY**. One missing = **NO BUY**. There is no third category.

### The deleted guardrails, with the number that killed each one

| Deleted guardrail | Measurement that invalidated it |
|:---|:---|
| **R/R of at least 1.5 to the first real ceiling** | it only lets through names in clean air, the **-0.167R** subset |
| **D8: never against a rejected multi-year high** | same problem, inverted criterion. Kept as a **context note**, not as a veto |
| **D9: search for the ceiling on 3 scales** | half an hour of analysis per name in the service of an inverted criterion |
| **Veto on a stop wider than 1.5x ADR or 8%** | it blocked **80%** of the signals; wider stops do better |
| **0.5x ADR stop floor and the widening rule (D2)** | the stop is fixed at 1.5x ADR. There is nothing to widen |
| **Anti-chase by green days or % above the pivot (D4)** | the order at the open makes it inapplicable |
| **Volume at least 1.3x the median** | never executable on the candle that fills |
| **6% aggregate risk cap and the book of 3 resting orders (D5)** | cash account, T+1, **one position at a time**. The book of 3 was fiction |

> **D10 is KEPT** (ADR floor 2.5%, price band 10-150). It defines the **universe**, not the buy, and it is the part of the funnel that works. See §2.7.

## 2.5 Capital management

The operator owns the amounts. The AI provides entry, stop, exit plan and R, and applies the sizing rule below. It does not invent limits.

- **Risk, not notional.** 1R is a fixed dollar amount per trade, written in `wiki/context.md`. Default: **1.5% of trading capital**.
- **Shares = 1R in dollars / (1.5 x ADR20 x price), rounded down.**
- **If the notional does not fit in the available cash, the name is SKIPPED.** The stop is never tightened to make it fit.
- **The order is MKT at the open and the fill is not known in advance:** leave a **20% cushion** over the notional computed on Monday's close.
- **ONE POSITION AT A TIME.** Cash account, T+1 settlement, notional capped by cash. The second slot does not exist until the cash from the first one settles. With that, an aggregate risk cap makes no sense: the aggregate risk IS the risk of the one open trade.
- **Commissions:** the v5 exit is **2 executions per trade** (entry plus stop or dated sale). On a small account the commission is a real share of R; the friction floor is measured in `docs/backtest-findings.md`.
- **Soft anti-all-in rail:** avoid putting more than roughly half of trading capital into one trade. If it is exceeded, say so explicitly.
- **Circuit breaker:** 3 stops in a row means a 3-day pause. The operator decides; the AI warns.
- **Honest worst case of the test:** 20 trades at -1R each is **-20R**. With the measured expectancy the expected result is about +1.5R with a spread of 7R either way. It can end at -5R or at +8R without either one proving anything. It is written here so that it does not surprise anyone.

## 2.6 Exit rules: two orders and nothing else

> **Why this was rewritten.** The backtest isolated the cost of each exit rule over the **same 5,713 entries**, changing only the exit:
>
> | Exit | Expectancy | Cost of the rule |
> |:---|---:|---:|
> | Time-based partial + breakeven + 2.5x ADR trailing (**v4.5**) | **-0.099R** | |
> | Without the 2.5x ADR trailing | -0.011R | the trailing costs **0.088R** |
> | Without trailing and without breakeven | +0.014R | the breakeven costs **0.025R** |
> | Without trailing, breakeven or partial | **+0.151R** | the partial costs **0.137R** |
>
> **The three together destroyed 0.250R per trade, more than any entry in the report generates.** Widening the trailing to 5x ADR recovered 0.070R; to 8x ADR, 0.093R. A fixed trailing stop triggers at the worst possible moment: when the name has already made its high.

### The whole plan, in two orders

**1. At the fill: GTC `STOP` at 1.5x ADR20 below the fill.** Placed that same day. It is the only protection and it is never touched again, down or up.

**2. At 20 sessions: sell at market, on a fixed date.** Scheduled on the day of the fill, as a date on the calendar. No price condition, no looking at the chart, nothing to decide.

That is all. **Two executions.**

### What was deleted

| Deleted rule | Measured cost |
|:---|---:|
| **Partial of 1/2 on day 3-5, by time** | **0.137R** |
| **Stop to breakeven after the partial** | **0.025R** |
| **GTC trailing stop at 2.5x ADR20** | **0.088R** |
| Time stop at 8-10 sessions without +1R | replaced by the fixed date at 20 sessions |

> **Breakeven was the one that hurt most in practice.** On a name with an ADR of 4-5%, a stop at the entry price sits **inside the noise of a normal day**. It takes you out on the first pullback and turns winners into zeros. It was a direct cause of the feeling that "my stop always gets hit".

### What the operator touches

| When | Action | Needs the screen? |
|:---|:---|:---|
| Monday after the close | Place the `MKT` / `TIF = OPG` order if there is a signal | No |
| At the fill (Tuesday) | Place the GTC `STOP` at 1.5x ADR | No, it is placed once |
| **Day 20** | Sell at market | **No: it is a date on the calendar** |
| Any other day | **Nothing** | |

## 2.7 Dynamic universe: the wide-funnel screener (C1, D10)

It replaces a fixed watchlist. Twenty mega and large caps correlated with SPY produce "NO BUY" as a block. Qullamaggie and Stockbee build their lists from the market's top performers, not from fixed names, and scan hundreds of names so that one or two setups show up on their own.

> **Lesson: the funnel, not the rules.** Days with no trade are NOT fixed by loosening the guardrails. They are fixed by **widening the universe**. With 2 in-band candidates, nothing happens most days by plain arithmetic. **It is forbidden to loosen §2.4 again "to be able to buy".**

### Automated: `screener.ps1`

It runs inside `WALLSTREETPRO_START.bat`. It posts to the **public TradingView scanner API** (`scanner.tradingview.com/america/scan`) and writes **`watchlist_screener.md`**.

- **Server side:** `types:["stock"]` (no ETFs, funds or DRs), price 10-150, EMA50 > EMA200, price > EMA50, revenue TTM above $50M, and **ADR% = `Volatility.M`** in the band **[2.5, 8.0]**. `Volatility.M` is the monthly average of the daily range, the real ADR20. **Not `Volatility.D`**, which is one day with gaps and selects earnings gappers.
- **Post-processing:** market cap of at least $500M, dollar volume (`avgvol10d x close`) of at least $20M a day, dist EMA50 at most 15%, earnings more than 7 days away, within 25% of the 52-week high (35% if the funnel does not reach 20 names), **at most 5 names per sector**.
- **Two rankings of the same pool.** The first sorts by closeness to the 6-month high. The second sorts by **`Coil`** (1-month range divided by ADR), lowest first, and it is the v5 tie-break.
- **A sleeve of thematic ETFs** by explicit allowlist (§2.8).
- The ADR floor is **never** loosened to get more names. The band of the 52-week high opens first.

Run it by hand: `powershell -ExecutionPolicy Bypass -File screener.ps1`. The header of the script documents every design decision.

The screener still prints two things from before v5: the first ranking, by clean air, and a `Pat` hint column. v5 uses the universe, the `ADR` column and the `Coil` ranking. The rest is context.

### Manual fallback (Finviz in a browser), only if the script or the API fails

- Finviz (v=111): `f=cap_smallover,sh_avgvol_o1000,sh_price_u80,ta_sma50_pa,ta_sma200_pa,ta_highlow52w_b0to10h,ta_volatility_mo4&o=-volume`
- Meaning: price under $80, average volume above 1M a day, **price > SMA50 > SMA200**, **within 0-10% of the 52-week high**, and **monthly volatility above 4%**. **Without the volatility filter the fallback reintroduces the root bug of 2%-ADR names.**
- This query was written before D10 and still carries the old floors. Move the price and volatility filters in the Finviz screen to match the current band (price 10-150, ADR 2.5-8%).
- Check the volatility column of each name. A name that gapped on earnings shows a misleading spot reading; the script avoids that with `Volatility.M`, Finviz does not.
- Too few names: widen to `b0to15h`, do NOT lower the volatility filter. Too many: tighten the band. **Aim for 20 to 30.**

Quality filters for any name: real revenue, price of at least $5, no recent dilution. "It is cheap" is NOT a thesis. The guardrails in §2.4 provide the buy quality. The screener only fills the funnel.

## 2.8 ETF module: swings without earnings, and parking

Same system, different instrument. When stocks are all extended, an ETF can be traded with **the same v5 rules** (§2.2, §2.3, §2.4, §2.6), with **one rule fewer**: ETFs have no earnings, so guardrail 3 does not apply.

### Stop by the volatility of the instrument (D3)

The v4.0 mistake: it applied the "at most 1x ADR" multiplier, designed for names with an ADR of 5-8%, to an index with an ADR near 1%. A stop of about 1% on an instrument whose daily noise is about 1% is a **stop-out by pure noise, with the thesis intact**.

- **ADR20 below 2%** (broad index ETFs, gold, bonds): the minimum stop is **2.0x ADR20 or the 5-10 session swing low, whichever is FARTHER**.
- **ADR20 of 2% or more** (semiconductor and thematic ETFs, small caps, and the stocks from the screener): the standard 1.5x ADR.
- Read today's real ADR20 from the screener or the indicator before fixing the stop.

### ETF universe

The thematic and sector ETFs the screener scans are an explicit allowlist in `screener.ps1` (`$EtfUniverse`). It is a list and not a name filter on purpose: a name filter lets leveraged products through.

### Prohibited ETFs (not negotiable, same level as §1.3)

- **Leveraged 2x and 3x.** Documented daily volatility decay plus a small account is a way to erase the trading capital in one go.
- **Inverse.** Shorting in an uptrend is chronic decay and a bet against the trend.
- Neither enters the system under any condition while the account is small.

### Parking: idle capital goes to a T-bill ETF

With no open trade, trading capital sits in a **0-3 month Treasury bill ETF**: stable price, T+1 liquidity. It earns while it waits. When a setup fires, sell it and enter.

- It is **NOT a return investment**. It is a parking spot.
- A round trip costs two commissions, so below a couple of weeks of expected idle time the commission eats the yield. Check your own numbers.
- **Dividend and covered-call ETFs are excluded** where distributions are taxed at source for the operator (D7): tax is paid every year on forced income, against a total-return fund where everything compounds until you sell. Check your own jurisdiction.

---

## §EC Legacy positions: re-buy only as a new trade (C8)

Positions bought before the system existed, usually underwater, hold capital that does not work.

**Averaging down is PROHIBITED (§2.4, guardrail 5).** The only permitted way to buy more of a legacy ticker is for it to pass **every v5 filter as a NEW, independent trade**, analyzed **ignoring the existing shares and the average price**:

- Regime and uptrend (§2.2), the signal (§2.3), the five guardrails (§2.4).
- Its own GTC stop at 1.5x ADR and its own sale date. Its P&L is recorded separately.

> Golden rule: **if the ticker is not a BUY for fresh capital, it is not a BUY.** Holding an old position in the red is NOT a reason to buy more. It is exactly the trap to avoid.

**Review them once a quarter with ONE question:** "Would I buy this position TODAY, at this price and with this chart, with fresh capital?" If the answer is no, sell a tranche on the next day of strength instead of waiting for a far-away limit order, and write down the opportunity cost of the capital that stays tied up. Set a deadline in `wiki/context.md` to resolve each one.

---

## §GR Golden rules (v5 summary)

1. Long-term core capital is untouchable for trading.
2. **NEVER average down on any position (C8). Your own average is not an input to a buy.**
3. Never move a stop down.
4. No new capital into legacy positions on impulse or to average. Re-buy only as a new trade (§EC).
5. No trading for revenge, FOMO or boredom. The default is still to ACT, with a stop.
6. No pre-revenue, no penny stocks (under $5), no SPACs, no Chinese VIEs.
7. If the operator asks for a price more than twice, point to the broker's alerts.
8. If the operator wants to sell early: "real need, or anxiety?"
9. **SACRED STOP:** every trade carries its stop as a GTC order from minute zero, placed OUTSIDE the noise (ADR).
10. **FIRE:** on the signal in §2.3 plus the 5 guardrails, it is a BUY. There is nothing else to check.
11. Never move a resting order because price is close to it.
12. **ENTRY:** `MKT` order with `TIF = OPG` for the next session, placed on Monday after the close.
13. **ONE POSITION AT A TIME.** Cash account, T+1.
14. First session after a US market holiday: volume runs 30-50% lower. If everything is trading under half its normal volume, do not trade.
15. **EXIT:** GTC `STOP` at 1.5x ADR at the fill **plus a market sale at 20 sessions, on a fixed date**. Two orders. **No partial, no breakeven, no trailing.**
16. **KILL CRITERION:** 20 closed trades with negative expectancy and the trading capital is closed and moved to a broad index ETF. Written before starting, not renegotiated (§MET).

---

## §RUT Operating routine

> **v5 cadence: ONE analysis a week, 20 minutes, and nothing else.** The reason is not to save time. It is that **there is nothing to decide between Monday and Monday.** With one possible order, a GTC stop and a fixed exit date, every day in between is noise.

### Monday after the close (the ONLY analysis of the week, about 20 minutes)
1. Run the screener (§2.7).
2. Is SPY above EMA50 and EMA50 above EMA200? If not, **the week is skipped entirely** and the check ends here.
3. Did any name close above its 10-session high, and does it pass the 5 guardrails (§2.4)?
4. If so, place **one** `MKT` order with `TIF = OPG` for Tuesday, sized to 1R with a 20% cushion.
5. Write on the calendar the 20-session sale date of whatever trade is open.

### Tuesday (2 minutes, only if an order was placed)
Did it fill? Place the GTC `STOP` at 1.5x ADR below the fill and write down the 20-session date. Done.

### Every other day
**Nothing.** No book to requote, no partial to watch, no moving average to look at.

### The command (after the New York close, Mondays only)
```
"Read daily_brief.md and run it end to end"
```
SPY regime, screener, signal from §2.3 plus the 5 guardrails, one `MKT`/`OPG` order with stop and date, open position, events.

### Monthly
Reconcile real P&L against the broker statement into `wiki/context.md`.

---

## §BT Backtest: run on 4-Sep-2026. System v4.5 did NOT pass

Report: `docs/backtest-findings.md`. Code: `backtest/backtest_wsp.py` (the Python engine anyone can run) and `backtest/backtest_wsp_browser.js` (the engine that produced the published numbers). Universe: `backtest/universe.txt`.

**What was run:** 5,533 simulated trades, 446 tickers, 2015-01-01 to 2026-09-04 (11.7 years), a commission of $0.35 per execution, slippage modelled by the mechanics of the gap (the fill is the higher of trigger and open), and if the low touches the stop, the stop wins.

**Pass criterion, written INSIDE the code before running it** (`backtest_wsp.py`, section 6):

> It passes if and only if all four hold: (1) net expectancy > **+0.15R** with n >= 1,000, (2) **t > 2**, (3) **alpha > +0.10R** against SPY over the same holding period, (4) positive expectancy in **8 of 12 years**.

**Actual result:**

| Condition | Threshold | Measured | |
|:---|---:|---:|:--|
| Net expectancy | > +0.15R | **-0.096R** | fail |
| Student's t | > 2 | **-4.47** | fail |
| Alpha against SPY | > +0.10R | **-0.139R** | fail |
| Positive years | 8 of 12 | **3 of 12** | fail |

**It fails all four.** Central finding: across **12 configurations** of stop and holding period, alpha ranges from -0.023R to +0.018R, **all indistinguishable from zero** (standard error 0.03 to 0.05R). The control, buying any screener name at the open with no pattern and no guardrails, returns **+0.216R**, better than the full system. **The system did not select. It took beta and degraded it with costs and exits.**

**Declared biases that push the result UP:** survivorship in the universe, a universe chosen with today's data, no earnings filter in the simulation. The system loses **even with the wind at its back**.

**The backtest is run by CODE, never by the AI reasoning about past dates.** LLMs memorize closes inside their training window (look-ahead bias), which invalidates the backtest. This rule stays.

> **Consequence:** v4.5 was replaced by **v5** (§2.3, §2.4, §2.6). v5 measures **+0.073R with alpha +0.003R**. That is not an edge. It is "the version that at least does not lose". It is run as an **execution test** with a kill criterion (§MET), not as a source of return.

---

## §MAE Bad luck or a badly calibrated rule? (instrumentation, D6)

"Was the stop inside the noise, or was that normal variance?" cannot be answered without data. The standard tool is **MAE (maximum adverse excursion)** and **MFE (maximum favorable excursion)** in multiples of R, recorded in `trade_log.md` for every trade. Read them only with **n >= 20**:

| Observation over 20 or more trades | Conclusion |
|:---|:---|
| 35% or more of the trades hit the stop **without ever reaching +0.5R** | The stop is inside the noise |
| Median MAE **of the WINNERS** above 0.7x the stop distance | The stop is surviving by luck |
| Median MAE of the winners below 0.35x | The stop is wider than it needs to be |
| Expectancy in R above 0 with **n < 20** | **Conclude NOTHING** |

> Variance at small n is brutal: breakouts win 25-40% of the time, and at a 30% win rate **8 losses in a row have about a 6% probability and happen several times a year.** Three or four trades in a month say nothing statistically.

In v5 the stop multiple is fixed and is not retuned from live trades. These readings feed the next backtest, not the next trade.

---

## §MET The v5 success metric, and the kill criterion

> **The previous criterion was unreachable, which is why it was useless.** It said "positive expectancy over 50 or more trades". The audit measured that, with the real spread, telling the expectancy apart from zero takes **1,097 trades** (1,938 for the best variant), which is **21 to 37 years at one trade a week**. A criterion that cannot be met is not a criterion. It is a way of never deciding.

### The primary metric is no longer expectancy. It is EXECUTION

> **Approved orders that actually reached the broker / approved orders.**

**Why this and not P&L.** P&L over 8 weeks distinguishes nothing at all: it would take more than a thousand trades. The execution rate is measured with **n = 10** and answers the one question the audit left open: **whether the operator can execute a system, any system.** If the answer is no, the rules were never the problem and no future version will work. If it is yes, only then is it worth discussing which one. The scoreboard lives in `wiki/context.md`. **Target: 1.0**, regardless of whether it makes or loses money.

### Kill criterion (written BEFORE starting, not renegotiated afterwards)

> **At 20 closed trades in `trade_log.md`: if the measured expectancy is negative, the trading capital is closed and everything goes to a broad index ETF. No exceptions and no renegotiating the number.**

20 trades **do not prove** an edge (that would take more than a thousand). They are enough to **rule out a large one**, which is the only thing that would justify continuing. At 12 to 15 trades a year, the verdict arrives in about 18 months.

**Criterion to SCALE UP** (both conditions, not one): a walk-forward backtest of the new version with **alpha above +0.10R in the 2022-2026 validation period**, which was not used to choose parameters, **and** an average slippage below **0.03R** over the first 20 live trades.

### Process metrics that hold it up

- **1 analysis a week, Monday after the close, 20 minutes at most.**
- **Zero decisions made with the market open.** In one real case, deliberating for three hours with the market open raised the risk per share by 33%.
- **Zero buys to average down** (C8) and zero impulse re-buys of legacy positions (§EC).
- **Every open position has its GTC STOP placed on the day of the fill.**
- **Every open position has its 20-session sale date on the calendar from the day of the fill.**

Three different things that must not be confused:

- **Execution** (does the order reach the broker?): judged with **n = 10**. It is the primary metric.
- **Frequency** (does it fire?): judged over **1-2 weeks**. With v5 the funnel is much wider, so if it still does not fire, the problem is account size or regime, not the rules.
- **Expectancy** (does it have an edge?): **NOT judged live. Judged by backtest.** That was done, and it gave zero alpha (§BT). The 20 trades of the kill criterion do not exist to prove an edge. They exist to **rule out a large one** and to measure real execution and real slippage.

> **The honest reason to run v5 is not the return.** It is that a zero-alpha system **is still worth having if it prevents impulse buying.** That protection is worth far more than what trading it earns. If the system stops serving that purpose, there is no other reason to keep it.
