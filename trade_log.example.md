# TRADE LOG: WallStreetPro v5

One row per CLOSED trade. It is the only way to tell bad luck from a badly calibrated rule.
The weekly check adds the row when a position closes (`daily_brief.md`, step 5).

> This is a template. The two rows below are invented, with a made-up ticker, to show how a row is filled in. `setup.ps1` copies this file to `trade_log.md`, which is gitignored. Delete the example rows there before logging your first trade.

How to read it: `trading_system.md` §MAE. Conclude nothing before **n >= 20 trades**.

## How to measure each field

- **MAE (R), maximum adverse excursion:** how far price went AGAINST you before turning, in multiples of R. Entry $50, stop $47, so 1R = $3. If price dropped to $48.65 before rising, MAE = (50 - 48.65) / 3 = 0.45R.
- **MFE (R), maximum favorable excursion:** how far it went IN YOUR FAVOR at its best before you were out, in R.
- **ADR mult:** the entry-to-stop distance in multiples of the ADR20 of the entry day. In v5 it is always **1.50x** by construction. If it differs, something was entered wrong.
- **Entry:** the real fill of the `MKT` / `TIF = OPG` order, not Monday's estimate.
- **Exit:** by `stop` or by `date` (the sale at 20 sessions). Write which one.
- **Slippage (R):** fill minus Monday's close, in R. It is one of the two conditions of the scale-up criterion (§MET): an average under 0.03R over the first 20 trades.
- **Realized R:** net result of the trade in R. A full stop is -1R before slippage.
- **Violations:** a decision made with the market open, a stop that was moved, an order that was approved and not placed, an average-down. "none" is the goal.

Use the intraday low and high of the holding period for MAE and MFE, not the closes.

---

| # | Entry date | Ticker | Entry | Stop | ADR20 % | ADR mult | MAE (R) | MFE (R) | Exit date | Exit | Slippage (R) | Realized R | Commission | Violations |
|:--|:---|:---|---:|---:|---:|---:|---:|---:|:---|:---|---:|---:|---:|:---|
| 1 | 2026-01-06 | EXAMPLE-A | $50.00 | $47.00 | 4.0% | 1.50x | 0.45R | 2.10R | 2026-02-04 | date | 0.05R | **+1.40R** | USD 2.00 | none |
| 2 | 2026-02-10 | EXAMPLE-B | $80.00 | $76.40 | 3.0% | 1.50x | 1.00R | 0.30R | 2026-02-13 | stop | 0.02R | **-1.00R** | USD 2.00 | none |

<!-- Add new rows above this line. -->

### Levels in R for the open trade

Fill this in at the fill, so MAE and MFE can be read off at the close with no recalculation. Example for trade 1:

| | Price |
|:---|---:|
| -1R (stop) | $47.00 |
| -0.5R | $48.50 |
| Entry | $50.00 |
| +0.5R | $51.50 |
| +1R | $53.00 |
| +2R | $56.00 |
| +3R | $59.00 |

---

## Summary (recompute at every close)

- **Closed trades:** 2 (example)
- **Measured expectancy:** +0.20R. With n = 2 this means NOTHING. It is compared against the kill criterion at trade 20.
- **Stop-outs that never reached +0.5R:** 1 of 2
- **Average slippage:** 0.035R. Target to scale up: under 0.03R over 20 trades.
- **Total commissions:** USD 4.00

## Kill criterion (§MET), written before starting and not negotiable

> **At 20 closed trades: if the measured expectancy is negative, the trading capital is closed and everything goes to a broad index ETF.**
