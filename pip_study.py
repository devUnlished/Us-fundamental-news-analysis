import json
import urllib.request
from datetime import datetime, timedelta
from collections import defaultdict
import pandas as pd
import yfinance as yf

# Detailed Forensic Pips Study on Gold (XAUUSD / GC=F)
# 1 Gold Dollar move = 10 Pips (e.g. 4474.55 to 4378.55 = $96.00 move = 960 Pips / 9600 points)
# Note: On 2-digit Gold (4474.55), 4474.55 - 4378.55 = 96.00. 
# Many traders refer to $45.00 move as 450 pips and $96.00 as 960 pips.

print("1. Loading Gold Historical Candles...")
# Download GC=F (Gold Futures) or GLD
df_gold = yf.download('GC=F', period='730d', interval='1h')
if df_gold.empty or len(df_gold) < 100:
    df_gold = yf.download('GLD', period='730d', interval='1h')
    is_gld = True
else:
    is_gld = False

if isinstance(df_gold.columns, pd.MultiIndex):
    df_gold.columns = [col[0].lower() for col in df_gold.columns]
else:
    df_gold.columns = [c.lower() for c in df_gold.columns]
df_gold.index = pd.to_datetime(df_gold.index, utc=True)

print(f"Loaded {len(df_gold)} bars (Source: {'GLD' if is_gld else 'GC=F'}).")

# 2. Fetch all historical releases across 3 years
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

print(f"Collected {len(events)} total releases.")

# Filter strictly on our primary focus events:
FOCUS_MAP = {
    "nonfarm payrolls": "NFP",
    "non farm payrolls": "NFP",
    "cpi m/m": "CPI MoM",
    "cpi y/y": "CPI YoY",
    "core cpi": "Core CPI",
    "core pce": "Core PCE",
    "fed interest rate": "FOMC Rate",
    "interest rate decision": "FOMC Rate",
    "retail sales": "Retail Sales",
    "unemployment rate": "Unemployment Rate"
}

results_by_event = defaultdict(list)

for e in events:
    title = (e.get('title') or "").lower()
    match_cat = None
    for k, v in FOCUS_MAP.items():
        if k in title:
            match_cat = v
            break
    if not match_cat:
        continue

    if e.get('actual') is None:
        continue
    fc = e.get('forecast') if e.get('forecast') is not None else e.get('previous')
    if fc is None:
        continue

    try:
        actual = float(e.get('actual'))
        bench = float(fc)
        diff = actual - bench
    except:
        continue

    if abs(diff) < 1e-6:
        continue

    ev_time = pd.to_datetime(e.get('date'), utc=True)
    future = df_gold[(df_gold.index >= ev_time - timedelta(minutes=30)) & (df_gold.index <= ev_time + timedelta(hours=3))]
    if len(future) < 2:
        continue

    # Open at news candle
    entry_p = float(future.iloc[0]['open'])
    max_h = float(future['high'].max())
    min_l = float(future['low'].min())

    # Range in dollars
    total_range_dollars = max_h - min_l
    if is_gld:
        # GLD is approx 1/10th Gold price
        total_range_dollars *= 10.0

    total_pips = total_range_dollars * 10.0 # Standard Forex Gold: $1.00 = 10 pips ($45.00 = 450 pips, $96.00 = 960 pips)

    results_by_event[match_cat].append({
        "date": str(ev_time)[:10],
        "diff": diff,
        "abs_diff": abs(diff),
        "range_dollars": round(total_range_dollars, 2),
        "pips": round(total_pips, 1)
    })

print("\n" + "="*85)
print("     HISTORICAL GOLD NEWS PIP MOVEMENT & SURPRISE CORRELATION STUDY")
print("="*85)

summary_table = {}

for cat, list_items in results_by_event.items():
    if not list_items: continue
    list_items.sort(key=lambda x: x['abs_diff'])
    total_count = len(list_items)
    avg_pips = sum(x['pips'] for x in list_items) / total_count
    max_pip = max(x['pips'] for x in list_items)
    min_pip = min(x['pips'] for x in list_items)

    # Split into: Small Surprise (Bottom 33%), Medium (Middle 33%), Blowout (Top 33%)
    third = max(1, total_count // 3)
    small_subset = list_items[:third]
    medium_subset = list_items[third:2*third]
    blowout_subset = list_items[2*third:]

    avg_small_pips = sum(x['pips'] for x in small_subset) / len(small_subset)
    avg_med_pips = sum(x['pips'] for x in medium_subset) / len(medium_subset)
    avg_blowout_pips = sum(x['pips'] for x in blowout_subset) / len(blowout_subset)

    summary_table[cat] = {
        "count": total_count,
        "avg_pips": round(avg_pips, 1),
        "max_pips": round(max_pip, 1),
        "small_diff": f"< {small_subset[-1]['abs_diff']:.2f}",
        "small_pips": round(avg_small_pips, 1),
        "med_diff": f"{small_subset[-1]['abs_diff']:.2f} - {medium_subset[-1]['abs_diff']:.2f}",
        "med_pips": round(avg_med_pips, 1),
        "blowout_diff": f"> {medium_subset[-1]['abs_diff']:.2f}",
        "blowout_pips": round(avg_blowout_pips, 1)
    }

print(f"{'Event Category':<18} | {'Releases':<8} | {'Avg Pips':<9} | {'Small Surprise':<16} | {'Solid Surprise':<16} | {'Blowout Surprise'}")
print("-" * 95)
for cat, s in summary_table.items():
    print(f"{cat:<18} | {s['count']:<8} | {s['avg_pips']:<9} | {s['small_pips']} pips ({s['small_diff']}) | {s['med_pips']} pips ({s['med_diff']}) | {s['blowout_pips']} pips ({s['blowout_diff']})")

print("="*95)

with open("pip_movement_analysis.json", "w") as f:
    json.dump(summary_table, f, indent=2)
