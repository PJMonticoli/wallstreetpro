"""Should I average down this losing position? A periodic check with a criterion written before the first run.

Run it after the close:
    backtest\\.venv\\Scripts\\python.exe backtest\\averaging_check.py TICKER [--price 3.10] [--refresh]

The position, its resting sell orders and the plans to test live in backtest/averaging_config.json, created by
setup.ps1 from averaging_config.example.json. The cohort is every past episode, across a universe of similar
names, that was in the same state as the position today (far below its EMA50, deep under its 252-day high, in a
Death Cross). Each buy plan is replayed on every episode and compared with doing nothing and with putting the
same money in a broad index fund.
"""
import argparse, json, os, pickle, time, warnings
from datetime import date
import numpy as np, pandas as pd, yfinance as yf
warnings.filterwarnings("ignore")

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, ".cache", "averaging_cohort.pkl")
MINERS = """MP USAR UAMY NB TMC IDR AREC TMQ PPTA NAK UUUU LEU WWR ABAT LAC LAR SGML SLI IONR ATLX
NMG UEC DNN URG NXE EU UROY HYMC GORO USAU PZG VGZ THM GROY DC IAUX CTGO HL CDE AG EXK MUX TGB WRN
LODE XPL AUST NEXA SBSW SQM ALB PLG TRX ODV GATO SILV""".split()
NARR = """OKLO SMR NNE ASTS RKLB JOBY ACHR IONQ RGTI QBTS QUBT LUNR RDW PL SPCE FCEL PLUG BE CHPT QS
LCID RIVN BLNK STEM RUN ENVX MVST SLDP AMPX EOSE GEVO CLNE BLDP WKHS HYLN XOS NKLA GOEV FSR RIDE
BYND PTON OPEN TLRY CGC ACB SNDL OUST MVIS AEVA INDI DNA SANA BFLY CLOV LAZR VLDN SKLZ WISH""".split()
CRYPTO = """COIN MARA RIOT CLSK HUT WULF CIFR IREN BTBT HOOD BKKT MSTR GLXY CORZ BTDR HIVE CAN SOS EBON
GREE ARBK SDIG BTCS BTCM ANY MIGI SLNH APLD BITF SI""".split()
COOLDOWN = 63
H_MID, H_LONG = 130, 504
TBILL_Y, INDEX_Y = 0.025, 0.07
HAIRCUT = 0.10

# The criterion, fixed before the first run. A plan is OPPORTUNE only if, exiting at the combined breakeven, at
# 504 sessions and in every cohort with enough episodes to vote, it meets all three:
#   A) P(exit flat, given it filled) >= fair-bet odds (buy price / new breakeven) + 5 points
#   B) mean effect of the new money, after a 10% bankruptcy haircut, > the same money in an index fund at 7% a year
#   C) median effect of the new money >= 0
# and no fundamentals flag (shares outstanding up 5% or more over the config, a sign of new issuance).
FAIR_MARGIN = 0.05
MIN_N = 30


def load_cohort(refresh):
    if not refresh and os.path.exists(CACHE) and time.time() - os.path.getmtime(CACHE) < 7 * 86400:
        with open(CACHE, "rb") as f:
            return pickle.load(f)
    data = {}
    for t in sorted(set(MINERS + NARR + CRYPTO + ["BTC-USD"])):
        try:
            df = yf.Ticker(t).history(period="max", auto_adjust=True)[["Open", "High", "Low", "Close", "Volume"]].dropna()
            df = df[df["Close"] > 0]
            df.index = pd.to_datetime(df.index.date)
            if len(df) >= 320:
                data[t] = df
        except Exception:
            pass
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    with open(CACHE, "wb") as f:
        pickle.dump(data, f)
    return data


def rsi(c, n=14):
    d = c.diff()
    au = d.clip(lower=0).ewm(alpha=1 / n, adjust=False).mean()
    ad = (-d.clip(upper=0)).ewm(alpha=1 / n, adjust=False).mean()
    return 100 - 100 / (1 + au / ad)


def ind(df):
    c = df["Close"]
    x = {"c": c, "e21": c.ewm(span=21, adjust=False).mean(), "e50": c.ewm(span=50, adjust=False).mean(),
         "e200": c.ewm(span=200, adjust=False).mean(), "hi252": df["High"].rolling(252).max(), "rsi": rsi(c)}
    m = c.ewm(span=12, adjust=False).mean() - c.ewm(span=26, adjust=False).mean()
    x["macd_h"] = m - m.ewm(span=9, adjust=False).mean()
    x["adr"] = (df["High"] / df["Low"]).rolling(20).mean() - 1
    x["volr"] = df["Volume"] / df["Volume"].rolling(50).median()
    return x


def episodes(df, dist_max, dd_max, btc_dd=None, btc_max=None):
    x = ind(df)
    c = x["c"]
    dv = (c * df["Volume"]).rolling(20).median()
    m = x["hi252"].notna() & (dv >= 1e6) & (x["e50"] < x["e200"]) & (c / x["e50"] - 1 <= dist_max) & (c / x["hi252"] - 1 <= dd_max)
    if btc_dd is not None:
        m &= btc_dd.reindex(df.index).ffill() <= btc_max
    out, last = [], -10**9
    o, h, l, cc, e21 = (v.values for v in (df["Open"], df["High"], df["Low"], c, x["e21"]))
    for i in np.flatnonzero(m.values):
        if i - last >= COOLDOWN:
            last = i
            p0 = cc[i]
            out.append({"d": df.index[i], "rsi0": x["rsi"].iloc[i], "o": o[i + 1:] / p0, "h": h[i + 1:] / p0,
                        "l": l[i + 1:] / p0, "c": cc[i + 1:] / p0, "e21": e21[i + 1:] / p0})
    return out


def run(ep, p, sh0, cost0, pre, buys, rule, H):
    o, h, l, c, e21 = (ep[k] * p for k in ("o", "h", "l", "c", "e21"))
    if len(c) < H:
        return None
    sh, cash, new, new_sh, last_fill, out, fair = sh0, 0.0, 0.0, 0.0, None, None, None
    filled = [False] * len(buys)
    pre_r = [list(x) for x in pre]
    for d in range(H):
        if new == 0:
            for r in pre_r:
                if r[0] > 0 and h[d] >= r[1]:
                    q = min(r[0], sh)
                    cash += q * max(r[1], o[d]); sh -= q; r[0] = 0
        else:
            tgt = (cost0 + new - cash) / sh if rule == "BE" else last_fill * (1 + rule)
            if h[d] >= tgt:
                cash += sh * max(tgt, o[d]); sh = 0.0
        if sh <= 1e-9:
            out = d + 1
            break
        for k, (usd, lim) in enumerate(buys):
            if filled[k]:
                continue
            if lim == "EMA21":
                px = o[d] if d >= 1 and c[d - 1] > e21[d - 1] else None
            else:
                px = min(o[d], lim) if l[d] <= lim else None
            if px:
                sh += usd / px; new_sh += usd / px; new += usd; filled[k] = True; last_fill = px
                fair = (new / new_sh) / ((cost0 + new - cash) / sh)
    unfilled = sum(u for (u, _), f in zip(buys, filled) if not f)
    total = cash + sh * c[H - 1] - cost0 - new + unfilled * TBILL_Y * H / 252
    return {"total": total, "filled": any(filled), "out": out, "fair": fair}


def evaluate(eps, p, pos, plans, rules, H, today_pnl, log):
    sh0, cost0, pre = pos["shares"], pos["cost"], pos["sells_gtc"]
    base = [run(e, p, sh0, cost0, pre, [], "BE", H) for e in eps]
    bt = np.array([b["total"] for b in base if b])
    log(f"\n  -- {H} sessions | NO new money (current sell orders): total mean {bt.mean():+.0f} median {np.median(bt):+.0f}"
        f" p10 {np.percentile(bt,10):+.0f} | loses less than today {np.mean(bt > today_pnl):.0%}")
    res = {}
    for name, buys in plans.items():
        usd = sum(u for u, _ in buys)
        for rule in rules:
            rr = [(run(e, p, sh0, cost0, pre, buys, rule, H), b) for e, b in zip(eps, base)]
            rr = [(r, b) for r, b in rr if r and b]
            tot = np.array([r["total"] for r, _ in rr])
            eff = tot - np.array([b["total"] for _, b in rr])
            fill = np.array([r["filled"] for r, _ in rr])
            flat = tot >= -1
            days = [r["out"] for r, _ in rr if r["out"] and r["filled"]]
            fair = np.mean([r["fair"] for r, _ in rr if r["filled"]]) if fill.any() else np.nan
            adj = (1 - HAIRCUT) * eff.mean() - HAIRCUT * usd * fill.mean()
            rn = "breakeven" if rule == "BE" else f"+{rule:.0%} fill"
            res[(name, rn)] = {"flat_fill": flat[fill].mean() if fill.any() else 0, "fair": fair, "adj": adj, "med": np.median(eff)}
            log(f"  {name:30} exit {rn:10} fills {fill.mean():4.0%} | exits flat {flat.mean():4.0%} (if filled {res[(name, rn)]['flat_fill']:4.0%},"
                f" fair {fair:4.0%}) days {int(np.median(days)) if days else 0:3d} | loses less than today {np.mean(tot > today_pnl):4.0%}"
                f" | total median {np.median(tot):+6.0f} p10 {np.percentile(tot,10):+6.0f} | new money: mean {eff.mean():+5.0f}"
                f" (after haircut {adj:+5.0f}) median {np.median(eff):+5.0f} p10 {np.percentile(eff,10):+6.0f} P(loses half or more) {np.mean(eff <= -usd/2):4.0%}")
    return res


def exits(eps, p, pos, H, log):
    sh0 = pos["shares"]
    now = sh0 * p
    plans = {"current sell orders": pos["sells_gtc"]}
    for g in (0.20, 0.35, 0.50, 1.00):
        plans[f"all at +{g:.0%} (${p*(1+g):.2f})"] = [(sh0, round(p * (1 + g), 2))]
    plans["half +35% / half +100%"] = [(sh0 / 2, round(p * 1.35, 2)), (sh0 / 2, round(p * 2, 2))]
    log(f"\n  -- exits with NO new money, {H} sessions | selling today: ${now:,.0f}")
    for name, rungs in plans.items():
        tot, allout, anyout, days = [], [], [], []
        for e in eps:
            if len(e["c"]) < H:
                continue
            hh, cc = e["h"][:H] * p, e["c"][H - 1] * p
            freed, left, last = 0.0, 0.0, 0
            for q, lim in rungs:
                k = np.flatnonzero(hh >= lim)
                if len(k):
                    freed += q * lim; last = max(last, int(k[0]) + 1)
                else:
                    left += q
            tot.append(freed + left * cc); allout.append(left == 0); anyout.append(freed > 0)
            if left == 0:
                days.append(last)
        if not tot:
            continue
        tot = np.array(tot)
        log(f"  {name:28} sells some {np.mean(anyout):4.0%} | sells all {np.mean(allout):4.0%} (median days {int(np.median(days)) if days else 0:3d})"
            f" | final value: mean ${tot.mean():5.0f} median ${np.median(tot):5.0f} p10 ${np.percentile(tot,10):5.0f} | beats selling today {np.mean(tot > now):4.0%}")


def technicals(df, p, log):
    x = ind(df)
    c = x["c"].copy()
    c.iloc[-1] = p
    r = rsi(c)
    rw = rsi(c.resample("W-FRI").last())
    log("\n## Technicals (daily, computed here; cross-check against the TradingView indicator)")
    log(f"  EMA21 ${x['e21'].iloc[-1]:.2f} ({p/x['e21'].iloc[-1]-1:+.0%}) | EMA50 ${x['e50'].iloc[-1]:.2f} ({p/x['e50'].iloc[-1]-1:+.0%})"
        f" | EMA200 ${x['e200'].iloc[-1]:.2f} ({p/x['e200'].iloc[-1]-1:+.0%}) | order "
        f"{'bearish (21<50<200)' if x['e21'].iloc[-1] < x['e50'].iloc[-1] < x['e200'].iloc[-1] else 'mixed'}")
    log(f"  RSI14 daily {r.iloc[-1]:.0f} (20-session low {r.iloc[-20:].min():.0f}) | RSI14 weekly {rw.iloc[-1]:.0f}"
        f" | MACD histogram {x['macd_h'].iloc[-1]:+.3f} ({'rising' if x['macd_h'].iloc[-1] > x['macd_h'].iloc[-2] else 'falling'})")
    lows = df["Low"].iloc[-60:]
    piv = [(d, v) for k, (d, v) in enumerate(lows.items()) if 2 <= k < len(lows) - 2 and v == lows.iloc[k - 2:k + 3].min()]
    div = ""
    if len(piv) >= 2:
        (d1, v1), (d2, v2) = piv[-2], piv[-1]
        r1, r2 = r.loc[d1], r.loc[d2]
        div = f" | last two swing lows {d1.date()} ${v1:.2f} RSI {r1:.0f} and {d2.date()} ${v2:.2f} RSI {r2:.0f}" + (
            ": bullish divergence" if v2 < v1 and r2 > r1 + 2 else ": no divergence")
    log(f"  ADR20 {x['adr'].iloc[-1]:.1%} | last volume {x['volr'].iloc[-1]:.1f}x the 50-session median | down sessions in a row"
        f" {int((c.diff().iloc[::-1] < 0).cumprod().sum())}{div}")
    lo52 = df["Low"].iloc[-252:].min()
    log(f"  52-week low ${lo52:.2f} ({p/lo52-1:+.0%})" + (" | no price support below within the last year" if p <= lo52 * 1.03 else ""))


def tech_tests(eps, log):
    log("\n  ## Does the RSI at entry change the outcome? (same cohort)")
    for lab, sel in (("RSI14 < 25", lambda e: e["rsi0"] < 25), ("RSI14 25-35", lambda e: 25 <= e["rsi0"] < 35), ("RSI14 >= 35", lambda e: e["rsi0"] >= 35)):
        g = [e for e in eps if sel(e) and len(e["c"]) >= 252]
        if len(g) < 10:
            log(f"  {lab:12} n={len(g)} (too few)")
            continue
        c63 = np.array([e["c"][62] - 1 for e in g]); c252 = np.array([e["c"][251] - 1 for e in g])
        race = []
        for e in g:
            up = np.flatnonzero(e["h"][:252] >= 1.5); dn = np.flatnonzero(e["l"][:252] <= 0.7)
            race.append((up[0] if len(up) else 10**9) < (dn[0] if len(dn) else 10**9))
        log(f"  {lab:12} n={len(g):3d} | 63 sessions median {np.median(c63):+.0%} | 252 sessions median {np.median(c252):+.0%} P(>0) {np.mean(c252>0):.0%}"
            f" | +50% before -30%: {np.mean(race):.0%}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ticker")
    ap.add_argument("--price", type=float, help="price to evaluate instead of the last close (what-if)")
    ap.add_argument("--refresh", action="store_true", help="download the cohort again even if the cache is fresh")
    a = ap.parse_args()
    tk = a.ticker.upper()
    cfg_path = os.path.join(HERE, "averaging_config.json")
    if not os.path.exists(cfg_path):
        cfg_path = os.path.join(HERE, "averaging_config.example.json")
    cfg = json.load(open(cfg_path, encoding="utf-8"))[tk]
    lines = []

    def log(s=""):
        print(s)
        lines.append(s)

    df = yf.Ticker(tk).history(period="2y", auto_adjust=True)
    df.index = pd.to_datetime(df.index.date)
    x = ind(df)
    p = a.price or float(x["c"].iloc[-1])
    dist, dd = p / x["e50"].iloc[-1] - 1, p / x["hi252"].iloc[-1] - 1
    ytd = p / x["c"][:f"{date.today().year-1}-12-31"].iloc[-1] - 1
    sh0, cost0 = cfg["shares"], cfg["cost"]
    today_pnl = sh0 * p - cost0
    log(f"# Averaging check {tk} | {date.today()} | price ${p:.2f} | dist EMA50 {dist:+.0%} | from 252-day high {dd:+.0%} | year to date {ytd:+.0%}")
    log(f"  position {sh0} sh, cost ${cost0:,.2f}, value ${sh0*p:,.0f}, P&L {today_pnl:+,.0f}  (config: {os.path.basename(cfg_path)})")
    technicals(df, p, log)

    fz, flags = cfg.get("fundamentals") or {}, []
    if fz.get("shares_out"):
        try:
            so = yf.Ticker(tk).fast_info.get("shares")
        except Exception:
            so = None
        if so:
            ch = so / fz["shares_out"] - 1
            log(f"\n  shares outstanding: config {fz['shares_out']/1e6:.1f}M ({fz['as_of']}), yfinance {so/1e6:.1f}M ({ch:+.0%})")
            if ch >= 0.05:
                flags.append(f"shares {ch:+.0%} over the config: possible new issuance")
        else:
            flags.append("no share count in yfinance: check by hand")
        if fz.get("cash"):
            cps = fz["cash"] / fz["shares_out"]
            log(f"  cash per share ${cps:.2f} ({fz['as_of']}) = {cps/p:.0%} of the price | the market values everything else at ${(p-cps)*fz['shares_out']/1e6:,.0f}M")
    if ytd <= -0.50 and date.today().month in (11, 12) and not (date.today().month == 12 and date.today().day > 20):
        log("  NOTE tax-loss window: big losers of the year often keep falling into the year end. Consider not placing buys before about 20-Dec.")

    data = load_cohort(a.refresh)
    if cfg["cohort"] == "small":
        uni = [t for t in sorted(set(MINERS + NARR)) if t != tk and t in data]
        kws = {"broad": dict(dist_max=min(-0.10, dist + 0.20), dd_max=min(-0.30, dd + 0.06)),
               "strict": dict(dist_max=min(-0.10, dist + 0.10), dd_max=min(-0.30, dd + 0.01))}
    else:
        btc = data["BTC-USD"]["Close"]
        bdd = btc / btc.rolling(365).max() - 1
        uni = [t for t in sorted(set(CRYPTO)) if t != tk and t in data]
        kws = {"broad": dict(dist_max=min(-0.10, dist + 0.10), dd_max=min(-0.30, dd + 0.08), btc_dd=bdd, btc_max=-0.30),
               "strict": dict(dist_max=min(-0.10, dist + 0.05), dd_max=min(-0.30, dd + 0.03), btc_dd=bdd, btc_max=-0.30)}

    limits = list(cfg.get("limits", [])) + [round(p * (1 + q), 2) for q in cfg.get("limits_pct", [])]
    plans = {}
    for u in cfg["usd"]:
        for lim in limits:
            if lim < p:
                plans[f"${u:,} LMT ${lim:.2f}"] = [(u, lim)]
    u = max(cfg["usd"])
    plans[f"${u:,} tranches -20/-35/-50%"] = [(u / 3, round(p * 0.80, 2)), (u / 3, round(p * 0.65, 2)), (u / 3, round(p * 0.50, 2))]
    for name, buys in cfg.get("custom_plans", {}).items():
        if all(lim < p for _, lim in buys):
            plans[name] = [(usd, lim) for usd, lim in buys]
    plans[f"${u:,} on an EMA21 reclaim"] = [(u, "EMA21")]
    plans[f"${u:,} at market"] = [(u, 1e9)]

    verdict, ncoh = {}, {}
    for cname, kw in kws.items():
        eps = []
        for t in uni:
            eps += episodes(data[t], **kw)
        log(f"\n## Cohort {cname}: dist EMA50 <= {kw['dist_max']:+.0%}, from 252-day high <= {kw['dd_max']:+.0%} | {len(eps)} episodes, "
            f"{len(set(e['d'].year for e in eps))} years")
        full = [e for e in eps if len(e["l"]) >= 252]
        ncoh[cname] = len(full)
        if not full:
            continue
        tr = np.array([e["l"][:252].min() - 1 for e in full])
        dy = np.array([int(np.argmin(e["l"][:252])) + 1 for e in full])
        log("  one-year trough: " + " | ".join(f"p{q} ${p*(1+np.percentile(tr,q)):.2f} ({np.percentile(tr,q):+.0%})" for q in (25, 50, 75))
            + f" | sessions to the trough: median {int(np.median(dy))} | trough within the next 70 sessions: {np.mean(dy<=70):.0%}")
        tech_tests(eps, log)
        for H in (H_MID, H_LONG):
            exits(eps, p, cfg, H, log)
        evaluate(eps, p, cfg, plans, ["BE", 0.30], H_MID, today_pnl, log)
        res = evaluate(eps, p, cfg, plans, ["BE"], H_LONG, today_pnl, log)
        log("")
        for name, buys in plans.items():
            r = res[(name, "breakeven")]
            usd = sum(v for v, _ in buys)
            index = usd * ((1 + INDEX_Y) ** (H_LONG / 252) - 1)
            ok = {"A": r["flat_fill"] >= r["fair"] + FAIR_MARGIN, "B": r["adj"] > index, "C": r["med"] >= 0}
            verdict.setdefault(name, {})[cname] = all(ok.values())
            fixed = all(isinstance(lim, float) and lim < 1e8 for _, lim in buys)
            be = f"BE ${(cost0 + usd) / (sh0 + sum(v / lim for v, lim in buys)):.2f} | " if fixed else ""
            log(f"  criterion {name:30} {be}A fair {r['fair']:.0%} vs measured {r['flat_fill']:.0%} {'OK' if ok['A'] else 'NO'}"
                f" | B {r['adj']:+.0f} vs index {index:+.0f} {'OK' if ok['B'] else 'NO'} | C median {r['med']:+.0f} {'OK' if ok['C'] else 'NO'}")

    valid = [c for c in kws if ncoh.get(c, 0) >= MIN_N]
    passed = [n for n, v in verdict.items() if valid and all(v.get(c) for c in valid)]
    if not valid:
        v = f"INCONCLUSIVE: no cohort reaches {MIN_N} episodes"
    elif not passed:
        v = f"NOT OPPORTUNE: no plan passes A, B and C in {' and '.join(valid)}"
    elif flags:
        v = f"criterion met for {', '.join(passed)}, but with flags: {'; '.join(flags)}"
    else:
        v = f"OPPORTUNE for {', '.join(passed)} (deciding cohorts: {', '.join(valid)})"
    skipped = [f"{c} n={ncoh.get(c, 0)}" for c in kws if c not in valid]
    if skipped:
        v += f" | no vote, sample too small: {', '.join(skipped)}"
    log(f"\n## VERDICT {tk}: {v}")
    for f in flags:
        log(f"  flag: {f}")
    log("  Survivors only: names that went bankrupt or were delisted are missing, and they weigh more the deeper the drop.")
    log("  Before any buy, check by hand: new share issuance or ATM program, financing, going concern, today's news.")
    out_dir = os.path.join(HERE, "averaging_check_out")
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, f"{date.today():%Y%m%d}_{tk}{f'_p{a.price:g}' if a.price else ''}.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
