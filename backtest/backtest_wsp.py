#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
backtest_wsp.py :: reproducible backtest of the WallStreetPro swing system

WHAT IT DOES
   Replays, one daily bar at a time, the system as it was written at version 4.5
   (screener universe, breakout pattern, guardrails, exits) and runs the parameter
   sweeps that isolate which rule adds value and which one destroys it. The v5
   rules are one of the measured variants (V0_next_open_v5).

WHY THERE IS A PYTHON ENGINE AND A JAVASCRIPT ENGINE
   The numbers published in docs/backtest-findings.md came out of
   backtest_wsp_browser.js, which ran in a browser because the environment where
   the audit ran had no network route to a price provider. This file is the port
   anyone can run locally with yfinance. The rules are the same. Results will not
   match to the last digit: Yahoo restates history between runs (splits,
   delistings, renamed tickers) and the price band is an absolute filter.

HOW TO RUN
   pip install -r ../requirements.txt
   python backtest_wsp.py
   python backtest_wsp.py universe.txt --start 2014-06-01 --end 2026-09-05

GOLDEN RULE
   The backtest is run by code, never by a language model reasoning about past
   dates. LLMs memorize closes inside their training window and produce look-ahead
   bias. A number that does not come out of running this file is not a measured
   number.
"""

import argparse
import json
import os
import sys
import time

import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))

# ============================================================================
# 1. DEFAULT CONFIGURATION :: the system as written at v4.5
# ============================================================================
BASE = dict(
    # == universe (trading_system.md 2.7) ==
    px_min=10.0, px_max=150.0,          # price band
    dv_min=20e6,                        # 20-day dollar volume >= 20M a day
    adr_min=2.5, adr_max=8.0,           # ADR20 band, in percent
    max_ext=15.0,                       # distance to EMA50 <= 15%
    regime=True,                        # SPY > EMA50 > EMA200
    sig_from=20150101, sig_to=20260904, # window in which a signal may fire
    # == entry (2.3) ==
    pattern="B",                        # "B" breakout | "A" pullback | "ANY" control
    vol_filter=False,                   # volume >= 1.3x its 20-day median (context, not a veto)
    trig_offset=0.05,                   # buy-stop 5 cents above the signal day's high
    gtc_days=3,                         # sessions the buy-stop stays live
    chase_max=0.05,                     # anti-chase: trigger <= 5% above the pivot
    cancel_ext=True,                    # cancel when the fill is more than 15% above EMA50
    entry_mode="stop",                  # "stop" buy-stop | "open" market-on-open | "limit"
    # == limit entry (the "buy the pullback" idea, measured against the open) ==
    limit_ref="pivot",                  # "pivot" (the 10-day high that broke) | "mid" | "close"
    limit_days=3,                       # sessions the limit order stays live
    max_gap_adr=None,                   # with entry_mode="open": skip if it opens > N x ADR above the close
    # == stop (2.4) ==
    stop_mult=1.0,                      # 1R = stop_mult x ADR20, in dollars
    max_stop_pct=8.0,                   # hard cap of 8% of price (None disables it)
    max_stop_adr=None,                  # veto above N x ADR (None measures the clean sweep)
    # == exits (2.6 as of v4.5) ==
    partial_day=4,                      # time-based partial of 1/2 on session 4 after the fill
    partial_frac=0.5,
    be_partial=True,                    # move the stop of the remainder to breakeven after the partial
    trail_mult=2.5,                     # trailing stop at 2.5 x ADR20
    trail_always=False,
    time_stop=10,                       # no +1R after 10 sessions: close
    max_hold=60,
    # == friction ==
    # Cost of 3 executions, in R: $0.35 minimum commission per execution over a
    # reference 1R of about $16. A trade pays cost_r * legs / 3.
    cost_r=0.066,
)

# ETFs listed in the universe file. They are loaded (SPY drives the regime filter
# and the benchmark) but the simulation never trades them, same as the JS engine.
ETFS = {"SPY", "QQQ", "XOP", "XBI", "ARKK", "GLD", "SMH", "IWM", "SGOV", "VOO"}


# ============================================================================
# 2. INDICATORS :: same definitions as the Pine indicator of the project
# ============================================================================
def ema(a, p):
    return pd.Series(a).ewm(span=p, adjust=False, min_periods=p).mean().to_numpy()


def adr20(h, l, p=20):
    """ADR20 = 20-session SMA of (high / low - 1) x 100. It is the definition used
    by the Pine indicator and the same quantity as TradingView's Volatility.M.
    ATR is not used on purpose: ATR includes gaps, which is exactly what the stop
    wants to leave out."""
    r = pd.Series(h / l - 1.0)
    return (r.rolling(p).mean() * 100).to_numpy()


def roll_dollar_vol(c, v, p=20):
    return pd.Series(c * v).rolling(p).mean().to_numpy()


def roll_max_prev(h, p):
    """Highest high of the p sessions BEFORE today, today excluded. This is the pivot."""
    return pd.Series(h).shift(1).rolling(p).max().to_numpy()


def prepare(df):
    o, h, l, c, v = (df[k].to_numpy(float) for k in ("Open", "High", "Low", "Close", "Volume"))
    d = np.array([int(x.strftime("%Y%m%d")) for x in df.index])
    return dict(d=d, o=o, h=h, l=l, c=c, v=v,
                e21=ema(c, 21), e50=ema(c, 50), e200=ema(c, 200),
                adr=adr20(h, l), dv=roll_dollar_vol(c, v),
                hh10=roll_max_prev(h, 10), medv=pd.Series(v).rolling(20).median().to_numpy(),
                idx={int(x): i for i, x in enumerate(d)})


# ============================================================================
# 3. SIGNALS
# ============================================================================
def signals(data, cfg):
    out = []
    for sym, D in data.items():
        if sym in ETFS:
            continue
        c, e50, e200, adr, d = D["c"], D["e50"], D["e200"], D["adr"], D["d"]
        n = len(c)
        with np.errstate(invalid="ignore", divide="ignore"):
            ok = ((d >= cfg["sig_from"]) & (d <= cfg["sig_to"])
                  & (c >= cfg["px_min"]) & (c <= cfg["px_max"])
                  & (D["dv"] >= cfg["dv_min"])
                  & (c > e50) & (e50 > e200)
                  & ((c / e50 - 1) * 100 <= cfg["max_ext"])
                  & (adr >= cfg["adr_min"]) & (adr <= cfg["adr_max"]))
            if cfg["regime"]:
                ok &= D["reg"]
            if cfg["pattern"] == "B":
                ok &= c > D["hh10"]
                if cfg["vol_filter"]:
                    ok &= D["v"] >= 1.3 * D["medv"]
            elif cfg["pattern"] == "A":
                d21 = (c / D["e21"] - 1) * 100
                ok &= (d21 >= -1) & (d21 <= 5)
            # "ANY" is the control: no pattern required at all
        ok[:250] = False          # warm-up for EMA200 and ADR20
        ok[max(n - 1, 0):] = False  # the last bar has no next session to fill on
        for i in np.flatnonzero(ok):
            pivot = D["hh10"][i]
            if cfg["pattern"] == "A":
                green = 0
                for k in range(i, i - 5, -1):
                    if c[k] > c[k - 1]:
                        green += 1
                    else:
                        break
                if green >= 3:
                    continue
                pivot = D["h"][i]
            out.append(dict(sym=sym, i=int(i), dt=int(d[i]), pivot=float(pivot), adr=float(adr[i]),
                            c=float(c[i]), hi=float(D["h"][i])))
    out.sort(key=lambda s: s["dt"])
    return out


# ============================================================================
# 4. SIMULATION OF ONE TRADE
#    Conservative convention: when the low of a session touches the stop, the
#    stop is assumed to execute BEFORE anything else that session, and it fills
#    at min(open, stop) so that gaps are punished.
# ============================================================================
def simulate(D, sig, cfg):
    i, n = sig["i"], len(D["c"])
    adr_d = sig["adr"] / 100.0 * sig["c"]
    if cfg["entry_mode"] == "open":
        j = i + 1
        if j >= n:
            return None
        fill = D["o"][j]
        # anti-gap filter: if it opens too far above the close the trade is born expensive
        if cfg.get("max_gap_adr") is not None and (fill - sig["c"]) > cfg["max_gap_adr"] * adr_d:
            return None
    elif cfg["entry_mode"] == "limit":
        # A BUY LIMIT executes at the limit OR BETTER. If the session opens below the
        # reference it fills at the open. Otherwise it fills at the reference only if
        # the low touches it. If it never does, THERE IS NO TRADE: that signal is lost,
        # which is why expectancy is also reported PER SIGNAL and not only per fill.
        ref = {"pivot": sig["pivot"],
               "mid": 0.5 * (sig["pivot"] + sig["c"]),
               "close": sig["c"]}[cfg["limit_ref"]]
        j, fill = -1, None
        for k in range(i + 1, min(i + cfg["limit_days"], n - 1) + 1):
            if D["o"][k] <= ref:
                j, fill = k, D["o"][k]
                break
            if D["l"][k] <= ref:
                j, fill = k, ref
                break
        if j < 0:
            return None
    else:
        trig = sig["hi"] + cfg["trig_offset"]
        if cfg["chase_max"] is not None and trig > sig["pivot"] * (1 + cfg["chase_max"]):
            return None
        j = -1
        for k in range(i + 1, min(i + cfg["gtc_days"], n - 1) + 1):
            if D["h"][k] >= trig:
                j = k
                break
        if j < 0:
            return None
        fill = max(trig, D["o"][j])
    if cfg["cancel_ext"] and fill > D["e50"][i] * 1.15:
        return None

    R = cfg["stop_mult"] * adr_d
    if cfg["max_stop_adr"] is not None and R / adr_d > cfg["max_stop_adr"]:
        return None
    if cfg["max_stop_pct"] is not None and R / fill * 100 > cfg["max_stop_pct"]:
        return None

    stop0 = fill - R
    rem, acc, partial = 1.0, 0.0, False
    hwm, mlo, exit_k, reason = D["h"][j], D["l"][j], j, "end"
    trail_f = cfg["trail_mult"] * sig["adr"] / 100.0 if cfg["trail_mult"] is not None else None

    for k in range(j, min(j + cfg["max_hold"], n)):
        if k > j:
            hwm = max(hwm, D["h"][k])
            mlo = min(mlo, D["l"][k])
        st = stop0
        if partial:
            if cfg["be_partial"]:
                st = max(st, fill)
            if trail_f is not None:
                st = max(st, hwm * (1 - trail_f))
        elif cfg["trail_always"] and trail_f is not None:
            st = max(st, hwm * (1 - trail_f))
        if D["l"][k] <= st:
            acc += rem * (min(D["o"][k], st) - fill)
            rem = 0.0
            exit_k = k
            reason = "stop"
            break
        if (not partial) and cfg["partial_day"] is not None and (k - j) == cfg["partial_day"]:
            acc += cfg["partial_frac"] * (D["c"][k] - fill)
            rem -= cfg["partial_frac"]
            partial = True
        if cfg["time_stop"] is not None and (k - j) >= cfg["time_stop"] and hwm < fill + R:
            acc += rem * (D["c"][k] - fill)
            rem = 0.0
            exit_k = k
            reason = "time"
            break
        exit_k = k
    if rem > 0:
        acc += rem * (D["c"][exit_k] - fill)

    legs = 3 if partial else 2
    dd3 = int(any(fill - D["l"][k] >= adr_d for k in range(j, min(j + 4, n))))
    rng = D["h"][j] - D["l"][j]
    return dict(sym=sig["sym"], dt=int(D["d"][j]), xdt=int(D["d"][exit_k]), fill=float(fill), R=float(R),
                adr=sig["adr"],
                rr=float(acc / R - cfg["cost_r"] * legs / 3),
                mfe=float((hwm - fill) / R), mae=float((fill - mlo) / R),
                pos=float((fill - D["l"][j]) / rng) if rng > 0 else 0.5,
                held=exit_k - j, reason=reason, dd3=dd3,
                slip=float((fill - (sig["hi"] + cfg["trig_offset"])) / R) if cfg["entry_mode"] == "stop" else 0.0)


# ============================================================================
# 5. METRICS
# ============================================================================
def stats(T, n_sig=None, spy=None):
    if not T:
        return dict(n=0, n_signals=n_sig)
    r = np.array([t["rr"] for t in T])
    w, l = r[r > 0], r[r <= 0]
    out = {}
    # exp_per_signal is the honest metric when order types are compared. A limit
    # order that does not fill is NOT a neutral trade, it is a lost signal. Measured
    # on fills only, the limit order always wins by construction, because the days
    # the stock runs away (the winners) drop out of the sample. Here unfilled
    # signals count as 0 in the numerator and as 1 in the denominator.
    if n_sig:
        out.update(n_signals=n_sig,
                   fill_rate=round(100.0 * len(r) / n_sig, 1),
                   exp_per_signal=round(float(r.sum() / n_sig), 4))
    sd = float(r.std(ddof=1)) if len(r) > 1 else 0.0
    se = sd / np.sqrt(len(r)) if len(r) > 1 else 0.0
    out.update(
        n=len(r), exp=round(float(r.mean()), 4), sd=round(sd, 2), se=round(float(se), 3),
        t=round(float(r.mean() / se), 2) if se > 0 else None,
        win=round(100 * len(w) / len(r), 1),
        avg_w=round(float(w.mean()) if len(w) else 0.0, 3),
        avg_l=round(float(l.mean()) if len(l) else 0.0, 3),
        med_mfe=round(float(np.median([t["mfe"] for t in T])), 2),
        med_fill_pos=round(float(np.median([t["pos"] for t in T])), 2),
        pct_pullback_1adr_3d=round(100 * float(np.mean([t["dd3"] for t in T])), 1),
        pct_stop_before_05R=round(100 * float(np.mean([t["reason"] == "stop" and t["mfe"] < 0.5 for t in T])), 1),
        avg_slip_R=round(float(np.mean([t["slip"] for t in T])), 3),
        # trades needed to tell this expectancy apart from zero at t = 2
        n_for_t2=int(round(4 * r.var(ddof=1) / (r.mean() ** 2))) if len(r) > 1 and r.mean() != 0 else None,
    )
    # ALPHA: for every trade, the SPY return over the exact same holding period,
    # expressed in the same R units. Expectancy minus that is what the rules add
    # on top of simply being long the market.
    if spy is not None:
        mkt = []
        for t in T:
            a, b = spy["idx"].get(t["dt"]), spy["idx"].get(t["xdt"])
            if a is not None and b is not None:
                mkt.append((spy["c"][b] / spy["c"][a] - 1) * t["fill"] / t["R"])
        if mkt:
            m = float(np.mean(mkt))
            out.update(market=round(m, 3), alpha=round(float(r.mean()) - m, 3))
    # stability: expectancy by calendar year of the entry
    years = {}
    for t in T:
        years.setdefault(t["dt"] // 10000, []).append(t["rr"])
    means = {y: float(np.mean(v)) for y, v in sorted(years.items())}
    out.update(years_positive=sum(1 for v in means.values() if v > 0), years_total=len(means),
               by_year={str(y): round(v, 3) for y, v in means.items()})
    return out


# ============================================================================
# 6. PASS / FAIL CRITERION :: written before the first run, not after
# ============================================================================
CRITERION = """
The system PASSES if and only if all four conditions hold at once:
  1. Expectancy net of commissions and slippage > +0.15R over n >= 1000 trades.
  2. Student's t > 2 against zero.
  3. ALPHA > +0.10R, that is, expectancy minus the market return over the time
     each trade was open. Without this the result is beta, and an index fund
     delivers beta cheaper.
  4. Positive expectancy in at least 8 of the 12 calendar years of the period.
If any of the four fails, the system is NOT funded with new capital.
"""


def verdict(s):
    checks = [
        ("expectancy > +0.15R with n >= 1000", s.get("n", 0) >= 1000 and s.get("exp", 0) > 0.15,
         f"exp {s.get('exp')}R, n {s.get('n')}"),
        ("t > 2", (s.get("t") or 0) > 2, f"t {s.get('t')}"),
        ("alpha > +0.10R", s.get("alpha") is not None and s["alpha"] > 0.10, f"alpha {s.get('alpha')}R"),
        ("positive in 8 of 12 years", s.get("years_positive", 0) >= 8,
         f"{s.get('years_positive')} of {s.get('years_total')}"),
    ]
    lines = [f"  [{'PASS' if ok else 'FAIL'}] {name}: {got}" for name, ok, got in checks]
    lines.append("  => " + ("SYSTEM PASSES" if all(ok for _, ok, _ in checks) else "SYSTEM FAILS"))
    return "\n".join(lines)


# ============================================================================
# 7. DATA
# ============================================================================
def load(sym, start, end, cache=None):
    path = os.path.join(cache, f"{sym}_{start}_{end}.csv") if cache else None
    if path and os.path.exists(path):
        df = pd.read_csv(path, index_col=0, parse_dates=True)
    else:
        import yfinance as yf
        df = None
        for attempt in range(3):
            try:
                df = yf.download(sym, start=start, end=end, progress=False, auto_adjust=False, timeout=30)
            except Exception:
                df = None
            if df is not None and len(df) > 0:
                break
            time.sleep(2 * (attempt + 1))
        if df is None or len(df) == 0:
            return None
        if isinstance(df.columns, pd.MultiIndex):
            df.columns = df.columns.get_level_values(0)
        df = df[["Open", "High", "Low", "Close", "Volume"]].dropna()
        if path:
            df.to_csv(path)
    return df if len(df) >= 300 else None


# ============================================================================
# 8. MAIN
# ============================================================================
def main():
    ap = argparse.ArgumentParser(description="Backtest of the WallStreetPro swing system (daily bars, yfinance).")
    ap.add_argument("universe", nargs="?", default=os.path.join(HERE, "universe.txt"),
                    help="file with one ticker per line (default: universe.txt next to this script)")
    ap.add_argument("--start", default="2014-06-01", help="first bar to download; warm-up for EMA200 and ADR20")
    ap.add_argument("--end", default="2026-09-05", help="download end date, exclusive")
    ap.add_argument("--signals-from", default="2015-01-01", help="first date on which a signal may fire")
    ap.add_argument("--out", default=os.path.join(HERE, "results.json"), help="where to write the results")
    ap.add_argument("--cache", default=os.path.join(HERE, ".cache"),
                    help="folder for downloaded bars, so a second run is offline ('' disables it)")
    a = ap.parse_args()

    cache = a.cache or None
    if cache:
        os.makedirs(cache, exist_ok=True)

    with open(a.universe, encoding="utf-8") as fh:
        syms = [s.strip().upper() for s in fh if s.strip() and not s.startswith("#")]
    print(f"universe: {len(syms)} tickers", file=sys.stderr)

    spy = load("SPY", a.start, a.end, cache)
    if spy is None:
        sys.exit("could not download SPY: check the network connection and try again")
    S = prepare(spy)
    spy_regime = {int(S["d"][i]): bool(S["c"][i] > S["e50"][i] > S["e200"][i]) for i in range(len(S["c"]))}

    data, failed = {}, []
    for k, s in enumerate(syms):
        df = load(s, a.start, a.end, cache)
        if df is not None:
            D = prepare(df)
            D["reg"] = np.array([spy_regime.get(int(x), False) for x in D["d"]], dtype=bool)
            data[s] = D
        else:
            failed.append(s)
        if k % 25 == 0:
            print(f"  {k}/{len(syms)}", file=sys.stderr)
    traded = [s for s in data if s not in ETFS]
    print(f"loaded: {len(data)} ({len(traded)} tradable, {len(data) - len(traded)} ETFs)", file=sys.stderr)
    if failed:
        print(f"skipped, no data or under 300 bars: {' '.join(failed)}", file=sys.stderr)

    window = dict(sig_from=int(a.signals_from.replace("-", "")), sig_to=int(a.end.replace("-", "")))

    def run(**over):
        cfg = dict(BASE)
        cfg.update(window)
        cfg.update(over)
        sg = signals(data, cfg)
        T = [t for t in (simulate(data[s["sym"]], s, cfg) for s in sg) if t]
        return stats(T, len(sg), S)

    R = {"_meta": dict(universe=len(syms), loaded=len(data), tradable=len(traded),
                       start=a.start, end=a.end, signals_from=a.signals_from)}

    # ---- the system as written, and the attribution of each exit rule ----
    R["A_system_v45_as_written"] = run()
    R["B_no_trailing"] = run(trail_mult=None)
    R["C_no_trailing_no_breakeven"] = run(trail_mult=None, be_partial=False)
    R["D_initial_stop_and_time_only"] = run(trail_mult=None, partial_day=None)
    R["E_entry_at_next_open"] = run(trail_mult=None, partial_day=None, entry_mode="open")
    R["F_control_any_screener_day"] = run(trail_mult=None, partial_day=None, entry_mode="open", pattern="ANY")
    R["G_pattern_A_pullback"] = run(trail_mult=None, partial_day=None, pattern="A")
    for m in (0.5, 0.75, 1.0, 1.5, 2.0, 2.5, 3.0):
        R[f"stop_{m}xADR"] = run(stop_mult=m, max_stop_pct=None)

    # ---- stop x holding period, entry at the next open, no other exit rule ----
    # Twelve cells. The question each one answers is the same: is there alpha?
    for m in (1.0, 1.5, 2.0, 2.5):
        for h in (10, 20, 40):
            R[f"grid_stop{m}_hold{h}"] = run(entry_mode="open", stop_mult=m, max_hold=h, max_stop_pct=None,
                                             trail_mult=None, partial_day=None, time_stop=None,
                                             chase_max=None)

    # ---- order types on top of the v5 rules ----
    # The metric that decides here is exp_per_signal, NOT exp. See stats().
    V5 = dict(trail_mult=None, partial_day=None, time_stop=None, max_hold=20,
              stop_mult=1.5, max_stop_pct=None, max_stop_adr=None,
              chase_max=None, cost_r=0.070)
    R["V0_next_open_v5"] = run(entry_mode="open", **V5)
    R["V1_limit_at_pivot"] = run(entry_mode="limit", limit_ref="pivot", **V5)
    R["V2_limit_at_midpoint"] = run(entry_mode="limit", limit_ref="mid", **V5)
    R["V3_limit_at_signal_close"] = run(entry_mode="limit", limit_ref="close", **V5)
    R["V4_open_skip_gap_1ADR"] = run(entry_mode="open", max_gap_adr=1.0, **V5)
    R["V5_open_skip_gap_0_5ADR"] = run(entry_mode="open", max_gap_adr=0.5, **V5)
    R["V6_buy_stop_reference"] = run(entry_mode="stop", **V5)
    for d in (1, 2, 5, 10):
        R[f"V1_pivot_live_{d}d"] = run(entry_mode="limit", limit_ref="pivot", limit_days=d, **V5)

    print(json.dumps(R, indent=1))
    with open(a.out, "w", encoding="utf-8") as fh:
        json.dump(R, fh, indent=1)
    print(CRITERION, file=sys.stderr)
    print("Verdict for A_system_v45_as_written:", file=sys.stderr)
    print(verdict(R["A_system_v45_as_written"]), file=sys.stderr)
    print(f"\nresults written to {a.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
