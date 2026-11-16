# Visual guide: WallStreetPro v3 Unified

Quick reference for reading a TradingView chart with the indicator in `wallstreetpro_v3_unified.pine` loaded. Daily timeframe.

The indicator draws on two places: lines and a background zone on the **price pane**, and one line in **its own pane** below. Everything else it computes is in the **data window**, which is what Claude reads over MCP.

---

## Price pane: the three EMAs

| Line | Color | Period | What it tells you |
|:---|:---|:---|:---|
| Thick | Red | EMA 200 | Long-term trend, about 40 weeks. The structural floor |
| Medium | Blue | EMA 50 | Medium-term trend, about 10 weeks. The reference for "extended" |
| Dotted | Yellow | EMA 21 | Short-term trend, about one month. Context only since v5 |

What the rules ask of them:

```
Price above the blue line (EMA 50)?            -> uptrend, part 1
Blue line above the red line (EMA 200)?        -> uptrend, part 2
Price at most 15% above the blue line?         -> not extended
```

All three must hold for a name to be a candidate. On SPY, the first two are the regime filter: if SPY is not above its EMA 50 with the EMA 50 above the EMA 200, the whole week is skipped.

## Price pane: the red background

| What you see | Condition | Meaning |
|:---|:---|:---|
| Soft red background | Close more than 15% above EMA 50 | **EXTENDED.** Guardrail 4 fails: NO BUY |
| Red label "EXTENDED >15% EMA50" | First bar of an extended stretch | Marks where the stretch began |

There are no buy or sell arrows and no score. Earlier versions had both. They were removed because they suggested rules the system does not have.

---

## Indicator pane: ADR20

One aqua line: **ADR20 %**, the 20-session average of the daily range, `(high - low) / low`. It is the number that sizes the stop.

| Reference line | Meaning |
|:---|:---|
| Dotted gray at 2% | Below this, an ETF falls under rule D3: stop of at least 2.0x ADR |
| Dotted green at 4% | A reference for a comfortably volatile name |

How it is used:

```
1R per share = 1.5 x ADR20 % x price
stop         = fill - 1R per share
```

Example with made-up numbers: price $50.00, ADR20 4.0%. 1R per share = 1.5 x 0.04 x 50 = $3.00, so the stop goes at $47.00.

**Never recompute ADR20 by hand.** Read it here or in the `ADR` column of `watchlist_screener.md`. They are the same quantity (TradingView's `Volatility.M`).

---

## Data window: what Claude reads

Open the data window (the icon on the right toolbar) and hover a bar. These fields come from the indicator:

| Field | What it is | Role in v5 |
|:---|:---|:---|
| `ADR20 %` | 20-session average daily range | **Sizes the stop** |
| `EMA200 val`, `EMA50 val`, `EMA21 val` | The three EMAs as numbers | Uptrend and regime checks |
| `Dist EMA50 %` | Distance from the close to EMA 50 | **Guardrail 4: at most 15%** |
| `Extended (>15% EMA50)` | 1 or 0 | Same guardrail, as a flag |
| `RSI`, `RSI signal` | RSI 14 and its 9-period EMA | Context, never a veto |
| `MACD line`, `MACD signal`, `MACD hist` | MACD 12, 26, 9 | Context, never a veto |
| `Vol ratio med x` | Volume divided by its 20-day **median** | Context, written in the trade log |
| `Vol ratio sma x` | Volume divided by its 20-day mean | Kept for comparison with old readings |

Two things to remember:

- **The data window follows the cursor.** A reading taken with the crosshair on an old bar is that bar's reading. Check `EMA50 val` against the live quote before trusting the rest.
- **The median, not the mean, for volume.** An earnings gap inflates the 20-day mean by about a quarter for 20 sessions. The median does not move.

---

## What the indicator does NOT show

**The signal.** A close above the high of the previous 10 sessions is not drawn. Claude confirms it with the last 11 daily bars, and you can see it by eye: today's close is above every high of the 10 candles before it.

---

## A complete BUY, read off the chart

Made-up numbers, for the shape of it:

```
SPY           above its blue line, blue above red          regime GREEN
Price         $50.00, closed above the 10-session high     signal
EMA 50        $46.50   -> Dist EMA50 +7.5%, no red zone    not extended
EMA 200       $41.00   -> blue above red                   uptrend
ADR20 %       4.0      -> 1R per share $3.00               stop $47.00
Earnings      31 days away                                 clear
=> BUY: MKT order with TIF = OPG for tomorrow's open,
        GTC stop at fill - $3.00, sell at market 20 sessions later
```

The rules behind every line are in `trading_system.md`, §2.2 to §2.6.
