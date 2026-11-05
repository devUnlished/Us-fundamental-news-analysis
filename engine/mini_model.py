#!/usr/bin/env python3
"""Mini-model v1: read-only analyzer. Pulls live MT5 data, computes Spec-v2
features, writes a fixed JSON brief + timing/spread logs. Places NO orders.

Usage:  python3 engine/mini_model.py [--symbol XAUUSD]
"""
import csv
import json
import os
import sys
import time
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mt5 import Client

VERSION = "1.0"
DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
BRIEFS = os.path.join(DATA, "briefs")
SPREADS = os.path.join(DATA, "spreads.csv")
EVENTS = os.path.join(DATA, "calendar_events.json")
COUNTRIES = os.path.join(DATA, "calendar_countries.json")
MARGIN_BUFFER = 2.50  # same buffer the EA engine uses; principled, not invented
MIN_BARS = {"M1": 30, "M15": 40, "H1": 60, "D1": 25}

# [TUNABLE] defaults; review at 20-trade sample.
PIVOT_N_M15 = 3
PIVOT_N_H1 = 5
CLUSTER_TOL = 1.50          # $ clustering tolerance for S/R zones
SPREAD_VETO_MULT = 2.0
SPREAD_VETO_MIN_SAMPLES = 20
SPREAD_INTERIM_VETO = 0.50  # 2x literature normal (25c) until medians measured
BLACKOUT_MIN = 5
STALE_PCT_OF_SL = 0.25


def ema(vals, n):
    if len(vals) < n:
        return [None] * len(vals)
    k = 2.0 / (n + 1)
    out = [None] * len(vals)
    seed = sum(vals[:n]) / n
    out[n - 1] = seed
    e = seed
    for i in range(n, len(vals)):
        e = vals[i] * k + e * (1 - k)
        out[i] = e
    return out


def atr_wilder(bars, n=14):
    if len(bars) < n + 1:
        return None
    trs = []
    for i in range(1, len(bars)):
        h, l = bars[i]["high"], bars[i]["low"]
        pc = bars[i - 1]["close"]
        trs.append(max(h - l, abs(h - pc), abs(l - pc)))
    a = sum(trs[:n]) / n
    for t in trs[n:]:
        a = (a * (n - 1) + t) / n
    return a


def pivots(bars, n):
    """N-bar pivots -> (swing_highs [(idx, price)], swing_lows)."""
    hi, lo = [], []
    for i in range(n, len(bars) - n):
        h = bars[i]["high"]
        if all(h > bars[j]["high"] for j in list(range(i - n, i)) + list(range(i + 1, i + n + 1))):
            hi.append((i, h))
        l = bars[i]["low"]
        if all(l < bars[j]["low"] for j in list(range(i - n, i)) + list(range(i + 1, i + n + 1))):
            lo.append((i, l))
    return hi, lo


def roc(vals, n):
    if len(vals) <= n or vals[-n - 1] == 0:
        return None
    return (vals[-1] - vals[-n - 1]) / vals[-n - 1] * 100.0


def anatomy(bar):
    rng = bar["high"] - bar["low"]
    if rng <= 0:
        return {"body": 0.0, "uwick": 0.0, "lwick": 0.0, "tag": "flat"}
    body = abs(bar["close"] - bar["open"]) / rng * 100
    uw = (bar["high"] - max(bar["open"], bar["close"])) / rng * 100
    lw = (min(bar["open"], bar["close"]) - bar["low"]) / rng * 100
    tag = "mixed"
    if body > 70:
        tag = "bull_conviction" if bar["close"] >= bar["open"] else "bear_conviction"
    elif uw + lw > 50:
        tag = "rejection"
    return {"body": round(body, 1), "uwick": round(uw, 1),
            "lwick": round(lw, 1), "tag": tag}


def main():
    symbol = sys.argv[sys.argv.index("--symbol") + 1] if "--symbol" in sys.argv else "XAUUSD"
    os.makedirs(BRIEFS, exist_ok=True)
    t = {}
    mark = lambda k: t.setdefault(k, time.time())
    el = lambda a, b: round(t[b] - t[a], 2)

    mark("start")
    c = Client()
    mark("connect")

    now_utc = datetime.now(timezone.utc).replace(microsecond=0)
    z = lambda dt: dt.isoformat().replace("+00:00", "Z")

    ti = c.call_tool("get_time_information", {})
    srv_now = ti.get("trade_server_last_known_time", "")
    try:
        srv_dt = datetime.fromisoformat(srv_now)
        off = srv_dt.replace(tzinfo=None) - now_utc.replace(tzinfo=None)
        off_min = round(off.total_seconds() / 60)
    except Exception:
        off_min = 0
    mark("time")

    q = c.call_tool("get_marketwatch_symbols", {"symbol": symbol})
    s = (q.get("symbols") or [{}])[0]
    bid, ask = s.get("bid"), s.get("ask")
    spread = round(ask - bid, 2) if bid and ask else None
    mark("quote")

    def hist(period, minutes_back, limit):
        dfrom = z(now_utc - timedelta(minutes=minutes_back))
        dto = z(now_utc + timedelta(minutes=2))
        r = c.call_tool("get_chart_history", {"symbol": symbol, "period": period,
                                              "datetime_from": dfrom, "datetime_to": dto,
                                              "limit": limit})
        return r.get("history", []) if isinstance(r, dict) else []

    m1 = hist("M1", 12 * 60, 150)
    m15 = hist("M15", 4 * 24 * 60, 120)
    h1 = hist("H1", 20 * 24 * 60, 220)
    d1 = hist("D1", 170 * 24 * 60, 110)
    # Retry once on short reads (observed transient truncation); else degrade.
    degraded = []
    for tf, bars, args in (("M1", m1, ("M1", 12 * 60, 150)),
                           ("M15", m15, ("M15", 4 * 24 * 60, 120)),
                           ("H1", h1, ("H1", 20 * 24 * 60, 220)),
                           ("D1", d1, ("D1", 170 * 24 * 60, 110))):
        if len(bars) < MIN_BARS[tf]:
            bars = hist(*args)
            if tf == "M1":
                m1 = bars
            elif tf == "M15":
                m15 = bars
            elif tf == "H1":
                h1 = bars
            else:
                d1 = bars
        if len(bars) < MIN_BARS[tf]:
            degraded.append(f"{tf} short: {len(bars)}<{MIN_BARS[tf]}")
    mark("history")

    acct = c.call_tool("get_trading_account_info", {}).get("account", {})
    mark("account")

    # Calendar in server tz (naive). Offset from measured delta.
    cal_from = (now_utc + timedelta(minutes=off_min) - timedelta(hours=2)).strftime("%Y-%m-%dT%H:%M:%S")
    cal_to = (now_utc + timedelta(minutes=off_min) + timedelta(hours=24)).strftime("%Y-%m-%dT%H:%M:%S")
    cal = c.call_tool("economic_calendar_list_values",
                      {"datetime_from": cal_from, "datetime_to": cal_to, "limit": 500})
    vals = cal if isinstance(cal, list) else cal.get("values", [])
    try:
        evcache = json.load(open(EVENTS)) if os.path.exists(EVENTS) else {}
    except Exception:
        evcache = {}
    have = {k for k, v in evcache.items() if v.get("country_id")}
    new_ids = {v.get("event_id") for v in vals if v.get("event_id")} - have
    for eid in sorted(new_ids)[:60]:
        ev = c.call_tool("economic_calendar_get_event_by_id", {"event_id": str(eid)})
        e = ev.get("event", ev) if isinstance(ev, dict) else {}
        evcache[str(eid)] = {"name": e.get("name"), "country_id": e.get("country_id"),
                             "importance": e.get("importance")}
    try:
        json.dump(evcache, open(EVENTS, "w"), indent=1)
    except Exception:
        pass
    mark("calendar")

    # ---- features ----
    closes = lambda bars: [b["close"] for b in bars]
    atr = {tf: atr_wilder(b) for tf, b in
           (("M1", m1), ("M15", m15), ("H1", h1), ("D1", d1))}
    atr = {k: (round(v, 2) if v else None) for k, v in atr.items()}

    h1c = closes(h1)
    e50, e200 = ema(h1c, 50), ema(h1c, 200)
    m15c = closes(m15)
    e20m = ema(m15c, 20)
    h1_hi, h1_lo = pivots(h1, PIVOT_N_H1)
    m15_hi, m15_lo = pivots(m15, PIVOT_N_M15)

    def struct_dir(hi, lo):
        if len(hi) >= 2 and len(lo) >= 2:
            hh = hi[-1][1] > hi[-2][1]
            hl = lo[-1][1] > lo[-2][1]
            lh = hi[-1][1] < hi[-2][1]
            ll = lo[-1][1] < lo[-2][1]
            if hh and hl:
                return "HH_HL"
            if lh and ll:
                return "LH_LL"
        return "mixed"

    last = h1c[-1] if h1c else None
    up = (e50[-1] and e200[-1] and last > e50[-1] > e200[-1]
          and e50[-1] > (e50[-6] or 0) and struct_dir(h1_hi, h1_lo) == "HH_HL")
    dn = (e50[-1] and e200[-1] and last < e50[-1] < e200[-1]
          and e50[-1] < (e50[-6] or 0) and struct_dir(h1_hi, h1_lo) == "LH_LL")
    regime, reason = ("RANGE", "no trend confirmation")
    if up:
        regime, reason = ("TREND_UP", "H1 C>EMA50>EMA200, EMA50 rising, HH/HL")
    elif dn:
        regime, reason = ("TREND_DOWN", "H1 C<EMA50<EMA200, EMA50 falling, LH/LL")

    # S/R zones from pivot clusters
    pts = [p for _, p in m15_hi[-8:]] + [p for _, p in m15_lo[-8:]] \
        + [p for _, p in h1_hi[-6:]] + [p for _, p in h1_lo[-6:]]
    zones = []
    for p in sorted(pts):
        if zones and abs(p - zones[-1][1]) <= CLUSTER_TOL:
            zones[-1][1] = max(zones[-1][1], p)
            zones[-1][2] += 1
        else:
            zones.append([p, p, 1])
    zones = [{"low": round(a, 2), "high": round(b, 2), "touches": n}
             for a, b, n in zones if n >= 2]
    supports = sorted([zz for zz in zones if zz["high"] < (bid or 0)],
                      key=lambda x: -x["high"])[:3]
    resist = sorted([zz for zz in zones if zz["low"] > (bid or 0)],
                    key=lambda x: x["low"])[:3]
    # round $50s near price
    if bid:
        base = round(bid / 50) * 50
        for lv in (base - 50, base, base + 50):
            tgt = supports if lv < bid else resist
            if len(tgt) < 4:
                tgt.append({"low": lv, "high": lv, "touches": 0, "round": True})

    m1c = closes(m1)
    r10 = roc(m1c, 10)
    r10_prev = roc(m1c[:-3], 10) if len(m1c) > 13 else None
    r20 = roc(m15c, 20)

    def rngpos(cl):
        if len(cl) < 20:
            return None
        w = cl[-20:]
        hi_, lo_ = max(w), min(w)
        return round((cl[-1] - lo_) / (hi_ - lo_) * 100, 1) if hi_ > lo_ else 50.0

    adr = None
    consumed = None
    if len(d1) >= 21:
        ranges = [b["high"] - b["low"] for b in d1[-21:-1]]
        adr = sum(ranges) / len(ranges)
        adr = round(adr, 2)
        # Today's range from M1 bars stamped with today's server date (D1-today
        # bar is often absent from history).
        srv_today = (now_utc + timedelta(minutes=off_min)).strftime("%Y-%m-%d")
        daybars = [b for b in m1 if str(b.get("time", ""))[:10] == srv_today]
        if daybars and adr:
            consumed = round((max(b["high"] for b in daybars)
                              - min(b["low"] for b in daybars)) / adr * 100, 1)

    # gates
    with open(SPREADS, "a", newline="") as f:
        csv.writer(f).writerow([now_utc.isoformat(), bid, ask, spread])
    med = None
    try:
        rows = list(csv.reader(open(SPREADS)))
        sp = sorted(float(r[3]) for r in rows if len(r) > 3 and r[3] not in ("", "None"))
        if len(sp) >= SPREAD_VETO_MIN_SAMPLES:
            med = sp[len(sp) // 2]
    except Exception:
        pass
    if med is not None:
        spread_veto = spread > SPREAD_VETO_MULT * med
        spread_rule = f"spread {spread} vs 2x median {round(med, 2)}"
    else:
        spread_veto = (spread or 0) > SPREAD_INTERIM_VETO
        spread_rule = f"interim: spread {spread} vs cap {SPREAD_INTERIM_VETO}"

    try:
        ccmap = json.load(open(COUNTRIES)) if os.path.exists(COUNTRIES) else {}
    except Exception:
        ccmap = {}
    if not ccmap:
        cc = c.call_tool("economic_calendar_list_countries", {})
        items = cc if isinstance(cc, list) else cc.get("countries", [])
        ccmap = {str(i.get("id")): {"code": i.get("country_code"),
                                    "currency": i.get("currency")}
                 for i in items if i.get("id")}
        try:
            json.dump(ccmap, open(COUNTRIES, "w"), indent=1)
        except Exception:
            pass
    blackout, next_us = False, []
    for v in vals:
        e = evcache.get(str(v.get("event_id")), {})
        cc = ccmap.get(str(e.get("country_id")), {})
        if cc.get("currency") == "USD" and "High" in str(e.get("importance", "")):
            try:
                vt = datetime.fromisoformat(v["time"])
                dtmin = (vt - (now_utc.replace(tzinfo=None)
                               + timedelta(minutes=off_min))).total_seconds() / 60
                next_us.append({"in_min": round(dtmin, 1), "event": e.get("name"),
                                "forecast": v.get("forecast_value"),
                                "prev": v.get("prev_value")})
                if abs(dtmin) <= BLACKOUT_MIN:
                    blackout = True
            except Exception:
                pass
    next_us.sort(key=lambda x: x["in_min"])
    if blackout:
        regime, reason = ("EVENT", "USD high-impact within blackout window")

    mg = c.call_tool("trade_order_calc_margin",
                     {"symbol": symbol, "type": "buy", "volume": 0.01,
                      "price": ask}) if ask else {}
    margin1 = mg.get("margin") if isinstance(mg, dict) else None
    free = acct.get("margin_free", 0) or 0
    margin_fit = bool(margin1 and margin1 + MARGIN_BUFFER <= free)
    mark("features")

    brief = {
        "brief_version": VERSION, "features_version": VERSION,
        "timestamp_utc": z(now_utc), "server_time": srv_now,
        "symbol": symbol,
        "quote": {"bid": bid, "ask": ask, "spread": spread},
        "regime": {"tag": regime, "reason": reason},
        "trend": {"h1_ema50": round(e50[-1], 2) if e50 and e50[-1] else None,
                  "h1_ema200": round(e200[-1], 2) if e200 and e200[-1] else None,
                  "h1_structure": struct_dir(h1_hi, h1_lo),
                  "m15_ema20": round(e20m[-1], 2) if e20m and e20m[-1] else None},
        "structure": {
            "h1_swing_high": h1_hi[-1][1] if h1_hi else None,
            "h1_swing_low": h1_lo[-1][1] if h1_lo else None,
            "m15_swing_high": m15_hi[-1][1] if m15_hi else None,
            "m15_swing_low": m15_lo[-1][1] if m15_lo else None,
            "h1_range_pos": rngpos(h1c), "d1_range_pos": rngpos(closes(d1))},
        "trigger": {"m1_roc10": round(r10, 3) if r10 is not None else None,
                    "m1_roc_accel": round(r10 - r10_prev, 3)
                    if r10 is not None and r10_prev is not None else None,
                    "m15_roc20": round(r20, 3) if r20 is not None else None,
                    "last3_m1": [anatomy(b) for b in m1[-3:]]},
        "levels": {"supports": supports, "resistances": resist},
        "volatility": {"atr": atr, "adr20": adr, "adr_consumed_pct": consumed},
        "calendar": {"usd_high_next": next_us[:5], "blackout": blackout},
        "account": {"balance": acct.get("balance"), "equity": acct.get("equity"),
                    "free_margin": free, "margin_001": margin1},
        "gates": {"spread_veto": bool(spread_veto), "spread_rule": spread_rule,
                  "blackout": blackout, "margin_fit_001": margin_fit},
        "counts": {"m1": len(m1), "m15": len(m15), "h1": len(h1), "d1": len(d1)},
        "degraded": degraded,
        "timings": {"connect": el("start", "connect"), "time": el("connect", "time"),
                    "quote": el("time", "quote"), "history": el("quote", "history"),
                    "account": el("history", "account"),
                    "calendar": el("account", "calendar"),
                    "features": el("calendar", "features"),
                    "total": el("start", "features")},
    }
    fn = os.path.join(BRIEFS, now_utc.strftime("%Y%m%dT%H%M%SZ") + ".json")
    json.dump(brief, open(fn, "w"), indent=1)
    print(json.dumps(brief, indent=1)[:3500])
    print(f"\nbrief -> {fn}")


if __name__ == "__main__":
    main()
