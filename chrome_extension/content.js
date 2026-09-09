// Content script: High-detail institutional terminal HUD overlay for TradingView, XM & FBS
// Multi-month historical archive (June, July, August, September) with pagination, limits, and surprise delta metrics
(function() {
  console.log("[News Sniper Terminal] Connected to Live Institutional Economic Feed.");

  function formatTime24WithAmPm(dateObj) {
    const hours = dateObj.getHours();
    const minutes = String(dateObj.getMinutes()).padStart(2, "0");
    const seconds = String(dateObj.getSeconds()).padStart(2, "0");
    const ampm = hours >= 12 ? "PM" : "AM";
    const hours24 = String(hours).padStart(2, "0");
    return `${hours24}:${minutes}:${seconds} ${ampm}`;
  }

  function formatShortDateWithTime(dateObj) {
    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    const month = months[dateObj.getMonth()];
    const day = dateObj.getDate();
    const hours = dateObj.getHours();
    const minutes = String(dateObj.getMinutes()).padStart(2, "0");
    const ampm = hours >= 12 ? "PM" : "AM";
    const hours24 = String(hours).padStart(2, "0");
    return `${month} ${day}, ${hours24}:${minutes} ${ampm}`;
  }

  let hud = document.getElementById("fn-sniper-hud");
  if (!hud) {
    hud = document.createElement("div");
    hud.id = "fn-sniper-hud";
    hud.style.cssText = `
      position: fixed;
      top: 24px;
      right: 24px;
      z-index: 2147483647;
      width: 410px;
      min-width: 300px;
      max-width: 720px;
      background: #0b0e14;
      border: 1px solid #1e293b;
      border-radius: 8px;
      box-shadow: 0 14px 40px rgba(0, 0, 0, 0.85), 0 0 0 1px rgba(255, 255, 255, 0.05);
      color: #e2e8f0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", sans-serif;
      resize: both;
      overflow: hidden !important;
      user-select: none;
      display: flex;
      flex-direction: column;
      box-sizing: border-box;
    `;

    hud.innerHTML = `
      <!-- Draggable Header -->
      <div id="fn-drag-handle" style="background: #141a24; padding: 7px 12px; border-bottom: 1px solid #1e293b; display: flex; justify-content: space-between; align-items: center; cursor: move; flex-shrink: 0;">
        <div style="display: flex; align-items: center; gap: 6px;">
          <span style="width: 8px; height: 8px; border-radius: 50%; background: #22c55e; display: inline-block; box-shadow: 0 0 8px #22c55e;"></span>
          <span style="font-size: 11px; font-weight: 700; letter-spacing: 0.8px; color: #f8fafc;">XAUUSD NEWS TERMINAL</span>
        </div>
        <div style="display: flex; align-items: center; gap: 8px;">
          <span id="fn-time-display" style="font-size: 10px; color: #94a3b8; font-family: monospace;">--:--:-- -- GMT+2</span>
          <span style="font-size: 10px; color: #64748b; cursor: move;" title="Drag to Move">✥</span>
        </div>
      </div>

      <!-- Main Body -->
      <div style="padding: 8px 12px; display: flex; flex-direction: column; gap: 6px; flex: 1; overflow: hidden !important; box-sizing: border-box;">
        <!-- Main Action Banner -->
        <div id="fn-badge" style="background: #1e293b; border-radius: 6px; padding: 10px 12px; text-align: center; border: 1px solid rgba(255,255,255,0.06); transition: all 0.25s ease; flex-shrink: 0;">
          <div id="fn-conviction-tag" style="font-size: clamp(8px, 2vw, 10px); font-weight: 700; letter-spacing: 1px; color: #38bdf8; margin-bottom: 2px;">COUNTDOWN ACTIVE</div>
          <div id="fn-action-text" style="font-size: clamp(13px, 4vw, 18px); font-weight: 900; letter-spacing: 0.5px; color: #f1f5f9; line-height: 1.2;">UPCOMING EVENT LOADED</div>
          <div id="fn-volatility-tag" style="font-size: clamp(8px, 1.8vw, 9.5px); color: #94a3b8; margin-top: 2px;">Tracking pre-release forecast & prior</div>
        </div>

        <!-- Metrics Matrix: ACTUAL | FORECAST | PRIOR -->
        <div style="flex-shrink: 0;">
          <div style="display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 3px;">
            <div id="fn-event-title" style="font-size: clamp(8.5px, 2.2vw, 10.5px); font-weight: 700; color: #38bdf8; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 65%;">Querying US release...</div>
            <div id="fn-event-date" style="font-size: 9px; font-weight: 600; color: #f59e0b; font-family: monospace;">Date: --</div>
          </div>
          <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 5px; background: #0f141d; padding: 6px 8px; border-radius: 6px; border: 1px solid #1e293b;">
            <!-- Column 1: ACTUAL -->
            <div>
              <div style="font-size: 8px; color: #64748b; font-weight: 700; text-transform: uppercase;">Actual</div>
              <div id="fn-actual-val" style="font-size: clamp(10px, 2.8vw, 13px); font-weight: 800; color: #94a3b8; font-family: monospace;">AWAITING</div>
            </div>
            <!-- Column 2: FORECAST -->
            <div>
              <div style="font-size: 8px; color: #64748b; font-weight: 700; text-transform: uppercase;">Forecast</div>
              <div id="fn-est-val" style="font-size: clamp(9px, 2.5vw, 13px); font-weight: 800; color: #38bdf8; font-family: monospace;">--</div>
            </div>
            <!-- Column 3: PRIOR -->
            <div>
              <div style="font-size: 8px; color: #64748b; font-weight: 700; text-transform: uppercase;">Prior</div>
              <div id="fn-prior-val" style="font-size: clamp(10px, 2.8vw, 13px); font-weight: 800; color: #f8fafc; font-family: monospace;">--</div>
            </div>
          </div>
          <!-- Surprise Delta Strip -->
          <div id="fn-delta-strip" style="margin-top: 5px; background: #0f141d; padding: 5px 8px; border-radius: 4px; border: 1px solid #1e293b; display: flex; justify-content: space-between; align-items: center;">
            <span style="font-size: 8.5px; color: #64748b; font-weight: 600; text-transform: uppercase;">Surprise Delta:</span>
            <span id="fn-diff-val" style="font-size: 10.5px; font-weight: 800; color: #94a3b8; font-family: monospace;">PENDING RELEASE</span>
          </div>
        </div>

        <!-- Historical News Archive with Filter Tabs & View Limits -->
        <div style="background: #0d1117; border: 1px solid #1e293b; border-radius: 6px; padding: 6px 8px; flex: 1; display: flex; flex-direction: column; overflow: hidden; min-height: 120px;">
          <!-- Filter Tabs -->
          <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px; border-bottom: 1px solid #1c2433; padding-bottom: 4px; flex-wrap: wrap; gap: 4px;">
            <span style="font-size: 8.5px; font-weight: 800; color: #94a3b8; letter-spacing: 0.5px;">HISTORY (4 MONTHS):</span>
            <div id="fn-history-filters" style="display: flex; gap: 3px;">
              <button data-cat="ALL" style="background: #2563eb; color: #ffffff; border: none; border-radius: 3px; font-size: 8px; padding: 2px 5px; cursor: pointer; font-weight: 700;">ALL</button>
              <button data-cat="NFP" style="background: #1e293b; color: #94a3b8; border: none; border-radius: 3px; font-size: 8px; padding: 2px 5px; cursor: pointer;">NFP</button>
              <button data-cat="CPI" style="background: #1e293b; color: #94a3b8; border: none; border-radius: 3px; font-size: 8px; padding: 2px 5px; cursor: pointer;">CPI</button>
              <button data-cat="ADP" style="background: #1e293b; color: #94a3b8; border: none; border-radius: 3px; font-size: 8px; padding: 2px 5px; cursor: pointer;">ADP</button>
              <button data-cat="PPI" style="background: #1e293b; color: #94a3b8; border: none; border-radius: 3px; font-size: 8px; padding: 2px 5px; cursor: pointer;">PPI</button>
            </div>
          </div>
          <!-- History List Scroll Container -->
          <div id="fn-history-container" style="flex: 1; overflow-y: scroll; display: flex; flex-direction: column; gap: 4px; padding-right: 4px; max-height: 140px;">
            <div style="font-size: 9px; color: #64748b; text-align: center; padding: 6px;">Loading multi-month releases...</div>
          </div>
          <!-- View More / View Limit Footer -->
          <div style="display: flex; justify-content: space-between; align-items: center; border-top: 1px solid #1c2433; padding-top: 4px; margin-top: 4px;">
            <span id="fn-history-count" style="font-size: 8px; color: #64748b; font-family: monospace;">Showing 5 releases</span>
            <button id="fn-view-more-btn" style="background: #1e293b; color: #38bdf8; border: 1px solid #334155; border-radius: 3px; font-size: 8px; padding: 2px 8px; cursor: pointer; font-weight: 700;">
              View More (+5)
            </button>
          </div>
        </div>

        <!-- Live Status Footer -->
        <div style="border-top: 1px solid #18202f; padding-top: 4px; display: flex; justify-content: space-between; align-items: center; flex-shrink: 0;">
          <span id="fn-feed-status" style="font-size: 8px; color: #64748b; font-weight: 500;">Feed: Institutional 1s Live Stream</span>
          <span id="fn-pulse" style="font-size: 8.5px; color: #22c55e; font-weight: 700;">● Active Stream</span>
        </div>
      </div>
    `;
    document.body.appendChild(hud);

    // Make HUD Draggable
    const dragHandle = document.getElementById("fn-drag-handle");
    let isDragging = false;
    let startX = 0, startY = 0;
    let initialLeft = 0, initialTop = 0;

    dragHandle.addEventListener("mousedown", (e) => {
      isDragging = true;
      startX = e.clientX;
      startY = e.clientY;

      const rect = hud.getBoundingClientRect();
      initialLeft = rect.left;
      initialTop = rect.top;

      hud.style.right = "auto";
      hud.style.left = initialLeft + "px";
      hud.style.top = initialTop + "px";

      document.addEventListener("mousemove", onMouseMove);
      document.addEventListener("mouseup", onMouseUp);
      e.preventDefault();
    });

    function onMouseMove(e) {
      if (!isDragging) return;
      const dx = e.clientX - startX;
      const dy = e.clientY - startY;
      hud.style.left = Math.max(10, Math.min(window.innerWidth - hud.offsetWidth - 10, initialLeft + dx)) + "px";
      hud.style.top = Math.max(10, Math.min(window.innerHeight - hud.offsetHeight - 10, initialTop + dy)) + "px";
    }

    function onMouseUp() {
      isDragging = false;
      document.removeEventListener("mousemove", onMouseMove);
      document.removeEventListener("mouseup", onMouseUp);
    }

    // Audio Engine
    function playAudio(isBuy, isVeryHard) {
      try {
        const ctx = new (window.AudioContext || window.webkitAudioContext)();
        const baseFreq = isBuy ? (isVeryHard ? 980 : 800) : (isVeryHard ? 340 : 440);
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.type = isVeryHard ? "sawtooth" : "sine";
        osc.frequency.setValueAtTime(baseFreq, ctx.currentTime);
        if (isBuy) {
          osc.frequency.exponentialRampToValueAtTime(baseFreq * 1.35, ctx.currentTime + 0.3);
        } else {
          osc.frequency.exponentialRampToValueAtTime(baseFreq * 0.75, ctx.currentTime + 0.35);
        }
        gain.gain.setValueAtTime(0.35, ctx.currentTime);
        gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.55);
        osc.start();
        osc.stop(ctx.currentTime + 0.55);
      } catch(e) {}
    }

    // History Pagination, Limit & Render Engine
    let cachedHistory = [];
    let currentFilter = "ALL";
    let viewLimit = 5; // Default view limit

    function renderHistoryList() {
      const container = document.getElementById("fn-history-container");
      const countEl = document.getElementById("fn-history-count");
      const viewMoreBtn = document.getElementById("fn-view-more-btn");
      if (!container) return;

      const filtered = cachedHistory.filter(item => {
        if (currentFilter === "ALL") return true;
        return item.category === currentFilter;
      });

      const totalFound = filtered.length;
      const displayItems = filtered.slice(0, viewLimit);

      if (countEl) {
        countEl.innerText = `Showing ${displayItems.length} of ${totalFound} releases`;
      }

      if (viewMoreBtn) {
        if (viewLimit >= totalFound) {
          viewMoreBtn.innerText = "Show Less (5)";
        } else {
          viewMoreBtn.innerText = `View More (+5)`;
        }
      }

      if (displayItems.length === 0) {
        container.innerHTML = `<div style="font-size: 8.5px; color: #64748b; text-align: center; padding: 10px;">No ${currentFilter} releases found in past 4 months</div>`;
        return;
      }

      container.innerHTML = displayItems.map(item => {
        const isBuy = item.signal && item.signal.includes("BUY");
        const sigColor = isBuy ? "#4ade80" : "#f87171";
        const diffPrefix = item.diff && !item.diff.startsWith("+") && !item.diff.startsWith("-") ? "+" : "";
        const evDate = new Date(item.date);
        const gmt2Date = new Date(evDate.getTime() + (2 * 60 + evDate.getTimezoneOffset()) * 60000);
        const dateStr = formatShortDateWithTime(gmt2Date);

        return `
          <div style="background: #141a24; padding: 5px 7px; border-radius: 4px; display: flex; justify-content: space-between; align-items: center; border-left: 3px solid ${sigColor};">
            <div style="overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 44%;">
              <div style="font-size: 8.5px; font-weight: 700; color: #f1f5f9; overflow: hidden; text-overflow: ellipsis;" title="${item.title}">${item.title}</div>
              <div style="font-size: 7.5px; color: #94a3b8; font-family: monospace;">${dateStr}</div>
            </div>
            <div style="font-size: 8px; font-family: monospace; display: flex; gap: 5px; align-items: center; flex-shrink: 0;">
              <span style="color: #ffffff; font-weight: 700;" title="Actual">Act: ${item.actual}${item.unit || ''}</span>
              <span style="color: #38bdf8;" title="Forecast">Est: ${item.forecast}${item.unit || ''}</span>
              <span style="color: #94a3b8;" title="Prior">Pr: ${item.previous}${item.unit || ''}</span>
              <span style="color: ${sigColor}; font-weight: 800; background: rgba(255,255,255,0.06); padding: 1px 4px; border-radius: 3px;" title="Surprise Difference">
                Δ: ${diffPrefix}${item.diff}
              </span>
            </div>
          </div>
        `;
      }).join("");
    }

    // View More / Show Less Click Listener
    const viewMoreBtn = document.getElementById("fn-view-more-btn");
    if (viewMoreBtn) {
      viewMoreBtn.addEventListener("click", () => {
        const filtered = cachedHistory.filter(item => currentFilter === "ALL" || item.category === currentFilter);
        if (viewLimit >= filtered.length) {
          viewLimit = 5; // Reset back to default 5
        } else {
          viewLimit += 5; // Expand by 5
        }
        renderHistoryList();
      });
    }

    // Filter Buttons Wiring
    const filterButtons = document.querySelectorAll("#fn-history-filters button");
    filterButtons.forEach(btn => {
      btn.addEventListener("click", () => {
        filterButtons.forEach(b => {
          b.style.background = "#1e293b";
          b.style.color = "#94a3b8";
          b.style.fontWeight = "normal";
        });
        btn.style.background = "#2563eb";
        btn.style.color = "#ffffff";
        btn.style.fontWeight = "bold";
        currentFilter = btn.getAttribute("data-cat");
        viewLimit = 5; // Reset limit when switching categories
        renderHistoryList();
      });
    });

    // Display Upcoming Pre-Release Data (Forecast & Prior + Date)
    function renderUpcoming(ev) {
      const conviction = document.getElementById("fn-conviction-tag");
      const action = document.getElementById("fn-action-text");
      const volTag = document.getElementById("fn-volatility-tag");
      const title = document.getElementById("fn-event-title");
      const dateEl = document.getElementById("fn-event-date");
      const actualVal = document.getElementById("fn-actual-val");
      const estVal = document.getElementById("fn-est-val");
      const priorVal = document.getElementById("fn-prior-val");
      const diffVal = document.getElementById("fn-diff-val");

      const evDate = new Date(ev.date);
      const gmt2Date = new Date(evDate.getTime() + (2 * 60 + evDate.getTimezoneOffset()) * 60000);
      const fullDateStr = formatShortDateWithTime(gmt2Date) + " GMT+2";

      action.innerText = ev.title;
      dateEl.innerText = fullDateStr;

      if (ev.isDelayed) {
        conviction.innerText = "AWAITING SOURCE RELEASE (DELAYED)";
        conviction.style.color = "#f59e0b";
        volTag.innerText = `Scheduled ${fullDateStr} • Agency has not dropped actual yet (${ev.delayedMinutes}m overdue)`;
        diffVal.innerText = "WAITING FOR SOURCE";
        diffVal.style.color = "#f59e0b";
      } else {
        conviction.innerText = "UPCOMING RELEASE";
        conviction.style.color = "#38bdf8";
        const hasForecast = ev.hasForecast !== false && ev.forecast !== "N/A" && ev.forecast !== "N/A (Uses Prior)";
        if (hasForecast) {
          volTag.innerText = `Releasing: ${fullDateStr} • Consensus vs Prior loaded`;
        } else {
          volTag.innerText = `Releasing: ${fullDateStr} • No Wall St. forecast, baseline = Prior`;
        }
        diffVal.innerText = "PENDING RELEASE";
        diffVal.style.color = "#64748b";
      }

      const hasForecast = ev.hasForecast !== false && ev.forecast !== "N/A" && ev.forecast !== "N/A (Uses Prior)";
      if (hasForecast) {
        estVal.innerText = `${ev.forecast}${ev.unit || ''}`;
        estVal.style.color = "#38bdf8";
      } else {
        estVal.innerText = "None (vs Prior)";
        estVal.style.color = "#64748b";
      }

      title.innerText = ev.title;
      actualVal.innerText = "AWAITING";
      actualVal.style.color = "#94a3b8";

      priorVal.innerText = `${ev.previous}${ev.unit || ''}`;
    }

    // Render Triggered Signal When Actual Drops
    window.renderSniperSignal = function(data) {
      const badge = document.getElementById("fn-badge");
      const conviction = document.getElementById("fn-conviction-tag");
      const action = document.getElementById("fn-action-text");
      const volTag = document.getElementById("fn-volatility-tag");
      const title = document.getElementById("fn-event-title");
      const dateEl = document.getElementById("fn-event-date");
      const actualVal = document.getElementById("fn-actual-val");
      const estVal = document.getElementById("fn-est-val");
      const priorVal = document.getElementById("fn-prior-val");
      const diffVal = document.getElementById("fn-diff-val");

      badge.style.backgroundColor = data.badgeColor || "#1e293b";
      badge.style.border = "1px solid rgba(255, 255, 255, 0.25)";
      badge.style.boxShadow = `0 0 24px ${data.badgeColor}99`;

      conviction.innerText = data.conviction || "SIGNAL DETECTED";
      conviction.style.color = "#ffffff";
      action.innerText = data.signal;
      action.style.color = "#ffffff";
      volTag.innerText = `Expected Volatility: ~${data.expectedPips} (${data.benchmarkSource || 'Benchmark'})`;
      volTag.style.color = "#ffffff";

      title.innerText = data.title;
      if (data.date) {
        const evDate = new Date(data.date);
        const gmt2Date = new Date(evDate.getTime() + (2 * 60 + evDate.getTimezoneOffset()) * 60000);
        dateEl.innerText = formatShortDateWithTime(gmt2Date) + " GMT+2";
      } else {
        dateEl.innerText = `${data.time || 'NOW'} GMT+2`;
      }

      actualVal.innerText = `${data.actual}${data.unit || ''}`;
      actualVal.style.color = "#ffffff";

      estVal.innerText = data.forecast !== null && data.forecast !== undefined ? `${data.forecast}${data.unit || ''}` : "--";
      priorVal.innerText = data.previous !== null && data.previous !== undefined ? `${data.previous}${data.unit || ''}` : "--";

      diffVal.innerText = `${data.diff}${data.unit || ''}`;
      diffVal.style.color = data.signal.includes("BUY") ? "#4ade80" : "#f87171";

      const isBuy = data.signal.includes("BUY");
      const isVeryHard = data.signal.includes("VERY HARD");
      playAudio(isBuy, isVeryHard);
    };

    // Live Message Listener from background worker
    chrome.runtime.onMessage.addListener((msg) => {
      if (msg.type === "NEWS_SIGNAL") {
        window.renderSniperSignal(msg.data || msg);
      } else if (msg.type === "UPCOMING_EVENT") {
        renderUpcoming(msg.data);
      }
    });

    // Request full state (upcoming, last signal, history) on initialization
    chrome.runtime.sendMessage({ type: "GET_STATE" }, (resp) => {
      if (resp) {
        if (resp.history && resp.history.length > 0) {
          cachedHistory = resp.history;
          renderHistoryList();
        }
        if (resp.lastSignal) {
          window.renderSniperSignal(resp.lastSignal);
        } else if (resp.upcoming) {
          renderUpcoming(resp.upcoming);
        }
      }
    });

    // 24-hour Clock with AM/PM (GMT+2)
    setInterval(() => {
      const now = new Date();
      const gmt2 = new Date(now.getTime() + (2 * 60 + now.getTimezoneOffset()) * 60000);
      const timeEl = document.getElementById("fn-time-display");
      if (timeEl) timeEl.innerText = formatTime24WithAmPm(gmt2) + " GMT+2";
    }, 1000);
  }
})();
