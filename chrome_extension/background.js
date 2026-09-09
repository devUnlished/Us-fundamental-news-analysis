// Background Service Worker: robust multi-tab state sync, real-time polling, and 120-day historical archive
// Includes Trade Horizon & Impulse Duration Strategy (Macro Trend vs. 15-Min Scalp Trap)
const SEEN_EVENTS_KEY = "seen_news_event_ids";
const LATEST_SIGNAL_KEY = "latest_triggered_signal";
const UPCOMING_EVENT_KEY = "latest_upcoming_event";
const HISTORY_EVENTS_KEY = "history_news_events";

const INDICATOR_RULES = {
  // Tier 1: Mega Volatility (Macro Trend: 1 - 4 hours hold)
  "non farm payrolls": { dir: 1, name: "Nonfarm Payrolls (NFP)", category: "NFP", tier: 1, unit: "k", stdDev: 35.0, horizon: "MACRO TREND: 1 - 4 Hours", warning: "Explosive breakout expected. Look for structural trend continuation." },
  "nonfarm payrolls": { dir: 1, name: "Nonfarm Payrolls (NFP)", category: "NFP", tier: 1, unit: "k", stdDev: 35.0, horizon: "MACRO TREND: 1 - 4 Hours", warning: "Explosive breakout expected. Look for structural trend continuation." },
  "unemployment rate": { dir: -1, name: "Unemployment Rate", category: "NFP", tier: 1, unit: "%", stdDev: 0.15, horizon: "MACRO TREND: 1 - 4 Hours", warning: "High impact on Fed interest rate outlook." },
  "cpi m/m": { dir: 1, name: "CPI MoM", category: "CPI", tier: 1, unit: "%", stdDev: 0.15, horizon: "MACRO TREND: 2 - 6 Hours", warning: "Multi-hour directional leg. Trailing stop recommended." },
  "cpi y/y": { dir: 1, name: "CPI YoY", category: "CPI", tier: 1, unit: "%", stdDev: 0.2, horizon: "MACRO TREND: 2 - 6 Hours", warning: "Multi-hour directional leg. Trailing stop recommended." },
  "cpi": { dir: 1, name: "Consumer Price Index (CPI)", category: "CPI", tier: 1, unit: "%", stdDev: 0.2, horizon: "MACRO TREND: 2 - 6 Hours", warning: "Multi-hour directional leg. Trailing stop recommended." },
  "core cpi": { dir: 1, name: "Core CPI", category: "CPI", tier: 1, unit: "%", stdDev: 0.15, horizon: "MACRO TREND: 2 - 6 Hours", warning: "Multi-hour directional leg. Trailing stop recommended." },
  "core pce": { dir: 1, name: "Core PCE Price Index", category: "CPI", tier: 1, unit: "%", stdDev: 0.15, horizon: "MACRO TREND: 1 - 3 Hours", warning: "Fed primary inflation gauge. High follow-through." },
  "pce price index": { dir: 1, name: "PCE Price Index", category: "CPI", tier: 2, unit: "%", stdDev: 0.15, horizon: "SWING MOVE: 45 - 90 Mins", warning: "Watch for retest of pre-news highs/lows." },
  "fed interest rate": { dir: 1, name: "Fed Interest Rate Decision", category: "FOMC", tier: 1, unit: "%", stdDev: 0.25, horizon: "MAJOR CYCLE: Full Session Trend", warning: "Massive liquidity. High risk of 2-way volatility into Press Conf." },
  "interest rate decision": { dir: 1, name: "Interest Rate Decision", category: "FOMC", tier: 1, unit: "%", stdDev: 0.25, horizon: "MAJOR CYCLE: Full Session Trend", warning: "Massive liquidity. High risk of 2-way volatility into Press Conf." },
  "fed funds": { dir: 1, name: "Fed Funds Rate", category: "FOMC", tier: 1, unit: "%", stdDev: 0.25, horizon: "MAJOR CYCLE: Full Session Trend", warning: "Watch Powell speech for true directional run." },
  "fomc": { dir: 1, name: "FOMC Rate / Statement", category: "FOMC", tier: 1, unit: "%", stdDev: 0.25, horizon: "MAJOR CYCLE: Full Session Trend", warning: "High risk of 2-way whipsaw before clean trend." },

  // Tier 2: High Volatility (Swing / Quick Trend: 30 - 60 mins)
  "retail sales": { dir: 1, name: "Retail Sales", category: "RETAIL", tier: 2, unit: "%", stdDev: 0.3, horizon: "SWING IMPULSE: 30 - 60 Mins", warning: "Clean initial drive. Lock profits at key 15M structure." },
  "core retail sales": { dir: 1, name: "Core Retail Sales", category: "RETAIL", tier: 2, unit: "%", stdDev: 0.3, horizon: "SWING IMPULSE: 30 - 60 Mins", warning: "Clean initial drive. Lock profits at key 15M structure." },
  "gdp": { dir: 1, name: "Gross Domestic Product (GDP)", category: "GDP", tier: 2, unit: "%", stdDev: 0.4, horizon: "SWING MOVE: 45 - 90 Mins", warning: "Quarterly revisions determine directional follow-through." },
  "ism manufacturing": { dir: 1, name: "ISM Manufacturing PMI", category: "PMI", tier: 2, unit: "pts", stdDev: 1.2, horizon: "SWING MOVE: 30 - 60 Mins", warning: "50-level is the critical macro line. Quick reversal risk." },
  "ism services": { dir: 1, name: "ISM Services PMI", category: "PMI", tier: 2, unit: "pts", stdDev: 1.2, horizon: "SWING MOVE: 30 - 60 Mins", warning: "Major surprise factor in US economy. Watch M15 close." },
  "ppi": { dir: 1, name: "Producer Price Index (PPI)", category: "PPI", tier: 2, unit: "%", stdDev: 0.2, horizon: "SWING IMPULSE: 20 - 45 Mins", warning: "Leading indicator to CPI. Often retests after initial move." },
  "core ppi": { dir: 1, name: "Core PPI", category: "PPI", tier: 2, unit: "%", stdDev: 0.2, horizon: "SWING IMPULSE: 20 - 45 Mins", warning: "Leading indicator to CPI. Often retests after initial move." },
  "jolts": { dir: 1, name: "JOLTs Job Openings", category: "NFP", tier: 2, unit: "M", stdDev: 0.25, horizon: "SWING IMPULSE: 20 - 45 Mins", warning: "Watch for rapid algorithmic scalp reactions." },
  "adp employment": { dir: 1, name: "ADP Employment Change", category: "ADP", tier: 2, unit: "k", stdDev: 30.0, horizon: "SCALP WARNING: 10 - 15 Mins Quick Impulse", warning: "⚠️ HIGH REVERSAL RISK: Fast initial 15M spike then retraces. Take profit fast!" },

  // Tier 3: Scalp-Only (10 - 15 minutes quick spike)
  "initial jobless claims": { dir: -1, name: "Initial Jobless Claims", category: "CLAIMS", tier: 3, unit: "k", stdDev: 12.0, horizon: "SCALP ONLY: 10 - 20 Mins", warning: "⚠️ Quick spike only (25-45 pips). Often retests pre-news level." },
  "continuing jobless claims": { dir: -1, name: "Continuing Jobless Claims", category: "CLAIMS", tier: 3, unit: "k", stdDev: 25.0, horizon: "SCALP ONLY: 10 - 20 Mins", warning: "⚠️ Quick impulse. Do not hold through multiple candles." },
  "consumer sentiment": { dir: 1, name: "UoM Consumer Sentiment", category: "OTHER", tier: 3, unit: "pts", stdDev: 2.0, horizon: "SCALP ONLY: 15 Mins", warning: "⚠️ Fast 15M reaction. Target 20-35 pips maximum." },
  "inflation expectations": { dir: 1, name: "Consumer Inflation Expectations", category: "CPI", tier: 3, unit: "%", stdDev: 0.2, horizon: "SCALP ONLY: 15 Mins", warning: "⚠️ Fast 15M reaction. Target 20-35 pips maximum." },
  "business optimism": { dir: 1, name: "NFIB Business Optimism", category: "OTHER", tier: 3, unit: "pts", stdDev: 1.5, horizon: "SCALP ONLY: 15 Mins", warning: "Low institutional trend follow-through." },
  "consumer credit": { dir: 1, name: "Consumer Credit Change", category: "OTHER", tier: 3, unit: "B", stdDev: 3.0, horizon: "SCALP ONLY: 10 Mins", warning: "Minor late-day volume. Quick scalp only." }
};

function matchRule(title) {
  const lower = title.toLowerCase();
  if (lower.includes("productivity") || lower.includes("annual revision")) return null;
  for (const [key, rule] of Object.entries(INDICATOR_RULES)) {
    if (lower.includes(key)) return rule;
  }
  return null;
}

function computeStrength(diff, impactDir, rule) {
  const usdScore = diff * impactDir;
  const absDiff = Math.abs(diff);
  const ratio = rule.stdDev ? absDiff / rule.stdDev : 1.0;

  let signalAction = "NEUTRAL";
  let convictionLevel = "NEUTRAL";
  let expectedPips = "15 - 30 pips";
  let badgeColor = "#64748b";

  if (usdScore > 0) {
    if (ratio >= 2.0) {
      signalAction = "SELL VERY HARD";
      convictionLevel = "EXTREME SURPRISE";
      expectedPips = "180 - 350+ pips";
      badgeColor = "#991b1b";
    } else if (ratio >= 1.0) {
      signalAction = "SELL HARD";
      convictionLevel = "HIGH CONVICTION";
      expectedPips = "90 - 180 pips";
      badgeColor = "#dc2626";
    } else {
      signalAction = "SELL MODERATE";
      convictionLevel = "MODERATE MOVE";
      expectedPips = "40 - 80 pips";
      badgeColor = "#f87171";
    }
  } else if (usdScore < 0) {
    if (ratio >= 2.0) {
      signalAction = "BUY VERY HARD";
      convictionLevel = "EXTREME SURPRISE";
      expectedPips = "180 - 350+ pips";
      badgeColor = "#065f46";
    } else if (ratio >= 1.0) {
      signalAction = "BUY HARD";
      convictionLevel = "HIGH CONVICTION";
      expectedPips = "90 - 180 pips";
      badgeColor = "#059669";
    } else {
      signalAction = "BUY MODERATE";
      convictionLevel = "MODERATE MOVE";
      expectedPips = "40 - 80 pips";
      badgeColor = "#34d399";
    }
  }

  return { signalAction, convictionLevel, expectedPips, badgeColor, ratio };
}

let latestUpcomingEvent = null;
let lastTriggeredSignal = null;
let historicalList = [];

async function fetchAndEvaluate() {
  try {
    const now = new Date();
    // 130 days back (~4.5 months) to 10 days ahead
    const fromDate = new Date(now.getTime() - 130 * 24 * 60 * 60 * 1000).toISOString();
    const toDate = new Date(now.getTime() + 10 * 24 * 60 * 60 * 1000).toISOString();

    const url = `https://economic-calendar.tradingview.com/events?from=${fromDate}&to=${toDate}&countries=US`;
    const resp = await fetch(url, { headers: { "Origin": "https://www.tradingview.com" } });
    if (!resp.ok) return;

    const data = await resp.json();
    const events = data.result || [];

    const storage = await chrome.storage.local.get([SEEN_EVENTS_KEY, LATEST_SIGNAL_KEY]);
    const seen = new Set(storage[SEEN_EVENTS_KEY] || []);

    let closestUpcoming = null;
    let closestTimeDiff = Infinity;
    let newestReleasedSignal = null;
    let newestReleaseTime = 0;
    const historyCollector = [];

    for (const ev of events) {
      const rule = matchRule(ev.title || "");
      if (!rule) continue;

      const evTime = new Date(ev.date).getTime();
      const hasActual = ev.actual !== null && ev.actual !== undefined;

      // 1. Process Released Actual data (Live & 4-Month Historical Archive)
      if (hasActual) {
        const actual = parseFloat(ev.actual);
        const hasForecast = ev.forecast !== null && ev.forecast !== undefined;
        const benchmark = hasForecast ? parseFloat(ev.forecast) : parseFloat(ev.previous);
        const previous = ev.previous !== null && ev.previous !== undefined ? parseFloat(ev.previous) : null;
        const benchmarkSource = hasForecast ? "Forecast" : "Prior (No Forecast)";

        if (!isNaN(actual) && !isNaN(benchmark)) {
          const diff = actual - benchmark;
          const strength = computeStrength(diff, rule.dir, rule);

          const signalPayload = {
            id: ev.id,
            signal: strength.signalAction,
            conviction: strength.convictionLevel,
            expectedPips: strength.expectedPips,
            badgeColor: strength.badgeColor,
            ratio: strength.ratio.toFixed(1),
            title: ev.title || rule.name,
            ruleName: rule.name,
            category: rule.category,
            unit: rule.unit,
            tier: rule.tier,
            horizon: rule.horizon,
            strategyWarning: rule.warning,
            actual,
            forecast: hasForecast ? benchmark : "None",
            previous,
            benchmarkSource,
            diff: (diff > 0 ? "+" : "") + diff.toFixed(2),
            timestamp: evTime,
            date: ev.date,
            time: new Date(ev.date).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })
          };

          historyCollector.push(signalPayload);

          if (evTime > newestReleaseTime) {
            newestReleaseTime = evTime;
            newestReleasedSignal = signalPayload;
          }

          if (!seen.has(ev.id)) {
            seen.add(ev.id);
            broadcastSignal({
              type: "NEWS_SIGNAL",
              data: signalPayload
            });
            await chrome.storage.local.set({ [LATEST_SIGNAL_KEY]: signalPayload });
          }
        }
      }

      // 2. Track upcoming events where actual is not yet released
      if (!hasActual) {
        const diffToNow = evTime - now.getTime();
        if (diffToNow >= -45 * 60 * 1000) {
          const sortMetric = Math.abs(diffToNow);
          if (sortMetric < closestTimeDiff) {
            closestTimeDiff = sortMetric;
            const hasFc = ev.forecast !== null && ev.forecast !== undefined;
            closestUpcoming = {
              id: ev.id,
              title: rule.name,
              category: rule.category,
              date: ev.date,
              forecast: hasFc ? ev.forecast : "N/A (Uses Prior)",
              hasForecast: hasFc,
              previous: ev.previous !== null && ev.previous !== undefined ? ev.previous : "--",
              unit: rule.unit,
              tier: rule.tier,
              horizon: rule.horizon,
              strategyWarning: rule.warning,
              isDelayed: diffToNow < 0,
              delayedMinutes: diffToNow < 0 ? Math.floor(Math.abs(diffToNow) / 60000) : 0,
              timeDiffMs: diffToNow
            };
          }
        }
      }
    }

    // Sort history chronologically newest first
    historyCollector.sort((a, b) => b.timestamp - a.timestamp);
    historicalList = historyCollector.slice(0, 100);

    // Save state
    await chrome.storage.local.set({
      [HISTORY_EVENTS_KEY]: historicalList,
      [SEEN_EVENTS_KEY]: Array.from(seen)
    });

    if (closestUpcoming) {
      latestUpcomingEvent = closestUpcoming;
      await chrome.storage.local.set({ [UPCOMING_EVENT_KEY]: closestUpcoming });
      broadcastSignal({
        type: "UPCOMING_EVENT",
        data: closestUpcoming
      });
    }

    if (newestReleasedSignal) {
      lastTriggeredSignal = newestReleasedSignal;
      await chrome.storage.local.set({ [LATEST_SIGNAL_KEY]: newestReleasedSignal });
    }

  } catch (err) {
    console.error("[News Sniper Background Error]:", err);
  }
}

function broadcastSignal(payload) {
  chrome.tabs.query({}, (tabs) => {
    for (const tab of tabs) {
      if (tab.id) {
        chrome.tabs.sendMessage(tab.id, payload).catch(() => {});
      }
    }
  });
}

// Continuous active 1s polling
setInterval(fetchAndEvaluate, 1000);
fetchAndEvaluate();

// Respond immediately with full state when any tab loads
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type === "GET_STATE") {
    chrome.storage.local.get([UPCOMING_EVENT_KEY, LATEST_SIGNAL_KEY, HISTORY_EVENTS_KEY], (items) => {
      sendResponse({
        upcoming: items[UPCOMING_EVENT_KEY] || latestUpcomingEvent,
        lastSignal: items[LATEST_SIGNAL_KEY] || lastTriggeredSignal,
        history: items[HISTORY_EVENTS_KEY] || historicalList
      });
    });
    return true;
  }
});
