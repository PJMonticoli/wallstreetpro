# CURRENT STATE: capital, positions and P&L

Single source of truth for the volatile data of the system.

- RULES live in `trading_system.md`. They are stable and change rarely.
- DATA (positions, prices, capital, P&L) lives here. It changes often.
- When the portfolio changes, edit ONLY this file.

> This is a template with made-up numbers. `setup.ps1` copies it to `current_state.md`, which is gitignored. Put your real numbers there, never here.

Last updated: 2026-01-05 (example)

---

## ACCOUNT

| Field | Value |
|:---|:---|
| Broker | (your broker) |
| Account type | Cash, T+1 settlement, no margin |
| Order types needed | `MKT` with `TIF = OPG`, and GTC `STOP` |

## CAPITAL

| Pot | Purpose | Amount |
|:---|:---|---:|
| Long-term core | Broad index ETF. Never used for trading, not tracked here | n/a |
| **Trading capital** | The only money this system touches | **USD 10,000** |
| of which, available cash | The ceiling of any notional | USD 10,000 |
| of which, parked | T-bill ETF while there is no open trade | USD 0 |
| **1R (risk per trade)** | 1.5% of trading capital | **USD 150** |

Sizing: shares = 1R / (1.5 x ADR20 x price), rounded down. Notional plus a 20% cushion must fit in the available cash.

## OPEN POSITION (one at a time)

None.

| Ticker | Shares | Fill date | Fill | GTC stop | ADR20 % at entry | 1R per share | Sale date (20 sessions) |
|:---|---:|:---|---:|---:|---:|---:|:---|
| | | | | | | | |

## RESTING ORDERS AT THE BROKER

None.

| Ticker | Side | Quantity | Type | Price | TIF | Purpose |
|:---|:---|---:|:---|---:|:---|:---|
| | | | | | | |

## LEGACY POSITIONS

Positions bought before the system. No new capital on impulse and never averaged (`trading_system.md` §EC).

None.

| Ticker | Shares | Resting sell order | Deadline to resolve | Last quarterly review |
|:---|---:|:---|:---|:---|
| | | | | |

## EXECUTION SCOREBOARD (primary metric, §MET)

| Approved orders | Placed at the broker | Ratio |
|---:|---:|---:|
| 0 | 0 | n/a |

Add one line per approved order, placed or not, with the date and the reason if it was not placed.

## REALIZED RESULT

| Period | Closed trades | Result in R | Result in USD | Commissions |
|:---|---:|---:|---:|---:|
| 2026 year to date | 0 | 0.0R | USD 0.00 | USD 0.00 |

The detail of every trade is in `trade_log.md`.

## KEY DATES

- YYYY-MM-DD: next FOMC decision
- YYYY-MM-DD: next CPI release
- YYYY-MM-DD: next US market holiday
- YYYY-MM-DD: 20-session sale date of the open position

## LOG OF THIS FILE (newest first)

- 2026-01-05: file created from the template.
