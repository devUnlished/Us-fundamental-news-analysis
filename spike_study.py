import json
import urllib.request
from datetime import datetime, timedelta
from collections import defaultdict
import pandas as pd
import yfinance as yf

# Forensic Spike (Fakeout Wick) Analysis:
# How many pips does Gold wick in the OPPOSITE (wrong) direction before the true move unfolds?

print("1. Loading Gold historical candles...")
df_gold = yf.download('GC=F', period='730d', interval='1h')
if isinstance(df_gold.columns, pd.MultiIndex):
    df_gold.columns = [col[0].lower() for col in df_gold.columns]
else:
    df_gold.columns = [c.lower() for c in df_gold.columns]
df_gold.index = pd.to_datetime(df_gold.index, utc=True)

# Fetch economic events
now = datetime.fromisoformat('2026-09-15T12:00:00')
total_days = 3 * 365
chunk_days = 90
current_start = now - timedelta(days=total_days)

events = []
seen_ids = set()

while current_start < now:
    current_end = min(current_start + timedelta(days=chunk_days), now)
    from_str = current_start.strftime('%Y-%m-%dT%H:%M:%SZ')
    to_str = current_end.strftime('%Y-%m-%dT%H:%M:%SZ')
    url = f"https://economic-calendar.tradingview.com/events?from={from_str}&to={to_str}&countries=US"
    req = urllib.request.Request(url, headers={"Origin": "https://www.tradingview.com", "User-Agent": "Mozilla/5.0"})
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            for e in data.get('result', []):
                eid = e.get('id')
                if eid not in seen_ids:
                    seen_ids.add(eid)
                    events.append(e)
    except:
        pass
    current_start = current_end

RULES = {
    "nonfarm payrolls": {"dir": 1, "name": "NFP", "stdDev": 45.0},
    "non farm payrolls": {"dir": 1, "name": "NFP", "stdDev": 45.0},
    "cpi m/m": {"dir": 1, "name": "CPI", "stdDev": 0.12},
    "cpi y/y": {"dir": 1, "name": "CPI", "stdDev": 0.18},
    "core cpi": {"dir": 1, "name": "CPI", "stdDev": 0.12},
    "core pce": {"dir": 1, "name": "Core PCE", "stdDev": 0.05},
    "retail sales": {"dir": 1, "name": "Retail Sales", "stdDev": 0.22},
    "fed interest rate": {"dir": 1, "name": "FOMC", "stdDev": 0.10},
    "interest rate decision": {"dir": 1, "name": "FOMC", "stdDev": 0.10},
    "unemployment rate": {"dir": -1, "name": "Unemployment", "stdDev": 0.08}
}

def match_rule(title):
    t = (title or "").lower()
    for k, v in RULES.items():
        if k in t: return v
    return None

spike_study = defaultdict(list)

for e in events:
    r = match_rule(e.get('title'))
    if not r or e.get('actual') is None: continue
    fc = e.get('forecast') if e.get('forecast') is not None else e.get('previous')
    if fc is None: continue
    try:
        actual = float(e['actual'])
        bench = float(fc)
        diff = actual - bench
    except:
        continue
    if abs(diff) < 1e-6: continue

    usd_score = diff * r['dir']
    trade_dir = "SELL" if usd_score > 0 else "BUY"
    ratio = abs(diff) / r['stdDev']

    tier = "BLOWOUT" if ratio >= 2.0 else ("SOLID" if ratio >= 1.0 else "MODEST")

    ev_time = pd.to_datetime(e.get('date'), utc=True)
    future = df_gold[(df_gold.index >= ev_time - timedelta(minutes=30)) & (df_gold.index <= ev_time + timedelta(hours=2))]
    if len(future) < 2: continue

    entry_p = float(future.iloc[0]['open'])
    max_h = float(future['high'].max())
    min_l = float(future['low'].min())

    # Adverse Spike (The wrong-way manipulation wick before the real trend):
    # If News is SELL -> Adverse Spike is how high price pumped UP (max_h - entry_p)
    # If News is BUY  -> Adverse Spike is how low price dumped DOWN (entry_p - min_l)
    if trade_dir == "SELL":
        spike_dollars = max(0.0, max_h - entry_p)
        true_move_dollars = max(0.0, entry_p - min_l)
    else: # BUY
        spike_dollars = max(0.0, entry_p - min_l)
        true_move_dollars = max(0.0, max_h - entry_p)

    spike_pips = spike_dollars * 10.0 # 1 Gold dollar = 10 pips
    true_pips = true_move_dollars * 10.0

    spike_study[r['name']].append({
        "tier": tier,
        "diff": diff,
        "ratio": ratio,
        "spike_pips": spike_pips,
        "true_pips": true_pips
    })

print("\n" + "="*85)
print("     3-YEAR ADVERSE SPIKE (FAKE-OUT WICK) DEPTH & TAKE-PROFIT CALIBRATION")
print("="*85)

calibration_matrix = {}

for event_name, records in spike_study.items():
    calibration_matrix[event_name] = {}
    print(f"\n[{event_name}] (Total Releases Analyzed: {len(records)})")
    print(f"{'Tier':<12} | {'Count':<6} | {'Avg Spike Wick (Limit Entry)':<30} | {'Avg True Run (Take Profit)'}")
    print("-" * 80)
    for t in ["MODEST", "SOLID", "BLOWOUT"]:
        sub = [x for x in records if x['tier'] == t]
        if not sub: continue
        avg_spike = sum(x['spike_pips'] for x in sub) / len(sub)
        avg_true = sum(x['true_pips'] for x in sub) / len(sub)
        # 75th percentile spike for safe limit placement:
        sorted_spikes = sorted([x['spike_pips'] for x in sub])
        p75_spike = sorted_spikes[int(len(sorted_spikes) * 0.75)]
        # Safe TP: 65% of true move
        safe_tp = avg_true * 0.65

        calibration_matrix[event_name][t] = {
            "count": len(sub),
            "avg_spike_pips": round(avg_spike, 1),
            "limit_placement_pips": round(p75_spike, 1),
            "limit_placement_dollars": round(p75_spike / 10.0, 2),
            "avg_true_move_pips": round(avg_true, 1),
            "safe_tp_pips": round(safe_tp, 1),
            "safe_tp_dollars": round(safe_tp / 10.0, 2)
        }
        print(f"{t:<12} | {len(sub):<6} | {avg_spike:.1f} pips (P75: {p75_spike:.1f} pips = ${p75_spike/10:.2f}) | {avg_true:.1f} pips (TP: {safe_tp:.1f} pips = ${safe_tp/10:.2f})")

with open("spike_calibration.json", "w") as f:
    json.dump(calibration_matrix, f, indent=2)

print("\n" + "="*85)
print("Calibration saved to spike_calibration.json successfully!")
