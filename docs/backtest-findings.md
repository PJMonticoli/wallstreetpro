# Backtest findings: the audit that produced v5

This is a condensed English version of the independent audit of the system, run on 4 September 2026 against version 4.5 of the rules. The original report was written for the operator and included account-specific material, which is left out here. Everything about the method and the measurements is kept.

Every number in sections 1 to 9 came out of code run over real prices. None came from recalling closes. Section 10 is a second, independent run with the Python port, made when this repository was published.

---

## 1. Verdict

**The system cannot be saved with adjustments. It has to be replaced.**

Over **5,533 simulated trades between 2015 and 2026**, the system has an expectancy of **-0.096R per trade** and loses in **9 of the 12 years**. It is not variance: t = -4.47.

The serious part is not that it loses. It is **why it earns the little it earns in its best versions**. In the 12 combinations of stop, holding period and entry that were tested, expectancy is almost equal to the market's return over the holding period. **Alpha, what the rules add on top of simply being long, ranges from -0.023R to +0.018R: zero.** Buying any screener stock at the open, with no pattern and no guardrails, returns **+0.216R**: better than the full system.

In plain terms: **the system does not select. It takes market exposure, loads it with commissions, slippage and single-name risk, and degrades it with its exits.** An index ETF delivers that exposure with none of it.

What survives is the architecture of resting orders, the screener and the trade log. The buy and sell rules are thrown out.

---

## 2. How it was verified

| | |
|:-|:-|
| Universe | 446 US tickers with a market cap above $500M, dollar volume above $20M a day and a price between $10 and $150, plus the ETFs the system uses. See `backtest/universe.txt` |
| Period | 1-Jan-2015 to 4-Sep-2026 (11.7 years), daily bars. Warm-up from 1-Jun-2014 so that EMA200 and ADR20 are loaded |
| Source | Yahoo Finance chart API |
| Engine | JavaScript in a browser, `backtest/backtest_wsp_browser.js`. The environment had no network route to a price provider. Equivalent Python version in `backtest/backtest_wsp.py` |
| Intrabar convention | If the low of a session touches the stop, the stop is assumed to execute first and fills at the lower of open and stop. Gaps are punished on purpose |
| Commissions | $0.35 per execution, the minimum of a tiered retail plan |
| Entry slippage | Modelled by the mechanics of the gap: the fill is the higher of trigger and open |

**Engine validation against the system itself.** For one ticker on one date, the engine's ADR20, EMA50, 10-session pivot and distance to EMA50 were compared with the readings the live system had recorded that same day. They matched within rounding (ADR20 2.21% against 2.19%, the pivot identical). The system's indicators are computed correctly. **The problem is not the numbers. It is the rules.**

**Pass criterion, written in the code before the first run:**

> The system PASSES if and only if: net expectancy above +0.15R with n above 1,000, t above 2, **alpha above +0.10R**, and positive expectancy in 8 of the 12 years. If any of the four fails, it is not funded with new capital.

Actual result: expectancy **-0.096R**, t **-4.47**, alpha **-0.139R**, positive years **3 of 12**. **It fails all four.**

---

## 3. The hypotheses the audit was asked to test

| # | Verdict | Measured evidence |
|:-|:-|:-|
| **F1. The entry buys high in the day's range** | **CONFIRMED** | Systematic: **median fill at 64% of the day's range**, and **30.5% of fills land above 80%**. **P(pullback of 1x ADR within 3 sessions) = 44.2%**, over 5,533 fills. **10.1% of trades never reach +0.1R** |
| **F2. The payoff does not cover the win rate** | **CONFIRMED and quantified** | With the v4.5 exits the average winner is **1.388R** and the average loser **-0.941R**. Breaking even at a 36.3% win rate takes **1.65R**; at 30%, **2.20R**; at 25%, **2.82R** |
| **F3. An honest structural stop does not fit in the allowed width** | **CONFIRMED, and it is structural** | Over **8,518 breakout signals**: a stop below EMA21 measures a **median of 2.07x ADR**. Only **20.2%** of signals have it at 1.5x ADR or less, and **4.3%** at 1.0x or less. The 1-month base measures a **median of 4.72x ADR** |
| **F4. The system approves the most extended name** | **CONFIRMED, and worse than described** | Not only does it approve the most extended name: **that subset is the one with negative expectancy**. Names with clean air (no prior high above the entry within 1 year) return **-0.167R**; names with supply overhead return **+0.269R**. The gap holds in all 4 exit configurations tested. The R/R guardrail and vetoes D8 and D9 **select the losing side** |
| **F5. The vetoes cost money by rejecting winners** | **Undetermined on the live sample** | The rules in question were between 2 and 5 days old, so the forward window was a median of 2 sessions. That measures noise, not a veto. The question does have an answer with statistical power, and it is F4 |
| **F6. The backtest gate was never run** | **CONFIRMED** | The gate had existed for two months and two full versions went past it. This audit was the first time it ran |

---

## 4. The audit's own findings

### G1. Zero alpha. The central finding

For each trade, the return of SPY over exactly the same holding period was measured, in the same R units. The difference is alpha.

| Configuration | n | Expectancy | Market | **Alpha** |
|:-|-:|-:|-:|-:|
| System v4.5 as written | 5,533 | -0.096R | +0.044R | **-0.139R** |
| Buy-stop, 1 ADR stop, stop and time exit only | 5,533 | +0.160R | +0.174R | **-0.014R** |
| Entry at the next open, same stop | 8,113 | +0.245R | +0.190R | **+0.055R** |
| Control: any screener day, at the open | 6,624 | +0.216R | +0.202R | **+0.015R** |
| Pattern A (pullback to EMA21) | 27,213 | +0.121R | +0.182R | **-0.062R** |

The full sweep of stop by holding period, 8,407 signals in each cell:

| Stop | Hold 10 | Hold 20 | Hold 40 |
|:-|-:|-:|-:|
| 1.0x ADR | alpha -0.023 | alpha +0.004 | alpha +0.018 |
| 1.5x ADR | alpha -0.021 | alpha +0.003 | alpha +0.015 |
| 2.0x ADR | alpha -0.021 | alpha +0.001 | alpha +0.007 |
| 2.5x ADR | alpha -0.019 | alpha +0.004 | alpha +0.016 |

Twelve cells, twelve zeros. The standard error of expectancy in these samples is about 0.03 to 0.05R, so **all of these alphas are indistinguishable from zero**. And in all 12 the expectancy is negative in 2015, 2016, 2018 and 2022, the years the market did not go up. That is the signature of beta, not of an edge.

### G2. The buy-stop entry costs 0.085R against buying the same signal at the next open

Measured: +0.160R against +0.245R. The median position of the fill in the day's range moves from **0.64 to 0.53**. This is the complaint "I miss the green candle and buy the top", measured.

### G3. Buy-stop slippage

Mean **0.060R**. **29.4% of fills open with a gap above the trigger**, and when that happens the extra cost averages **0.204R**. The live fills observed fell inside this distribution.

### G4. Exact attribution of the exit rules

Same 5,713 entries, only the exits change:

| Exit | Expectancy | Cost of the rule |
|:-|-:|-:|
| Time-based partial + breakeven + 2.5x ADR trailing (**as written**) | **-0.099R** | |
| Without the 2.5x ADR trailing | -0.011R | the trailing costs **0.088R** |
| Without trailing and without breakeven | +0.014R | the breakeven costs **0.025R** |
| Without trailing, breakeven or time-based partial | **+0.151R** | the partial costs **0.137R** |

**The three rules together destroy 0.250R per trade.** That is more than any entry in this report generates. Widening the trailing to 5x ADR recovers 0.070R; to 8x ADR, 0.093R. The 2.5x ADR trailing was justified in the rules because "the EMA21 runs 2 to 2.5 ADR below price". True as a description, false as a rule: a fixed trailing stop triggers at the worst possible moment, when the name has already made its high.

### G5. The friction floor

Commissions of three executions, as a share of R, depend on how many dollars 1R is. Slippage does not.

| 1R in dollars | Commissions, 3 executions | Slippage | **Total friction** |
|-:|-:|-:|-:|
| about 11 | 9.8% of R | 6.0% | **15.8% of R** |
| about 16 | 6.5% of R | 6.0% | **12.5% of R** |
| about 32 | 3.3% of R | 6.0% | **9.3% of R** |
| 45 | 2.3% of R | 6.0% | **8.3% of R** |
| 75 | 1.4% of R | 6.0% | **7.4% of R** |

**Slippage, not commission, is the dominant cost, and it does not fall with capital.** Scaling the account does not fix it. Changing the order type does. The measured alpha is 0.000 to 0.018R.

### G6. The problem of proof has no solution in live trading

With the measured standard deviation, telling the real expectancy apart from zero at t = 2 takes **1,097 trades** for the system as written and **1,938** for the best variant. At one trade a week that is **21 and 37 years**. **The live account cannot answer the question. It never could.**

### G7. The arithmetic of the system is correct

It is worth saying because it is the one thing that survives the audit: ADR, EMAs, pivots, R/R and capital calculations are right. The error is not in the execution of the math. It is in the design.

---

## 5. Do the vetoes keep expectancy or destroy it?

| Criterion | n | Expectancy |
|:-|-:|-:|
| Names WITH NO ceiling above within 1 year (clean air, what the system approved) | 1,389 | **-0.167R** |
| Names WITH supply overhead (what the system vetoed) | 4,144 | **+0.269R** |
| Names with no ceiling in 5 years (all-time high) | 814 | **-0.234R** |

**The sign holds in all four exit configurations tested.** It is consistent with F4: the name in clean air is, by construction, the most extended of the group, the one that just ran, the one with its base farthest away and the widest stop.

What to do with each veto:

| Veto | Decision | Why |
|:-|:-|:-|
| **R/R of at least 1.5 to the first real ceiling** | **DELETE** | It measures correctly and concludes backwards. In practice it only lets through names in clean air, the negative-expectancy subset |
| **D8: never against a rejected multi-year high** | **DELETE as a veto, keep as a note** | Same problem. Individual rejections may have been right for other reasons, but the general criterion is inverted |
| **D9: search for the ceiling on three scales** | **DELETE** | It is analysis work, measured in hours a week, in the service of a criterion that does not work |
| **D10: ADR floor of 2.5% and price band 10 to 150** | **KEEP** | It defines the universe, not the buy. It is the part that works |
| **Not extended beyond 15% above EMA50** | **KEEP** | Cheap, and the 10-15% bucket is the worst of the three in almost every configuration |
| **Veto on a stop wider than 1.5x ADR** | **DELETE** | It blocked 80% of the signals and does not improve expectancy: wider stops give **better** expectancy (-0.096R at 1x against -0.058R at 2.5x) |
| **SPY above EMA50 and EMA200** | **KEEP** | The only filter that adds anything, because the system's return is beta and the regime is the only thing that modulates beta |
| **C8: never average down** | **KEEP, sacred** | This report does not measure it. Real losses do |

---

## 6. One position at a time

A cash account with T+1 settlement and a notional capped by cash holds one position. With a holding period of H sessions, the maximum is 252 / H trades a year. That turns expectancy per trade into R per year:

| Holding period | Trades a year | System v4.5 | Best variant | **Alpha only** |
|:-|-:|-:|-:|-:|
| 5 sessions | 50.4 | -4.8R | +8.3R | **+0.9R** |
| 20 sessions | 12.6 | -1.2R | +2.1R | **+0.2R** |
| 40 sessions | 6.3 | -0.6R | +1.0R | **+0.1R** |

Full portfolio simulation, one position at a time, with commissions, 2015 to 2026:

| Strategy | **CAGR** | Trades |
|:-|-:|-:|
| System v4.5, ranked by clean air | **-1.6%** | 205 |
| System v4.5, ranking inverted | -3.2% | 205 |
| Best variant (2 ADR stop, hold 60) | **+1.4%** | 85 |
| **SPY, bought and held** | **+12.0%** | 1 |

**At three and five times the capital the percentages barely change**, because risk per trade is proportional to capital. **Scaling the capital fixes nothing. It multiplies a number that is zero.**

---

## 7. What kind of evidence answers the question

| Question | Trades needed | At 1 a week | At 4 a week |
|:-|-:|-:|-:|
| Tell the current expectancy apart from zero | **1,097** | 21 years | 5.3 years |
| Tell the best variant apart from zero | **1,938** | 37 years | 9.3 years |
| Detect a large edge of +0.30R | 114 | 2.2 years | 0.5 years |

| Method | Sample per week of effort | What it proves | What it does NOT prove |
|:-|:-|:-|:-|
| **Backtest over 2015 to 2026** | 5,000 to 8,000 trades in an afternoon | expectancy, alpha, stability by year, attribution by rule | real execution, your own slippage, discipline |
| Walk-forward (train 2015-2021, validate 2022-2026) | same effort | that the result did not come from overfitting | the same |
| Manual bar replay | 20 to 40 trades a week of work | discipline and chart reading | expectancy (the sample is two orders of magnitude short) |
| Paper trading | 4 to 8 trades a month | order placement and order types | nothing statistical |
| **Live account** | 4 to 8 trades a month | real slippage and discipline | expectancy, not even in 20 years |

**The live account is the slowest, most expensive and least conclusive instrument available.** A backtest over 11.7 years delivers in one afternoon the equivalent of **106 years of trading at one trade a week**.

---

## 8. WSP v5, on one page

> **Rule zero: no decision is made with the market open. Everything is decided after the close and executed with resting orders.**

| Field | Rule |
|:-|:-|
| **Universe** | US stocks, price 10 to 150, market cap above $500M, 20-day dollar volume above $20M, ADR20 between 2.5% and 8%, price above EMA50 above EMA200, dist EMA50 up to 15%. **The existing screener, untouched** |
| **Regime** | Trade only with SPY above EMA50 and EMA200. Otherwise the week is skipped. It is the only filter that adds anything |
| **Ranking** | By **base compression** (`Coil` = 1-month range divided by ADR), lowest first. **Ranking by clean air is removed**: it selects the losing subset |
| **Signal** | Close above the high of the previous 10 sessions |
| **Entry** | **`MKT` order with `TIF = OPG` for the next session**, placed on Monday after the close. **The buy-stop is removed.** Measured: +0.085R against the buy-stop, and the fill moves from the 64th to the 53rd percentile of the day's range |
| **Stop** | **1.5x ADR20 below the fill**, as a GTC STOP, placed the same day. No 8% cap. **The veto for stop width is removed** |
| **Sizing** | Risk of 1.5% of trading capital. Shares = risk / 1R, rounded down. If the notional does not fit in the cash, the name is skipped. The stop is not tightened to make it fit |
| **Exit** | **One: the GTC STOP, plus a market sale on a fixed date 20 sessions out.** Two executions. **The time-based partial, the breakeven stop and the 2.5x ADR trailing are removed.** Measured: together they cost 0.250R |
| **Positions** | **One**. Cash account, T+1 |
| **Vetoes that stay** | SPY regime, dist EMA50 up to 15%, no earnings within 5 days (stocks), never average, never move the stop down, nothing leveraged or inverse |
| **Vetoes that go** | R/R to the first ceiling, D8, all of D9, stop wider than 1.5x ADR, 1.3x volume filter, anti-chase by green days |
| **Weekly cost** | **20 minutes on Monday after the close.** Nothing else |
| **Measured expectancy** | **+0.073R** per trade (entry at the open, 1.5x ADR stop, hold 20), **alpha +0.003R**. Written on purpose: that is all there is |

**What the simplification removes, in numbers:** from 10 guardrails to 5, from 8 validation points to 4, from 3 executions per trade to 2, from 2 analysis sessions a week to 1.

### The questions about intraday participation

1. **Running the analysis mid-session: no.** In one real case the analysis ran with the market open, the decision came three hours later, and the 1R per share had grown by 33%.
2. **"I miss the green candle": the fix is not watching it, it is buying the next open.** A buy-stop above yesterday's high fills at the 64th percentile of the day's range. A market-on-open order placed the night before fills at the 53rd, and expectancy rises 0.085R. It is a resting order: it does not need you there.
3. **Opening range breakout cannot be coded as a resting order placed the night before.** In the reference paper (Zarattini and Aziz, SSRN 4416622), the unfiltered version underperformed buy and hold; the good result appears only after filtering for abnormal relative volume at the open, a number that does not exist the night before. It also uses 4x leverage and assumes zero slippage.
4. **News and sector strength: the one anchor with academic backing is post-earnings announcement drift**, and it does not fit this horizon. It accumulates over 40 to 60 sessions, is stronger in small caps where execution costs are higher, and is implemented as a decile portfolio, not one position at a time.
5. **Buying the first pullback after the move** was tested: +0.121R with alpha -0.062R over 27,213 signals. **Worse than the breakout, not better.**

### Was "buy strength" the right lesson?

Before the system, the winners had been short swings sold into strength, and the large losses had been an unconfirmed re-buy and accumulation near the top. Rule C3 translated that into "buy the confirmation of strength".

**The translation was wrong in one specific part.** What worked was **selling** into strength, not **buying** into it. C3 took the right diagnosis of the losses (buying unconfirmed is bad) and produced a rule that buys at the most expensive point of the day. The stop rule had been copied from a method whose entry is the opening range high of the morning, when the low of the day is inches away. Applying that stop multiplier to a different entry point is where F3 comes from: the honest stop ends up at a median of 2.07x ADR.

---

## 9. Limitations, said out loud

1. **Survivorship bias.** The universe is tickers that exist today. That inflates the result. **It is one more reason for the verdict, not one less: the system loses even with the wind at its back.**
2. **No earnings filter** in the simulation (there was no historical calendar). It affects stocks, not ETFs. Direction of the bias unknown.
3. **No intraday data**, so opening range breakout was not tested directly. It was answered with the literature and with the mechanics of the open.
4. **The universe was selected with today's data**, another source of optimistic bias.
5. **Expectancy depends on the right tail.** In the best variant, **1% of the trades contribute 129% of the total result**. With one position at a time, the probability of catching one of those in a year is low, which is why the portfolio simulation gives +1.4% CAGR while expectancy per trade gives +0.16R. Both are true at once.

### External sources and the quality of the evidence

Figures as cited in the audit. Check the papers before relying on them.

| Source | What it contributes | Status of the track record |
|:-|:-|:-|
| Barber, Lee, Liu and Odean, *Do Day Traders Rationally Learn About Their Ability?* (Taiwan, 1992 to 2006) | About 5% of active day traders had a positive cumulative net return; fewer than 3% predictably so. Most of those who lost kept trading | Academic, full population. The strongest evidence in the report |
| Zarattini and Aziz, *Can Day Trading Really Be Profitable?* (SSRN 4416622) | Opening range breakout. The good result depends on a relative-volume filter at the open, 4x leverage and zero slippage | Published research, not a track record. Favorable assumptions declared by the authors |
| Kristjan Kullamagi (Qullamaggie), self-published rules | Stop at the low of the day and no wider than the ADR; entry at opening range highs; sell part at 3 to 5 days; trail by the first close below the 10-day average | Self-reported. No independent audit |
| Pradeep Bonde (Stockbee), episodic pivots | Gap with volume several times the average; requires measuring the first 15 to 30 minutes of volume | Self-reported and educational |
| Mark Minervini, SEPA | US Investing Championship results administered by a third party | Verified by the contest organizer on one account. Not a full audited track record |
| Bernard and Thomas (1989) and later PEAD work | Drift after earnings over about 60 sessions, smaller in recent estimates, stronger in small caps, eroded by costs | Academic, peer reviewed |
| George and Hwang (2004), *The 52-Week High and Momentum Investing*, Journal of Finance | The 52-week-high effect works **with monthly rebalancing and a 6-month hold, as a decile portfolio**. Not as a single trade with a 1 ADR stop | Academic. It does NOT contradict F4: different horizon and different vehicle |

**On the apparent contradiction.** The finding that names in clean air do worse does not refute the literature on the 52-week high. They are different questions: a decile portfolio rebalanced monthly and held 6 months with no stop, against a single trade with a 1 ADR stop and a horizon of 5 to 60 sessions. **With a 1 ADR stop, the most extended name is the one that touches it most easily.**

---

## 10. Independent reproduction with the Python port

The published numbers came out of the JavaScript engine. When this repository was prepared, the Python port was extended to compute alpha and the per-year breakdown, and it was run from scratch on 16 November 2026: 463 of the 468 symbols in `universe.txt` returned data, 453 of them tradable and 10 ETFs. The whole run, download included, took about 7 minutes.

| Measure | Published (JS, 4-Sep-2026) | Python port (16-Nov-2026) |
|:-|-:|-:|
| System v4.5: trades | 5,533 | 5,650 |
| System v4.5: expectancy | -0.096R | -0.106R |
| System v4.5: t | -4.47 | -5.15 |
| System v4.5: market return over the hold | +0.044R | +0.045R |
| System v4.5: alpha | -0.139R | -0.151R |
| System v4.5: positive years | 3 of 12 | 2 of 12 |
| Median fill position in the day's range, buy-stop | 0.64 | 0.64 |
| Median fill position, next open | 0.53 | 0.53 |
| Average buy-stop slippage | 0.060R | 0.060R |
| P(pullback of 1x ADR within 3 sessions) | 44.2% | 44.3% |
| Cost of the trailing / breakeven / partial | 0.088 / 0.025 / 0.137R | 0.083 / 0.025 / 0.132R |
| Next open against buy-stop | +0.085R | +0.088R |
| Control, any screener day at the open | +0.216R, alpha +0.015R | +0.205R, alpha -0.006R |
| Pattern A, pullback | +0.121R, alpha -0.062R | +0.092R, alpha -0.091R |
| Alpha across the 12 cells of stop x hold | -0.023R to +0.018R | -0.030R to +0.009R |
| v5 rules (open, 1.5x ADR, hold 20) | +0.073R, alpha +0.003R | +0.066R, alpha -0.006R |
| Stop at 1.0x against 2.5x ADR | -0.096R against -0.058R | -0.106R against -0.061R |

Same verdict: it fails all four conditions, and alpha is zero in every cell.

Why the digits differ:

- **Yahoo restates history.** Splits, delistings and renamed tickers between the two dates change the bars, and the 10-150 price band is an absolute filter. Five symbols no longer returned data.
- **The 12-cell grid** is a reconstruction in the port (entry at the next open, the stop and the holding period as the only exit rules). The published grid reports 8,407 signals per cell; the port finds 8,319.
- **The control** reports 6,624 trades in the published run. The port simulates every qualifying day, 75,612 of them. The published code does not show how that run was thinned. The expectancy is about the same.

Expectancy by year of entry in the port's run:

| Year | System v4.5 | v5 rules |
|:-|-:|-:|
| 2015 | -0.466R | -0.358R |
| 2016 | -0.239R | -0.127R |
| 2017 | +0.265R | +0.338R |
| 2018 | -0.529R | -0.429R |
| 2019 | -0.090R | -0.032R |
| 2020 | -0.017R | +0.247R |
| 2021 | -0.167R | +0.100R |
| 2022 | -0.254R | -0.276R |
| 2023 | +0.194R | +0.387R |
| 2024 | -0.028R | +0.124R |
| 2025 | -0.105R | +0.045R |
| 2026 | -0.130R | +0.017R |

v5 is positive in 7 of the 12 years and negative in the years the market did not go up. That is what beta looks like.

---

*This document is measurement and arithmetic. It is not financial or investment advice.*
