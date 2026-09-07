// Background Service Worker: polls calendar API and dispatches signals to active tabs
const SEEN_EVENTS_KEY = "seen_news_event_ids";

const INDICATOR_RULES = {
  // Tier 1: Mega Volatility
  "non farm payrolls": { dir: 1, name: "Nonfarm Payrolls (NFP)", tier: 1 },
  "nonfarm payrolls": { dir: 1, name: "Nonfarm Payrolls (NFP)", tier: 1 },
  "unemployment rate": { dir: -1, name: "Unemployment Rate", tier: 1 },
  "cpi": { dir: 1, name: "Consumer Price Index (CPI)", tier: 1 },
  "core cpi": { dir: 1, name: "Core CPI", tier: 1 },
  "core pce": { dir: 1, name: "Core PCE Price Index", tier: 1 },
  "pce price index": { dir: 1, name: "PCE Price Index", tier: 2 },
  "fed interest rate": { dir: 1, name: "Fed Interest Rate Decision", tier: 1 },
  "interest rate decision": { dir: 1, name: "Interest Rate Decision", tier: 1 },
  "fed funds": { dir: 1, name: "Fed Funds Rate", tier: 1 },
  "fomc": { dir: 1, name: "FOMC Rate / Statement", tier: 1 },

  // Tier 2: High Volatility
  "retail sales": { dir: 1, name: "Retail Sales", tier: 2 },
  "core retail sales": { dir: 1, name: "Core Retail Sales", tier: 2 },
  "gdp": { dir: 1, name: "Gross Domestic Product (GDP)", tier: 2 },
  "ism manufacturing": { dir: 1, name: "ISM Manufacturing PMI", tier: 2 },
  "ism services": { dir: 1, name: "ISM Services PMI", tier: 2 },
  "ppi": { dir: 1, name: "Producer Price Index (PPI)", tier: 2 },
  "jolts": { dir: 1, name: "JOLTs Job Openings", tier: 2 },

  // Tier 3: Medium-High Volatility
  "initial jobless claims": { dir: -1, name: "Initial Jobless Claims", tier: 3 },
  "consumer sentiment": { dir: 1, name: "UoM Consumer Sentiment", tier: 3 }
};

function matchRule(title) {
  const lower = title.toLowerCase();
  for (const [key, rule] of Object.entries(INDICATOR_RULES)) {
    if (lower.includes(key)) return rule;
  }
  return null;
}

async function fetchAndEvaluate() {
  try {
    const now = new Date();
    const fromDate = new Date(now.getTime() - 2 * 60 * 60 * 1000).toISOString();
    const toDate = new Date(now.getTime() + 4 * 60 * 60 * 1000).toISOString();

    const url = `https://economic-calendar.tradingview.com/events?from=${fromDate}&to=${toDate}&countries=US`;
    const resp = await fetch(url, { headers: { "Origin": "https://www.tradingview.com" } });
    if (!resp.ok) return;

    const data = await resp.json();
    const events = data.result || [];

    const storage = await chrome.storage.local.get([SEEN_EVENTS_KEY]);
    const seen = new Set(storage[SEEN_EVENTS_KEY] || []);

    for (const ev of events) {
      if (ev.actual !== null && ev.actual !== undefined && !seen.has(ev.id)) {
        seen.add(ev.id);
        const rule = matchRule(ev.title || "");
        if (rule) {
          const actual = parseFloat(ev.actual);
          const benchmark = ev.forecast !== null ? parseFloat(ev.forecast) : parseFloat(ev.previous);

          if (!isNaN(actual) && !isNaN(benchmark)) {
            const diff = actual - benchmark;
            const usdScore = diff * rule.dir;

            let signal = "NEUTRAL";
            let explanation = "";

            if (usdScore > 0) {
              signal = "SELL"; // Strong USD -> Drop Gold
              explanation = `${rule.name}: Actual (${actual}) beat forecast/prior (${benchmark}) -> Strong USD -> SELL GOLD`;
            } else if (usdScore < 0) {
              signal = "BUY";  // Weak USD -> Rally Gold
              explanation = `${rule.name}: Actual (${actual}) missed forecast/prior (${benchmark}) -> Weak USD -> BUY GOLD`;
            }

            if (signal !== "NEUTRAL") {
              broadcastSignal({
                signal,
                title: rule.name,
                tier: rule.tier,
                actual,
                benchmark,
                explanation,
                time: new Date().toLocaleTimeString()
              });
            }
          }
        }
      }
    }

    await chrome.storage.local.set({ [SEEN_EVENTS_KEY]: Array.from(seen) });
  } catch (err) {
    console.error("[News Sniper Background Error]:", err);
  }
}

function broadcastSignal(payload) {
  chrome.tabs.query({}, (tabs) => {
    for (const tab of tabs) {
      if (tab.id) {
        chrome.tabs.sendMessage(tab.id, { type: "NEWS_SIGNAL", data: payload }).catch(() => {});
      }
    }
  });
}

setInterval(fetchAndEvaluate, 1000);
fetchAndEvaluate();
