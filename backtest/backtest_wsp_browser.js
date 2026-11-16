/* ============================================================================
   backtest_wsp_browser.js
   The engine that produced THE NUMBERS published in docs/backtest-findings.md.

   It runs pasted into the console of a browser tab sitting on the origin
   https://query1.finance.yahoo.com (for example by opening
   https://query1.finance.yahoo.com/v8/finance/chart/SPY?range=5d&interval=1d ).
   From that origin the fetch to the chart API is same-origin, so there is no CORS.

   It is published as it ran, for reproducibility. Only comments and identifier
   names were translated to English; the logic is untouched. The equivalent
   version in Python, with yfinance, is backtest_wsp.py.

   Usage:
     await LOAD(UNIVERSE);            // downloads and prepares the data
     STATS(RUN(BASE));                // system v4.5 as written
     STATS(RUN({...BASE, trailMult:null, partialDay:null}));   // variants
   ============================================================================ */

const UNIVERSE = []; // paste the contents of universe.txt here, one ticker per entry

/* == 1. Indicators ======================================================== */
function ema(a, p) {
  const k = 2 / (p + 1), out = new Float64Array(a.length).fill(NaN);
  let s = 0;
  for (let i = 0; i < a.length; i++) {
    if (i < p) { s += a[i]; if (i === p - 1) out[i] = s / p; }
    else out[i] = a[i] * k + out[i - 1] * (1 - k);
  }
  return out;
}
// ADR20 = 20-session SMA of (high/low - 1) x 100. Same quantity as Volatility.M.
function rollMeanRatio(h, l, p) {
  const out = new Float64Array(h.length).fill(NaN); let s = 0;
  for (let i = 0; i < h.length; i++) {
    const x = h[i] / l[i] - 1; s += x;
    if (i >= p) s -= h[i - p] / l[i - p] - 1;
    if (i >= p - 1) out[i] = s / p * 100;
  }
  return out;
}
function rollMean(a, p) {
  const out = new Float64Array(a.length).fill(NaN); let s = 0;
  for (let i = 0; i < a.length; i++) { s += a[i]; if (i >= p) s -= a[i - p]; if (i >= p - 1) out[i] = s / p; }
  return out;
}
// Highest high of the p sessions BEFORE today, today excluded. This is the pivot.
function rollMaxPrev(h, p) {
  const out = new Float64Array(h.length).fill(NaN);
  for (let i = p; i < h.length; i++) { let m = -1e18; for (let k = i - p; k < i; k++) if (h[k] > m) m = h[k]; out[i] = m; }
  return out;
}
function rollMedian(a, p) {
  const out = new Float64Array(a.length).fill(NaN);
  for (let i = p - 1; i < a.length; i++) {
    const w = Array.from(a.slice(i - p + 1, i + 1)).sort((x, y) => x - y); out[i] = w[p >> 1];
  }
  return out;
}

/* == 2. Data loading ====================================================== */
const D = {};
const P1 = Math.floor(Date.parse('2014-06-01') / 1000);
const P2 = Math.floor(Date.parse('2026-09-05') / 1000);

async function grab(sym) {
  try {
    const r = await fetch(`/v8/finance/chart/${sym}?period1=${P1}&period2=${P2}&interval=1d`);
    const j = await r.json(); const res = j.chart?.result?.[0];
    if (!res || !res.timestamp) return 0;
    const q = res.indicators.quote[0];
    const d = [], o = [], h = [], l = [], c = [], v = [];
    for (let i = 0; i < res.timestamp.length; i++) {
      if (q.open[i] == null || q.high[i] == null || q.low[i] == null || q.close[i] == null) continue;
      d.push(+new Date(res.timestamp[i] * 1000).toISOString().slice(0, 10).replace(/-/g, ''));
      o.push(q.open[i]); h.push(q.high[i]); l.push(q.low[i]); c.push(q.close[i]); v.push(q.volume[i] || 0);
    }
    if (d.length < 300) return 0;
    D[sym] = { d, o: Float64Array.from(o), h: Float64Array.from(h), l: Float64Array.from(l),
               c: Float64Array.from(c), v: Float64Array.from(v) };
    return 1;
  } catch (e) { return 0; }
}

async function LOAD(syms) {
  for (let i = 0; i < syms.length; i += 8) await Promise.all(syms.slice(i, i + 8).map(grab));
  for (const s in D) {
    const X = D[s];
    X.e21 = ema(X.c, 21); X.e50 = ema(X.c, 50); X.e200 = ema(X.c, 200);
    X.adr = rollMeanRatio(X.h, X.l, 20);
    const dv = new Float64Array(X.c.length);
    for (let i = 0; i < X.c.length; i++) dv[i] = X.c[i] * X.v[i];
    X.dv = rollMean(dv, 20);
    X.hh10 = rollMaxPrev(X.h, 10);
    X.medv = rollMedian(X.v, 20);
    X.idx = {}; for (let i = 0; i < X.d.length; i++) X.idx[X.d[i]] = i;
  }
  const S = D['SPY']; S.regime = {};
  for (let i = 0; i < S.d.length; i++) S.regime[S.d[i]] = (S.c[i] > S.e50[i] && S.e50[i] > S.e200[i]) ? 1 : 0;
  return Object.keys(D).length;
}

// ETFs in the universe file: loaded, never traded by the simulation.
const ETF = new Set(['SPY','QQQ','XOP','XBI','ARKK','GLD','SMH','IWM','SGOV','VOO']);

/* == 3. Configuration: the system as written at v4.5 ====================== */
const BASE = {
  from: 20150101, to: 20260904,
  pxMin: 10, pxMax: 150, dvMin: 20e6, adrMin: 2.5, adrMax: 8, maxExt: 15, regime: true,
  pattern: 'B', volFilter: false,
  trigOffset: 0.05, gtcDays: 3, chaseMax: 0.05, cancelExt: true, entryMode: 'stop',
  stopMult: 1.0, maxStopPct: 8, maxStopADR: null,
  partialDay: 4, partialFrac: 0.5, bePartial: true, trailMult: 2.5, trailAlways: false,
  timeStop: 10, maxHold: 60, costR: 0.066
};

/* == 4. Signals =========================================================== */
function SIGNALS(cfg) {
  const out = [], SPY = D['SPY'];
  for (const s in D) {
    if (ETF.has(s)) continue;
    const X = D[s];
    for (let i = 250; i < X.d.length - 1; i++) {
      const dt = X.d[i];
      if (dt < cfg.from || dt > cfg.to) continue;
      if (cfg.regime && SPY.regime[dt] !== 1) continue;
      const c = X.c[i], adr = X.adr[i], e50 = X.e50[i], e200 = X.e200[i];
      if (!(c >= cfg.pxMin && c <= cfg.pxMax)) continue;
      if (!(X.dv[i] >= cfg.dvMin)) continue;
      if (!(c > e50 && e50 > e200)) continue;
      if (!((c / e50 - 1) * 100 <= cfg.maxExt)) continue;
      if (!(adr >= cfg.adrMin && adr <= cfg.adrMax)) continue;
      let pivot = X.hh10[i];
      if (cfg.pattern === 'B') {
        if (!(c > X.hh10[i])) continue;
        if (cfg.volFilter && !(X.v[i] >= 1.3 * X.medv[i])) continue;
      } else if (cfg.pattern === 'A') {
        const d21 = (c / X.e21[i] - 1) * 100;
        if (!(d21 >= -1 && d21 <= 5)) continue;
        let green = 0;
        for (let k = i; k > i - 5; k -= 1) { if (X.c[k] > X.c[k - 1]) green += 1; else break; }
        if (green >= 3) continue;
        pivot = X.h[i];
      } // 'ANY' is the control: it requires no pattern at all
      out.push({ s, i, dt, pivot, adr, c, hi: X.h[i], e21: X.e21[i], e50: X.e50[i] });
    }
  }
  out.sort((a, b) => a.dt - b.dt);
  return out;
}

/* == 5. Simulation of one trade ===========================================
   Convention: when the low of a session touches the stop, the stop wins, and
   it fills at min(open, stop). Gaps are punished on purpose.
   ======================================================================== */
function SIM(sig, cfg) {
  const X = D[sig.s], i = sig.i, n = X.d.length;
  let j, fill;
  if (cfg.entryMode === 'open') {
    j = i + 1; if (j >= n) return null; fill = X.o[j];
  } else {
    const trig = sig.hi + cfg.trigOffset;
    if (cfg.chaseMax != null && trig > sig.pivot * (1 + cfg.chaseMax)) return null;
    j = -1;
    for (let k = i + 1; k <= Math.min(i + cfg.gtcDays, n - 1); k++) if (X.h[k] >= trig) { j = k; break; }
    if (j < 0) return null;
    fill = Math.max(trig, X.o[j]);
  }
  if (cfg.cancelExt && fill > X.e50[i] * 1.15) return null;

  const adr$ = sig.adr / 100 * sig.c;
  const R = cfg.stopMult * adr$;
  if (cfg.maxStopADR != null && R / adr$ > cfg.maxStopADR) return null;
  if (cfg.maxStopPct != null && R / fill * 100 > cfg.maxStopPct) return null;

  const stop0 = fill - R;
  let rem = 1, acc = 0, partial = false, hwm = X.h[j], minLo = X.l[j], exitK = j, reason = 'end';
  const trailF = cfg.trailMult != null ? cfg.trailMult * sig.adr / 100 : null;

  for (let k = j; k < Math.min(j + cfg.maxHold, n); k++) {
    if (k > j) { if (X.h[k] > hwm) hwm = X.h[k]; if (X.l[k] < minLo) minLo = X.l[k]; }
    let st = stop0;
    if (partial) { if (cfg.bePartial) st = Math.max(st, fill); if (trailF != null) st = Math.max(st, hwm * (1 - trailF)); }
    else if (cfg.trailAlways && trailF != null) st = Math.max(st, hwm * (1 - trailF));
    if (X.l[k] <= st) { acc += rem * (Math.min(X.o[k], st) - fill); rem = 0; exitK = k; reason = 'stop'; break; }
    if (!partial && cfg.partialDay != null && (k - j) === cfg.partialDay) {
      acc += cfg.partialFrac * (X.c[k] - fill); rem -= cfg.partialFrac; partial = true;
    }
    if (cfg.timeStop != null && (k - j) >= cfg.timeStop && hwm < fill + R) {
      acc += rem * (X.c[k] - fill); rem = 0; exitK = k; reason = 'time'; break;
    }
    exitK = k;
  }
  if (rem > 0) acc += rem * (X.c[exitK] - fill);

  const legs = partial ? 3 : 2, rng = X.h[j] - X.l[j];
  let dd3 = 0; for (let k = j; k < Math.min(j + 4, n); k++) if (fill - X.l[k] >= adr$) dd3 = 1;
  return { s: sig.s, dt: X.d[j], sigdt: sig.dt, fill, R, adr: sig.adr,
           rr: acc / R - (cfg.costR || 0) * legs / 3,
           mfe: (hwm - fill) / R, mae: (fill - minLo) / R,
           pos: rng > 0 ? (fill - X.l[j]) / rng : 0.5,
           held: exitK - j, reason, dd3,
           slip: cfg.entryMode === 'open' ? 0 : (fill - (sig.hi + cfg.trigOffset)) / R };
}

function RUN(cfg) { const T = []; for (const s of SIGNALS(cfg)) { const t = SIM(s, cfg); if (t) T.push(t); } return T; }

/* == 6. Metrics, including ALPHA against SPY ============================== */
function STATS(T) {
  if (!T.length) return { n: 0 };
  const SPY = D['SPY'], avg = a => a.reduce((x, y) => x + y, 0) / a.length;
  const r = T.map(t => t.rr), w = r.filter(x => x > 0), l = r.filter(x => x <= 0);
  const m = avg(r), sd = Math.sqrt(r.reduce((a, b) => a + (b - m) * (b - m), 0) / (r.length - 1));
  const mkt = [];
  for (const t of T) {
    const X = D[t.s], j = X.idx[t.dt], k = Math.min(j + t.held, X.d.length - 1);
    const a = SPY.idx[X.d[j]], b = SPY.idx[X.d[k]];
    if (a != null && b != null) mkt.push((SPY.c[b] / SPY.c[a] - 1) * t.fill / t.R);
  }
  const q = (a, p) => a.slice().sort((x, y) => x - y)[Math.floor(p * a.length)];
  return {
    n: T.length, exp: +m.toFixed(4), sd: +sd.toFixed(2), se: +(sd / Math.sqrt(r.length)).toFixed(3),
    t: +(m / (sd / Math.sqrt(r.length))).toFixed(2),
    market: +avg(mkt).toFixed(3), alpha: +(m - avg(mkt)).toFixed(3),
    win: +(w.length / r.length * 100).toFixed(1),
    avgW: +avg(w).toFixed(3), avgL: +avg(l).toFixed(3),
    medFillPos: +q(T.map(t => t.pos), 0.5).toFixed(2),
    pctPullback1ADR3d: +(avg(T.map(t => t.dd3)) * 100).toFixed(1),
    pctStopBefore05R: +(T.filter(t => t.reason === 'stop' && t.mfe < 0.5).length / T.length * 100).toFixed(1),
    avgSlipR: +avg(T.map(t => t.slip)).toFixed(3),
    nForT2: Math.round(4 * sd * sd / (m * m))
  };
}
