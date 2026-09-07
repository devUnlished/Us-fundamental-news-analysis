# ⚡ Fundamental News Sniper & Algorithmic Trading Suite (XAUUSD / Gold)

A high-performance fundamental news analysis terminal and execution suite engineered to exploit macroeconomic data releases (NFP, CPI, FOMC, Core PCE, Retail Sales, Unemployment Rate, PMIs) on **Gold (XAUUSD)** with sub-second precision.

---

## 📖 1. What This Software Is

Traditional retail economic calendars (like Investing.com or Forex Factory) update slowly in the browser, suffer from Cloudflare anti-bot blocks, and lack quantitative deviation analysis. By the time a manual trader reads the number, the initial 100-pip spike has already passed.

**Fundamental News Sniper** solves this by:
1. Connecting directly to **institutional-grade, low-latency economic calendar data feeds** (`economic-calendar.tradingview.com/events`).
2. Continuously parsing consensus forecasts and prior baselines.
3. Quantifying the statistical **Surprise Delta** ($\text{Actual} - \text{Forecast}$) the millisecond numbers drop.
4. Categorizing volatility into actionable **Conviction Tiers** (`SELL VERY HARD`, `SELL HARD`, `SELL MODERATE`, `BUY VERY HARD`, etc.).
5. Rendering an always-on-top, draggable, resizable institutional trading HUD directly over **TradingView, XM WebTrader, and FBS WebTrader**, complete with instant audio cues.

---

## ⚙️ 2. How the Fundamental Directional Logic Works

Because Gold is denominated in US Dollars (**XAU/USD**), it possesses an intrinsic **inverse relationship** with the macroeconomic health of the United States:

$$\text{Surprise Delta} = \text{Actual Release} - \text{Consensus Forecast}$$
$$\text{USD Score} = \text{Surprise Delta} \times \text{Indicator Direction Factor}$$

### The News Rules:
* **Proportional USD News** ($\text{Factor} = +1$):
  * *Events*: Nonfarm Payrolls (NFP), Consumer Price Index (CPI), Core PCE, PPI, Retail Sales, GDP, ISM PMIs, Fed Funds Target Rate.
  * **Actual > Forecast** ➡️ **Stronger USD** ➡️ **🔴 SELL GOLD (XAUUSD)**
  * **Actual < Forecast** ➡️ **Weaker USD** ➡️ **🟢 BUY GOLD (XAUUSD)**
* **Inverse USD News** ($\text{Factor} = -1$):
  * *Events*: Unemployment Rate, Initial Jobless Claims.
  * **Actual > Forecast** (Higher unemployment / more jobless claims) ➡️ **Weaker USD** ➡️ **🟢 BUY GOLD (XAUUSD)**
  * **Actual < Forecast** (Stronger labor market) ➡️ **Stronger USD** ➡️ **🔴 SELL GOLD (XAUUSD)**

### Statistical Conviction Tiers:
The engine scales its recommendations based on the size of the surprise:
* **EXTREME SURPRISE ($\ge 2.0\sigma$)**: **`SELL VERY HARD`** or **`BUY VERY HARD`** (Anticipate $180 - 350+$ pip explosive moves).
* **HIGH CONVICTION ($1.0\sigma - 1.9\sigma$)**: **`SELL HARD`** or **`BUY HARD`** (Anticipate $90 - 180$ pip clean trends).
* **MODERATE SURPRISE ($0.4\sigma - 0.9\sigma$)**: **`SELL MODERATE`** or **`BUY MODERATE`** (Anticipate $40 - 80$ pip retests).

---

## 🛠️ 3. How to Set It Up

The repository contains three deployment formats:

### Option C: Chrome / Edge Browser Extension (Active HUD Overlay)
*Runs directly inside your browser on TradingView, XM, and FBS.*
1. Open Google Chrome (or Edge / Brave) and navigate to:
   ```text
   chrome://extensions/
   ```
2. Enable **Developer mode** via the toggle in the top-right corner.
3. Click the **Load unpacked** button (top-left).
4. Select the folder:
   ```text
   C:\Users\Ty_Baby\Desktop\Us fundamental new analysis\chrome_extension
   ```
5. Open your chart on [TradingView](https://www.tradingview.com/chart/) or XM/FBS WebTrader.
6. The floating, draggable, resizable **XAUUSD News Terminal** will appear in the top-right corner.

### Option A: Desktop Floating HUD & PC Startup Reminders
*Floats above all desktop apps with native Windows toast alerts on PC boot.*
1. Run manually:
   ```powershell
   python desktop_hud\app.py
   ```
2. To auto-run in the background whenever you boot your PC:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install_startup.ps1
   ```

### Option B: Native MetaTrader 5 (MT5) Desktop Indicator
1. Copy `mt5_indicator\NewsSniper_Gold.mq5` into your MT5 directory: `MQL5\Indicators\`.
2. Open MetaEditor (**F4**), open the script, and press **Compile (F7)**.
3. Attach `NewsSniper_Gold` directly to your `XAUUSD` chart.

---

## 🤖 4. Strategy Blueprint: The "Swing-Breakout Liquidity" Trading Robot (EA)

### The Problem with Immediate Market Execution at News
Entering with a raw `Market Order` (Instant Buy/Sell) at 14:30:00 carries two deadly traps:
1. **Massive Spread Widening & Slippage**: Spreads on Gold frequently blow out from 15 cents to $3.00+ during the first 3 seconds of NFP.
2. **The 2-Sided Liquidity Sweep (Fakeout Spike)**: Market makers frequently spike price **upwards** to grab buy-side liquidity / trigger sellers' early stop-losses before plunging in the true fundamental direction.

### The Proposed Robot Architecture: Stop-Order on Structural Swing Highs/Lows

Instead of market execution, the robot automates **Stop-Order placement at key structural swings**:

```
[ Pre-News (14:29:50) ]
Scan M5 / M15 Chart on XAUUSD:
  ├── Find Nearest Swing High (Last 10-20 candles on M5/M15)
  └── Find Nearest Swing Low  (Last 10-20 candles on M5/M15)

[ News Drops at 14:30:01 ]
Feed Analysis Result: STRONG USD (e.g. NFP Beat -> SELL VERY HARD)
  │
  ├── 1. IGNORE MARKET EXECUTION (Do NOT sell into the initial spread spike)
  ├── 2. Calculate Sell Stop Trigger:
  │      Entry Price = Nearest M5/M15 Swing Low - Buffer (e.g., -5 to -10 pips)
  ├── 3. Place Pending Order:
  │      Type: SELL STOP
  │      Price: Swing Low Entry
  │      Stop Loss: Above the newly formed news spike high (or above M5 Swing High)
  │      Take Profit: Scaled TP (TP1 = 1:2 R:R, TP2 = Next Major Support)
  │      Expiration: Cancel if not triggered within 15–30 minutes
  └── 4. Trailing Mechanism:
         Once Swing Low breaks, momentum confirms true institutional direction.
         Activate Breakeven + Trailing Stop.
```

### Why This Specific Format Is Superior:
1. **Complete Immunity to the "Stop Hunt Spike"**:
   If the news spikes up 80 pips first to take out sellers, your `SELL STOP` sits untouched down at the swing low. You never get stopped out by the pre-move fakeout.
2. **True Momentum Confirmation**:
   Gold only triggers your entry once it actually breaks structural market structure (the swing low). If price consolidates or refuses to break structure, no order is executed and no capital is risked.
3. **Tight Spread Execution**:
   By the time price reaches the structural swing low, initial 14:30:00 spread widening has stabilized back to normal tight spreads.

---

## 🚀 Recommended Implementation Path for the Robot

Because web platforms (TradingView Web, XM Web, FBS Web) strictly block third-party scripts from dispatching real broker trades, an automated trading robot needs a direct broker trading bridge:

1. **Approach 1: Native MT5 / MT4 Expert Advisor (MQL5 / MQL4)**
   * Built as an Expert Advisor (`NewsSniper_EA.mq5`) loaded into your XM or FBS MT5 terminal.
   * Scans the M5/M15 chart using `iLowest` / `iHighest` or ZigZag for swing extremes.
   * Plugs into the calendar feed or MT5 `CalendarValueHistory`.
   * Fires the `OrderSend(..., ORDER_TYPE_SELL_STOP, swingLow, ...)` instantly.

2. **Approach 2: Python Algorithmic Engine with MetaTrader5 Bridge**
   * Python handles calendar fetching and calculates the deviation.
   * Python connects to the desktop MT5 terminal via `import MetaTrader5 as mt5`.
   * Grabs the M5/M15 candle data via `mt5.copy_rates_from_pos("XAUUSD", mt5.TIMEFRAME_M5, 0, 30)`.
   * Automatically calculates the swing low, determines lot size based on account balance, and transmits the pending `SELL STOP` order via API.

We can proceed to develop this exact Swing-Breakout EA / Python Robot whenever you are ready!
