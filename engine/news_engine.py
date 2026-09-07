"""
Comprehensive Fundamental News Analysis Engine & Rules for US News.
Covers all major volatility-inducing US events:
- Tier 1: NFP, CPI, Core CPI, FOMC Rate Decisions, Fed Funds Rate
- Tier 2: Core PCE Price Index, Retail Sales, Advance GDP, ISM Services PMI, ISM Manufacturing PMI
- Tier 3: PPI, Initial Jobless Claims, JOLTs Job Openings, UoM Consumer Sentiment
"""
from typing import Dict, Any, Optional

# impact_on_usd_when_actual_higher:
#  +1 -> Higher actual = Stronger USD = SELL GOLD (XAUUSD)
#  -1 -> Higher actual = Weaker USD = BUY GOLD (XAUUSD)
INDICATOR_RULES = {
    # Nonfarm Payrolls & Employment
    "non farm payrolls": {"dir": 1, "tier": 1, "name": "Nonfarm Payrolls (NFP)"},
    "nonfarm payrolls": {"dir": 1, "tier": 1, "name": "Nonfarm Payrolls (NFP)"},
    "unemployment rate": {"dir": -1, "tier": 1, "name": "Unemployment Rate"},
    "average hourly earnings": {"dir": 1, "tier": 2, "name": "Average Hourly Earnings"},
    "initial jobless claims": {"dir": -1, "tier": 3, "name": "Initial Jobless Claims"},
    "jolts job openings": {"dir": 1, "tier": 2, "name": "JOLTs Job Openings"},
    "adp employment change": {"dir": 1, "tier": 3, "name": "ADP Employment Change"},

    # Inflation (CPI, PCE, PPI)
    "cpi": {"dir": 1, "tier": 1, "name": "Consumer Price Index (CPI)"},
    "core cpi": {"dir": 1, "tier": 1, "name": "Core CPI"},
    "core pce price index": {"dir": 1, "tier": 1, "name": "Core PCE Price Index"},
    "pce price index": {"dir": 1, "tier": 2, "name": "PCE Price Index"},
    "ppi": {"dir": 1, "tier": 2, "name": "Producer Price Index (PPI)"},
    "core ppi": {"dir": 1, "tier": 2, "name": "Core PPI"},

    # Central Bank / Interest Rates / FOMC
    "fed interest rate decision": {"dir": 1, "tier": 1, "name": "Fed Interest Rate Decision"},
    "interest rate decision": {"dir": 1, "tier": 1, "name": "Interest Rate Decision"},
    "fed funds rate": {"dir": 1, "tier": 1, "name": "Fed Funds Target Rate"},
    "fomc": {"dir": 1, "tier": 1, "name": "FOMC Statement / Decision"},

    # Growth & Activity (GDP, Retail Sales, PMIs)
    "retail sales": {"dir": 1, "tier": 2, "name": "Retail Sales"},
    "core retail sales": {"dir": 1, "tier": 2, "name": "Core Retail Sales"},
    "gdp": {"dir": 1, "tier": 2, "name": "Gross Domestic Product (GDP)"},
    "ism manufacturing pmi": {"dir": 1, "tier": 2, "name": "ISM Manufacturing PMI"},
    "ism services pmi": {"dir": 1, "tier": 2, "name": "ISM Services PMI"},
    "michigan consumer sentiment": {"dir": 1, "tier": 3, "name": "UoM Consumer Sentiment"}
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
    impact_dir = rule["dir"]
    usd_score = diff * impact_dir

    if usd_score > 0:
        usd_sentiment = "STRONG_USD"
        gold_signal = "SELL"
        explanation = f"{rule['name']}: Actual ({actual_val}) beat forecast/prior ({benchmark_val}) -> Strong USD -> SELL GOLD"
    elif usd_score < 0:
        usd_sentiment = "WEAK_USD"
        gold_signal = "BUY"
        explanation = f"{rule['name']}: Actual ({actual_val}) missed forecast/prior ({benchmark_val}) -> Weak USD -> BUY GOLD"
    else:
        usd_sentiment = "NEUTRAL"
        gold_signal = "NEUTRAL"
        explanation = f"{rule['name']}: Actual ({actual_val}) matched forecast/prior ({benchmark_val}) -> Neutral"

    return {
        "event_id": event.get("id"),
        "title": event.get("title"),
        "rule_name": rule["name"],
        "tier": rule["tier"],
        "date": event.get("date"),
        "actual": actual_val,
        "forecast": benchmark_val,
        "previous": previous,
        "difference": diff,
        "usd_sentiment": usd_sentiment,
        "gold_signal": gold_signal,
        "explanation": explanation
    }
