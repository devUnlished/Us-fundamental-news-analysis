# Fundamental News Sniper Indicator (Gold / XAUUSD)

Real-time fundamental news trading indicator designed to generate instant **BUY / SELL** signals for **Gold (XAUUSD)** upon US macroeconomic data releases (NFP, CPI, Unemployment Rate, Retail Sales, Interest Rates).

---

## ⚡ Fundamental Trading Logic

Gold (XAUUSD) has an inverse relationship with USD strength:
- **Strong USD** (e.g., NFP Actual > Forecast, CPI > Forecast, or Unemployment Rate < Forecast) ➡️ **🔴 SELL GOLD**
- **Weak USD** (e.g., NFP Actual < Forecast, CPI < Forecast, or Unemployment Rate > Forecast) ➡️ **🟢 BUY GOLD**

---

## 🚀 3 Solutions Included

### 1. Option A: Ultra-Fast Desktop Floating HUD (Recommended)
Floats transparently on top of **any chart** (TradingView, XM WebTrader, FBS WebTrader, cTrader, or MT4/MT5).
- **Zero latency**: Continuously polls the real-time calendar feed with sub-second polling during news release windows (e.g., 14:29:50 – 14:30:30 GMT+2).
- **Instant Audio Alert**: Plays distinct audible alerts for BUY and SELL.
- **Run it**:
  ```bash
  python desktop_hud/app.py
  ```

### 2. Option B: Chrome / Edge Browser Extension
Injects an overlay directly onto `tradingview.com`, `xm.com`, and `fbs.com` web trading pages:
1. Open Chrome / Brave / Edge and go to `chrome://extensions/`
2. Toggle on **Developer mode** (top right).
3. Click **Load unpacked** and select the folder:
   `C:\Users\Ty_Baby\Desktop\Us fundamental new analysis\chrome_extension`
4. Open your chart on TradingView, XM Web, or FBS Web. The HUD badge will appear on your chart.

### 3. Option C: MetaTrader 5 (MT5) Custom Indicator
- Located in `mt5_indicator/NewsSniper_Gold.mq5`
- Copy to your MT5 directory: `MQL5/Indicators/`
- Open MT5 MetaEditor, click **Compile**, and drag `NewsSniper_Gold` onto your `XAUUSD` chart.
- Connects directly to MT5's native broker economic calendar database.
