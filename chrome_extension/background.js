// Background Service Worker: robust multi-tab state sync, real-time polling, and 120-day historical archive
// Includes Trade Horizon & Impulse Duration Strategy (Macro Trend vs. 15-Min Scalp Trap)
const SEEN_EVENTS_KEY = "seen_news_event_ids";
const LATEST_SIGNAL_KEY = "latest_triggered_signal";
const UPCOMING_EVENT_KEY = "latest_upcoming_event";
const HISTORY_EVENTS_KEY = "history_news_events";

const INDICATOR_RULES = {
  // THE BIG THREE ONLY: NFP, CPI, FOMC
  // Tier 1: Nonfarm Payrolls (NFP)
  "non farm payrolls": { dir: 1, name: "Nonfarm Payrolls (NFP)", category: "NFP", tier: 1, unit: "k", stdDev: 45.0, p75: 100.0, horizon: "MACRO TREND: 1 - 4 Hours", warning: "Explosive breakout expected. Look for structural trend continuation." },
  "nonfarm payrolls": { dir: 1, name: "Nonfarm Payrolls (NFP)", category: "NFP", tier: 1, unit: "k", stdDev: 45.0, p75: 100.0, horizon: "MACRO TREND: 1 - 4 Hours", warning: "Explosive breakout expected. Look for structural trend continuation." },
  "unemployment rate": { dir: -1, name: "Unemployment Rate", category: "NFP", tier: 1, unit: "%", stdDev: 0.08, p75: 0.15, horizon: "MACRO TREND: 1 - 4 Hours", warning: "High impact on Fed interest rate outlook." },

  // Tier 1: Consumer Price Index (CPI)
  "cpi m/m": { dir: 1, name: "CPI MoM", category: "CPI", tier: 1, unit: "%", stdDev: 0.12, p75: 0.25, horizon: "MACRO TREND: 2 - 6 Hours", warning: "Multi-hour directional leg. Trailing stop recommended." },
  "cpi y/y": { dir: 1, name: "CPI YoY", category: "CPI", tier: 1, unit: "%", stdDev: 0.18, p75: 0.30, horizon: "MACRO TREND: 2 - 6 Hours", warning: "Multi-hour directional leg. Trailing stop recommended." },
  "cpi": { dir: 1, name: "Consumer Price Index (CPI)", category: "CPI", tier: 1, unit: "%", stdDev: 0.20, p75: 0.35, horizon: "MACRO TREND: 2 - 6 Hours", warning: "Multi-hour directional leg. Trailing stop recommended." },
  "core cpi": { dir: 1, name: "Core CPI", category: "CPI", tier: 1, unit: "%", stdDev: 0.12, p75: 0.25, horizon: "MACRO TREND: 2 - 6 Hours", warning: "Multi-hour directional leg. Trailing stop recommended." },

  // Tier 1: Federal Open Market Committee (FOMC / Fed Funds Rate Decision)
  "fed interest rate": { dir: 1, name: "Fed Interest Rate Decision", category: "FOMC", tier: 1, unit: "%", stdDev: 0.10, p75: 0.25, horizon: "MAJOR CYCLE: Full Session Trend", warning: "Massive liquidity. High risk of 2-way volatility into Press Conf." },
  "interest rate decision": { dir: 1, name: "Fed Interest Rate Decision", category: "FOMC", tier: 1, unit: "%", stdDev: 0.10, p75: 0.25, horizon: "MAJOR CYCLE: Full Session Trend", warning: "Massive liquidity. High risk of 2-way volatility into Press Conf." },
  "fed funds": { dir: 1, name: "Fed Funds Rate Decision", category: "FOMC", tier: 1, unit: "%", stdDev: 0.10, p75: 0.25, horizon: "MAJOR CYCLE: Full Session Trend", warning: "Watch Powell speech for true directional run." },
  "fomc": { dir: 1, name: "FOMC Rate Decision", category: "FOMC", tier: 1, unit: "%", stdDev: 0.10, p75: 0.25, horizon: "MAJOR CYCLE: Full Session Trend", warning: "High risk of 2-way whipsaw before clean trend." }
};

function matchRule(title) {
  const lower = title.toLowerCase();
  if (lower.includes("productivity") || lower.includes("annual revision") || lower.includes("u-6")) return null;
  // Sort keys by descending length so specific terms ("core cpi") match before general ones ("cpi")
  const sortedKeys = Object.keys(INDICATOR_RULES).sort((a, b) => b.length - a.length);
  for (const key of sortedKeys) {
    if (lower.includes(key)) return INDICATOR_RULES[key];
  }
  return null;
}

// Strict filter for history view: The Big Three Only (NFP, CPI, FOMC)
function isFocusHistoryEvent(title, category) {
  const low = (title || "").toLowerCase().trim();
  
  // Explicit exclusions for noisy secondary metrics
  const noisySubstrings = [
    "u-6", "annual revision", "productivity", "weekly",
    "government payrolls", "manufacturing payrolls", "private",
    "projection", "minutes", "s.a", "qoq", "2nd est", "adv", "final"
  ];
  for (const noisy of noisySubstrings) {
    if (low.includes(noisy)) return false;
  }

  // 1. Nonfarm Payrolls (Core headline NFP)
  if (category === "NFP") {
    return low.includes("non farm payrolls") || low.includes("nonfarm payrolls");
  }

  // 2. CPI (Primary inflation gauges)
  if (category === "CPI") {
    return low === "cpi" || low.includes("core cpi") || low.includes("cpi y/y") || low.includes("cpi m/m");
  }

  // 3. FOMC / Fed Interest Rate Decisions
  if (category === "FOMC") {
    return low.includes("interest rate") || low.includes("fed funds") || low.includes("fomc");
  }

  return false;
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

  // Institutional Playbook Guidance:
  // 1. Hold vs Scalp based on statistical surprise deviation ratio
  // 2. Liquidity Sweep Targets & Take Profit zones (e.g. key psychological round numbers)
  let surpriseGuidance = "NORMAL MOVE";
  let sweepGuidance = "Take partial profit at next major round number";

  if (ratio >= 2.0) {
    surpriseGuidance = "🔥 EXTREME BLOWOUT: Heavy institutional re-pricing. Trend continuation favored. Trailing stop recommended.";
    sweepGuidance = "🎯 SWEEP TARGET: Watch for multi-leg run (150-300+ pips). Lock 50% at first major swing extreme.";
  } else if (ratio >= 1.0) {
    surpriseGuidance = "⚡ SOLID SURPRISE: Trend continuation likely. Protect breakeven after 40-50 pips.";
    sweepGuidance = "🎯 SWEEP TARGET: Major liquidity zone / nearest 50-pip round number. Take 70% off at retest.";
  } else {
    surpriseGuidance = "⚠️ MODEST SURPRISE (SLIGHT DEVIATION): High reversal risk! Scalp impulse only, do NOT marry position.";
    sweepGuidance = "🎯 SWEEP & REVERSE TARGET: Watch for V-shape rebound at key round number ($20-$40 move). Lock 80% fast!";
  }

  return { signalAction, convictionLevel, expectedPips, badgeColor, ratio, surpriseGuidance, sweepGuidance };
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
            surpriseGuidance: strength.surpriseGuidance,
            sweepGuidance: strength.sweepGuidance,
            actual,
            forecast: hasForecast ? benchmark : "None",
            previous,
            benchmarkSource,
            diff: (diff > 0 ? "+" : "") + diff.toFixed(2),
            timestamp: evTime,
            date: ev.date,
            time: new Date(ev.date).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })
          };

          // Strict Focus Filter for History: only primary high-impact market drivers
          // (Nonfarm Payrolls, CPI, Core PCE Price Index, Fed Interest Rate/FOMC, ADP Employment Change)
          // Excludes U-6, annual revisions, quarterly projections, minor secondaries.
          const isFocusHistorical = isFocusHistoryEvent(ev.title || rule.name, rule.category);
          if (isFocusHistorical) {
            historyCollector.push(signalPayload);
          }

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

    // 3. Trade Horizon Active Window Engine:
    // When a news signal releases, keep it displayed on the main card for the duration of its
    // suggested trade horizon (or minimum 20 minutes) so the trader has time to execute and manage the move.
    // Do NOT prematurely overwrite it with the next upcoming event.
    let isSignalActiveInHorizon = false;
    if (newestReleasedSignal) {
      lastTriggeredSignal = newestReleasedSignal;
      await chrome.storage.local.set({ [LATEST_SIGNAL_KEY]: newestReleasedSignal });

      // Calculate expiry based on rule.horizon (e.g. 15m, 30m, 45m, 1-4h)
      let activeHorizonMs = 30 * 60 * 1000; // default 30 mins
      const hor = (newestReleasedSignal.horizon || "").toUpperCase();
      if (hor.includes("10 - 15") || hor.includes("15 MIN")) {
        activeHorizonMs = 15 * 60 * 1000;
      } else if (hor.includes("20 - 45") || hor.includes("30 - 60")) {
        activeHorizonMs = 45 * 60 * 1000;
      } else if (hor.includes("1 - 4") || hor.includes("2 - 6") || hor.includes("MAJOR CYCLE")) {
        activeHorizonMs = 90 * 60 * 1000; // 90 minutes hold for Tier 1 macro trends
      }

      const elapsedSinceRelease = now.getTime() - newestReleasedSignal.timestamp;
      if (elapsedSinceRelease >= 0 && elapsedSinceRelease < activeHorizonMs) {
        isSignalActiveInHorizon = true;
      }
    }

    if (closestUpcoming) {
      latestUpcomingEvent = closestUpcoming;
      await chrome.storage.local.set({ [UPCOMING_EVENT_KEY]: closestUpcoming });
      // Only broadcast upcoming event if no active signal is currently within its trading horizon window
      if (!isSignalActiveInHorizon) {
        broadcastSignal({
          type: "UPCOMING_EVENT",
          data: closestUpcoming
        });
      }
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
