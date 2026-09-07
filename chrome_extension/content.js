// Content script injected onto TradingView, XM WebTrader, and FBS WebTrader pages
(function() {
  console.log("[Fundamental News Sniper] Injected on chart page.");

  let hudContainer = document.getElementById("fn-sniper-hud");
  if (!hudContainer) {
    hudContainer = document.createElement("div");
    hudContainer.id = "fn-sniper-hud";
    hudContainer.style.position = "fixed";
    hudContainer.style.top = "20px";
    hudContainer.style.right = "20px";
    hudContainer.style.zIndex = "9999999";
    hudContainer.style.backgroundColor = "rgba(18, 20, 24, 0.95)";
    hudContainer.style.color = "#ffffff";
    hudContainer.style.padding = "12px 18px";
    hudContainer.style.borderRadius = "8px";
    hudContainer.style.boxShadow = "0 6px 20px rgba(0,0,0,0.6)";
    hudContainer.style.fontFamily = "Segoe UI, -apple-system, sans-serif";
    hudContainer.style.border = "1px solid #334155";
    hudContainer.style.minWidth = "300px";
    hudContainer.style.transition = "all 0.3s ease";

    hudContainer.innerHTML = `
      <div style="font-size: 11px; font-weight: bold; color: #f0b90b; letter-spacing: 0.5px; margin-bottom: 6px;">
        ⚡ FUNDAMENTAL NEWS SNIPER | XAUUSD
      </div>
      <div id="fn-sniper-signal" style="font-size: 16px; font-weight: 800; background: #334155; padding: 8px; border-radius: 4px; text-align: center; margin-bottom: 6px;">
        STANDBY FOR NEWS
      </div>
      <div id="fn-sniper-desc" style="font-size: 11px; color: #94a3b8; line-height: 1.4;">
        Monitoring US high impact data releases...
      </div>
    `;
    document.body.appendChild(hudContainer);
  }

  function playAlertSound(isBuy) {
    try {
      const audioCtx = new (window.AudioContext || window.webkitAudioContext)();
      const osc = audioCtx.createOscillator();
      const gain = audioCtx.createGain();
      osc.connect(gain);
      gain.connect(audioCtx.destination);
      osc.type = "sine";
      osc.frequency.setValueAtTime(isBuy ? 880 : 440, audioCtx.currentTime);
      gain.gain.setValueAtTime(0.3, audioCtx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.0001, audioCtx.currentTime + 0.6);
      osc.start();
      osc.stop(audioCtx.currentTime + 0.6);
    } catch(e) {}
  }

  function displaySignal(data) {
    const signalEl = document.getElementById("fn-sniper-signal");
    const descEl = document.getElementById("fn-sniper-desc");

    if (data.signal === "BUY") {
      signalEl.style.backgroundColor = "#10b981";
      signalEl.style.color = "#ffffff";
      signalEl.innerText = "🟢 BUY GOLD (WEAK USD)";
      playAlertSound(true);
    } else if (data.signal === "SELL") {
      signalEl.style.backgroundColor = "#ef4444";
      signalEl.style.color = "#ffffff";
      signalEl.innerText = "🔴 SELL GOLD (STRONG USD)";
      playAlertSound(false);
    }

    descEl.innerText = `${data.title} | Actual: ${data.actual} vs Est: ${data.benchmark}\n${data.explanation}`;
  }

  chrome.runtime.onMessage.addListener((msg) => {
    if (msg.type === "NEWS_SIGNAL") {
      displaySignal(msg.data);
    }
  });
})();
