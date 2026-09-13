# MetaTrader Emergency News Close Script Guide

## 1. The Core Problem: Why Broker Platforms Freeze During News
During Tier-1 US economic releases (Nonfarm Payrolls, CPI, Core PCE, FOMC), high retail traffic and market maker quote adjustments cause extreme latency on broker web interfaces (XM, FBS, etc.):

- **Top-of-Book Depth Evaporation**: Bid/Ask spreads widen from 1.5–2 pips to 35–60 pips within 500ms.
- **Queue Saturation**: Tens of thousands of manual click requests flood broker bridge servers simultaneously.
- **Requote Rejections**: When clicking "Close", if the price shifts by even $0.30–$1.00 on Gold (`XAUUSD`), the broker returns `136 (Off quotes)` or `138 (Requote)` error dialogs, locking the user interface and preventing order execution.

---

## 2. The Solution: Script-Driven Relentless Retry Loop
An MQL script bypasses the terminal UI thread, executing direct TCP trade commands with:
1. **Slippage Tolerance (`SlippagePoints = 300`)**: Accepts up to 30 pips deviation, converting requotes into instant market fills.
2. **Relentless Auto-Retry Loop (`MaxRetries = 50`, `RetryDelayMs = 100`)**: If the broker responds with `ERR_OFF_QUOTES`, `ERR_SERVER_BUSY`, or `ERR_TRADE_CONTEXT_BUSY`, the script calls `RefreshRates()` and re-fires every 100ms until every position is confirmed closed.
3. **Single-Tap Execution**: The trader triggers a single hotkey (e.g., `F12`), allowing the script to automate the entire liquidation process without further manual intervention.

---

## 3. Included Scripts

The scripts are located in the repository at [`mql_scripts/`](file:///C:/Users/Ty_Baby/Desktop/Us%20fundamental%20new%20analysis/mql_scripts):

| File | Platform | Purpose |
| :--- | :--- | :--- |
| [`EmergencyNewsClose.mq4`](file:///C:/Users/Ty_Baby/Desktop/Us%20fundamental%20new%20analysis/mql_scripts/EmergencyNewsClose.mq4) | MetaTrader 4 (MT4) | Auto-retrying position liquidation script for MT4. |
| [`EmergencyNewsClose.mq5`](file:///C:/Users/Ty_Baby/Desktop/Us%20fundamental%20new%20analysis/mql_scripts/EmergencyNewsClose.mq5) | MetaTrader 5 (MT5) | Position liquidation script using the native MQL5 `CTrade` library. |

---

## 4. Script Configuration Parameters

| Input Parameter | Default | Description |
| :--- | :--- | :--- |
| `MaxRetries` | `50` | Maximum number of attempts per position before aborting. |
| `RetryDelayMs` | `100` | Milliseconds to wait between retry attempts. |
| `SlippagePoints` | `300` | Allowed slippage tolerance in points (~30 pips on Gold). |
| `CloseOnlyCurrent` | `false` | If `true`, closes only the active chart symbol; if `false`, closes all open market orders across all pairs. |

---

## 5. Step-by-Step Installation & Setup

1. Open **MetaTrader (MT4 or MT5)**.
2. In the top menu, select **File** -> **Open Data Folder**.
3. Navigate to:
   - For MT4: `MQL4` -> `Scripts`
   - For MT5: `MQL5` -> `Scripts`
4. Copy `EmergencyNewsClose.mq4` or `EmergencyNewsClose.mq5` into this folder.
5. In MetaTrader, open the **Navigator** window (`Ctrl + N`), right-click **Scripts**, and click **Refresh**.
6. **Assign a Global Hotkey (Essential for Instant Reaction)**:
   - In the Navigator tree under **Scripts**, right-click `EmergencyNewsClose`.
   - Select **Set hotkey**.
   - Assign a shortcut such as **`F12`** or **`Ctrl + Shift + X`**.
7. Enable **"AutoTrading" / "Algo Trading"** on the main MetaTrader toolbar.

---

## 6. Execution Workflow During News Releases

1. Enter high-conviction positions when the News Sniper Terminal signals an extreme surprise or solid breakout.
2. Monitor trade progression and take-profit targets via the HUD alert guidance.
3. When the target is reached, press **`F12`** once.
4. The script executes the retry sequence in memory and triggers an audible alert confirming:
   `"EMERGENCY CLOSE COMPLETE: Total Closed: X, Failed: 0"`
