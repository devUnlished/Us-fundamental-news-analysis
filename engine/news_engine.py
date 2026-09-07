"""
Fundamental News Analysis Engine & Rules.
Evaluates high-impact US macroeconomic indicators (NFP, CPI, PPI, Retail Sales, Unemployment Rate, etc.)
and generates Gold (XAUUSD) Buy/Sell signals based on USD strength/weakness.
"""
from typing import Dict, Any, Optional

INDICATOR_RULES = {
    "non farm payrolls": {
        "impact_on_usd_when_actual_higher": 1,
        "importance": 3,
        "name": "Nonfarm Payrolls (NFP)"
    },
    "nonfarm payrolls": {
        "impact_on_usd_when_actual_higher": 1,
        "importance": 3,
        "name": "Nonfarm Payrolls (NFP)"
    },
    "unemployment rate": {
        "impact_on_usd_when_actual_higher": -1,
        "importance": 3,
        "name": "Unemployment Rate"
    },
    "cpi": {
        "impact_on_usd_when_actual_higher": 1,
        "importance": 3,
        "name": "Consumer Price Index (CPI)"
    },
    "core cpi": {
        "impact_on_usd_when_actual_higher": 1,
        "importance": 3,
        "name": "Core CPI"
    },
    "ppi": {
        "impact_on_usd_when_actual_higher": 1,
        "importance": 2,
        "name": "Producer Price Index (PPI)"
    },
    "retail sales": {
        "impact_on_usd_when_actual_higher": 1,
        "importance": 2,
        "name": "Retail Sales"
    },
    "initial jobless claims": {
        "impact_on_usd_when_actual_higher": -1,
        "importance": 2,
        "name": "Initial Jobless Claims"
    },
    "ism manufacturing pmi": {
        "impact_on_usd_when_actual_higher": 1,
        "importance": 2,
        "name": "ISM Manufacturing PMI"
    },
    "ism services pmi": {
        "impact_on_usd_when_actual_higher": 1,
        "importance": 2,
        "name": "ISM Services PMI"
    },
    "fed interest rate decision": {
        "impact_on_usd_when_actual_higher": 1,
        "importance": 3,
        "name": "Fed Interest Rate Decision"
    }
}

def identify_rule(event_title: str) -> Optional[Dict[str, Any]]:
    title_lower = event_title.lower()
    for key, rule in INDICATOR_RULES.items():
        if key in title_lower:
            return rule
    return None

def analyze_event(event: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    title = event.get("title", "")
    rule = identify_rule(title)
    if not rule:
        return None

    actual = event.get("actual")
    forecast = event.get("forecast")
    previous = event.get("previous")

    if actual is None:
        return None

    benchmark = forecast if forecast is not None else previous
    if benchmark is None:
        return None

    try:
        actual_val = float(actual)
        benchmark_val = float(benchmark)
    except (ValueError, TypeError):
        return None

    diff = actual_val - benchmark_val
    impact_dir = rule["impact_on_usd_when_actual_higher"]
    usd_score = diff * impact_dir

    if usd_score > 0:
        usd_sentiment = "STRONG_USD"
        gold_signal = "SELL" # Strong USD -> Drop Gold
        explanation = f"Actual ({actual_val}) beat forecast ({benchmark_val}) -> Strong USD -> SELL GOLD"
    elif usd_score < 0:
        usd_sentiment = "WEAK_USD"
        gold_signal = "BUY"  # Weak USD -> Rally Gold
        explanation = f"Actual ({actual_val}) missed forecast ({benchmark_val}) -> Weak USD -> BUY GOLD"
    else:
        usd_sentiment = "NEUTRAL"
        gold_signal = "NEUTRAL"
        explanation = f"Actual ({actual_val}) matched forecast ({benchmark_val}) -> Neutral"

    return {
        "event_id": event.get("id"),
        "title": event.get("title"),
        "rule_name": rule["name"],
        "date": event.get("date"),
        "actual": actual_val,
        "forecast": benchmark_val,
        "previous": previous,
        "difference": diff,
        "usd_sentiment": usd_sentiment,
        "gold_signal": gold_signal,
        "explanation": explanation,
        "importance": rule["importance"]
    }
