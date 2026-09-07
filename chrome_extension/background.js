// Background Service Worker: polls calendar API and dispatches signals to active tabs
const SEEN_EVENTS_KEY = "seen_news_event_ids";

const INDICATOR_RULES = {
  "non farm payrolls": { dir: 1, name: "Nonfarm Payrolls (NFP)" },
  "nonfarm payrolls": { dir: 1, name: "Nonfarm Payrolls (NFP)" },
  "unemployment rate": { dir: -1, name: "Unemployment Rate" },
  "cpi": { dir: 1, name: "Consumer Price Index (CPI)" },
  "core cpi": { dir: 1, name: "Core CPI" },
  "ppi": { dir: 1, name: "Producer Price Index (PPI)" },
  "retail sales": { dir: 1, name: "Retail Sales" },
  "initial jobless claims": { dir: -1, name: "Initial Jobless Claims" }
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
              explanation = `${rule.name}: Actual (${actual}) beat forecast (${benchmark}) -> Strong USD -> SELL GOLD`;
            } else if (usdScore < 0) {
              signal = "BUY";  // Weak USD -> Rally Gold
              explanation = `${rule.name}: Actual (${actual}) missed forecast (${benchmark}) -> Weak USD -> BUY GOLD`;
            }

            if (signal !== "NEUTRAL") {
              broadcastSignal({
                signal,
                title: rule.name,
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

// Poll every 1 second
setInterval(fetchAndEvaluate, 1000);
fetchAndEvaluate();
