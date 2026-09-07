// Content script: High-detail institutional terminal HUD overlay for TradingView, XM & FBS
// Clean production version: connected exclusively to real live calendar data feed.
// Features: Drag-to-move, resizable, responsive metrics matrix, audio engine.
(function() {
  console.log("[News Sniper Terminal] Connected to Live Institutional Economic Feed.");

  let hud = document.getElementById("fn-sniper-hud");
  if (!hud) {
    hud = document.createElement("div");
    hud.id = "fn-sniper-hud";
    hud.style.cssText = `
      position: fixed;
      top: 24px;
      right: 24px;
      z-index: 2147483647;
      width: 350px;
      min-width: 250px;
      max-width: 600px;
      background: #0b0e14;
      border: 1px solid #1e293b;
      border-radius: 8px;
      box-shadow: 0 12px 36px rgba(0, 0, 0, 0.8), 0 0 0 1px rgba(255, 255, 255, 0.05);
      color: #e2e8f0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", sans-serif;
      resize: both;
      overflow: hidden;
      user-select: none;
      display: flex;
      flex-direction: column;
      box-sizing: border-box;
    `;

    hud.innerHTML = `
      <!-- Draggable Header -->
      <div id="fn-drag-handle" style="background: #141a24; padding: 8px 12px; border-bottom: 1px solid #1e293b; display: flex; justify-content: space-between; align-items: center; cursor: move;">
        <div style="display: flex; align-items: center; gap: 6px;">
          <span style="width: 8px; height: 8px; border-radius: 50%; background: #22c55e; display: inline-block; box-shadow: 0 0 8px #22c55e;"></span>
          <span style="font-size: 11px; font-weight: 700; letter-spacing: 0.8px; color: #f8fafc;">XAUUSD NEWS TERMINAL</span>
        </div>
        <div style="display: flex; align-items: center; gap: 8px;">
          <span id="fn-time-display" style="font-size: 10px; color: #94a3b8; font-family: monospace;">--:--:-- GMT+2</span>
          <span style="font-size: 10px; color: #64748b; cursor: move;" title="Drag to Move">✥</span>
        </div>
      </div>

      <!-- Scrollable / Responsive Content Body -->
      <div style="padding: 10px 12px; display: flex; flex-direction: column; gap: 8px; flex: 1; overflow-y: auto;">
        <!-- Main Action Banner -->
        <div id="fn-badge" style="background: #1e293b; border-radius: 6px; padding: 12px 14px; text-align: center; border: 1px solid rgba(255,255,255,0.06); transition: all 0.25s ease;">
          <div id="fn-conviction-tag" style="font-size: clamp(8px, 2.2vw, 10px); font-weight: 700; letter-spacing: 1px; color: #94a3b8; margin-bottom: 2px;">STANDBY MODE</div>
          <div id="fn-action-text" style="font-size: clamp(14px, 4.5vw, 22px); font-weight: 900; letter-spacing: 0.5px; color: #f1f5f9; line-height: 1.2;">LIVE FEED READY</div>
          <div id="fn-volatility-tag" style="font-size: clamp(8px, 2.2vw, 10px); color: #64748b; margin-top: 3px;">Awaiting Release Time...</div>
        </div>

        <!-- Metrics Matrix -->
        <div>
          <div id="fn-event-title" style="font-size: clamp(9px, 2.5vw, 11px); font-weight: 600; color: #38bdf8; margin-bottom: 6px;">Connected to US High-Impact Calendar</div>
          <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 6px; background: #0f141d; padding: 8px; border-radius: 6px; border: 1px solid #1e293b;">
            <div>
              <div style="font-size: 8px; color: #64748b; font-weight: 600; text-transform: uppercase;">Actual</div>
              <div id="fn-actual-val" style="font-size: clamp(10px, 3vw, 14px); font-weight: 700; color: #f8fafc; font-family: monospace;">--</div>
            </div>
            <div>
              <div style="font-size: 8px; color: #64748b; font-weight: 600; text-transform: uppercase;">Forecast</div>
              <div id="fn-est-val" style="font-size: clamp(10px, 3vw, 14px); font-weight: 700; color: #94a3b8; font-family: monospace;">--</div>
            </div>
            <div>
              <div style="font-size: 8px; color: #64748b; font-weight: 600; text-transform: uppercase;">Surprise Delta</div>
              <div id="fn-diff-val" style="font-size: clamp(10px, 3vw, 14px); font-weight: 800; color: #64748b; font-family: monospace;">--</div>
            </div>
          </div>
        </div>

        <!-- Live Status Footer -->
        <div style="border-top: 1px solid #18202f; padding-top: 6px; display: flex; justify-content: space-between; align-items: center;">
          <span style="font-size: 9px; color: #64748b; font-weight: 500;">Feed: TradingView Macro JSON</span>
          <span id="fn-status-indicator" style="font-size: 9px; color: #22c55e; font-weight: 600;">● Active 1s Polling</span>
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

    // Render Event & Conviction from Live Background Message
    window.renderSniperSignal = function(data) {
      const badge = document.getElementById("fn-badge");
      const conviction = document.getElementById("fn-conviction-tag");
      const action = document.getElementById("fn-action-text");
      const volTag = document.getElementById("fn-volatility-tag");
      const title = document.getElementById("fn-event-title");
      const actualVal = document.getElementById("fn-actual-val");
      const estVal = document.getElementById("fn-est-val");
      const diffVal = document.getElementById("fn-diff-val");

      badge.style.backgroundColor = data.badgeColor || "#1e293b";
      badge.style.border = "1px solid rgba(255, 255, 255, 0.25)";
      badge.style.boxShadow = `0 0 24px ${data.badgeColor}99`;

      conviction.innerText = data.conviction || "SIGNAL DETECTED";
      conviction.style.color = "#ffffff";
      action.innerText = data.signal;
      action.style.color = "#ffffff";
      volTag.innerText = `Expected Volatility: ~${data.expectedPips}`;
      volTag.style.color = "#ffffff";

      title.innerText = `${data.title} (${data.time || 'NOW'})`;
      actualVal.innerText = `${data.actual}${data.unit || ''}`;
      estVal.innerText = `${data.forecast}${data.unit || ''}`;
      diffVal.innerText = `${data.diff}${data.unit || ''}`;
      diffVal.style.color = data.signal.includes("BUY") ? "#4ade80" : "#f87171";

      const isBuy = data.signal.includes("BUY");
      const isVeryHard = data.signal.includes("VERY HARD");
      playAudio(isBuy, isVeryHard);
    };

    // Live Message Listener from background worker
    chrome.runtime.onMessage.addListener((msg) => {
      if (msg.type === "NEWS_SIGNAL") {
        window.renderSniperSignal(msg.data);
      }
    });

    // Clock (GMT+2)
    setInterval(() => {
      const now = new Date();
      const gmt2 = new Date(now.getTime() + (2 * 60 + now.getTimezoneOffset()) * 60000);
      const timeEl = document.getElementById("fn-time-display");
      if (timeEl) timeEl.innerText = gmt2.toLocaleTimeString() + " GMT+2";
    }, 1000);
  }
})();
