//+------------------------------------------------------------------+
//|                                     AllInOneNewsTerminal.mq5     |
//|            High-Impact News Execution & Liquidation Engine       |
//|    NEW: Calibrated Spike Limits & Take Profits derived from      |
//|         3-Year Forensic Manipulation Wick & True Move Data       |
//+------------------------------------------------------------------+
#property copyright "News Sniper Terminal"
#property link      "https://github.com/devUnlished/Us-fundamental-news-analysis"
#property version   "5.00"

#include <Trade\Trade.mqh>

input group "=== BARCODE SETTINGS ===";
input int      InpNumberOfStripes   = 10;      // Number of barcode stripes per trigger
input double   InpDefaultLot        = 0.05;    // Starting Lot size per stripe

input group "=== DYNAMIC CALIBRATION ===";
input bool     InpAutoCalibrateNews = true;    // Auto-calibrate Limit Distance & TP to live news release!
input double   InpFallbackSpikeDist = 18.0;    // Fallback Limit Offset in Gold $ ($18.00 = 180 pips)
input double   InpFallbackTPDist    = 30.0;    // Fallback Take Profit in Gold $ ($30.00 = 300 pips)

input group "=== SPIKE LIMITS ===";
input double   InpMarginPercent     = 70.0;    // Margin Utilization % for Spike Limit size
input int      InpNumberOfLimitStripes = 10;   // Divide total lot size into N split limit orders
input double   InpLadderStep        = 0.50;    // Pip/Dollar step between limit stripes ($0.50 = 5 pips)
input int      InpLimitExpiryMins   = 15;      // Auto-cancel unfilled limits after N minutes

input group "=== AUTO-PILOT NEWS ROBOT ===";
input bool     InpEnableAutoPilot   = false;   // Trade hands-free when news alert triggers (DISABLED)
input bool     InpAutoArmLimits     = false;   // Step 1: Auto-arm 10 Spike Limits at release
input bool     InpAutoBarcode       = false;   // Step 2: Auto-fire Barcode after spike
input int      InpBarcodeDelaySecs  = 10;      // Seconds to wait after spike before firing 1st Barcode
input int      InpBarcodeWaveCount  = 2;       // Number of Barcode waves to fire (default: 2 barcodes)
input int      InpWaveIntervalSecs  = 5;       // Seconds between Wave 1 and Wave 2 Barcodes
input bool     InpEnableAudioAlert  = false;   // Play chime on automatic trade execution

input group "=== EMERGENCY CLOSE ===";
input int      InpMaxRetries        = 50;      // Retry attempts on broker requote
input int      InpSlippagePoints    = 300;     // Slippage allowance in points (30 pips)

CTrade trade;
double g_currentLot = 0.05;
string g_activeNewsName = "Standby (Normal)";
double g_activeSpikeOffset = 18.00; // in Gold dollars ($18.00 = 180 pips)
double g_activeTPDist = 30.00;      // in Gold dollars ($30.00 = 300 pips)
string g_activeTier = "STANDARD";

// Auto-pilot state tracking
ulong  g_lastTradedValueId = 0;
datetime g_signalTriggerTime = 0;
datetime g_lastWaveTime = 0;
int    g_wavesFired = 0;
ENUM_ORDER_TYPE g_pendingBarcodeType = WRONG_VALUE;
bool   g_barcodePending = false;

void ExecuteBarcode(ENUM_ORDER_TYPE orderType, double customLot = 0.0);
void ArmSpikeLimits(ENUM_ORDER_TYPE orderType);
bool CanAffordBarcode(ENUM_ORDER_TYPE orderType, double &outLotPerStripe);

void CreateButton(string name, string text, int x, int y, int w, int h, color bg, color fg, int fontSize = 9)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI Semibold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, fg);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrNONE);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void CreateEditBox(string name, string text, int x, int y, int w, int h)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI Bold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 11);
   ObjectSetInteger(0, name, OBJPROP_COLOR, C'248,250,252');
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, C'30,41,59');
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, C'71,85,105');
   ObjectSetInteger(0, name, OBJPROP_ALIGN, ALIGN_CENTER);
}

void DrawHUD()
{
   int startX = 20;
   int startY = 35;
   int btnW = 140;
   int btnH = 36;
   int gap = 6;
   int totalW = (btnW * 2) + gap;

   // Explicitly purge any legacy test buttons from chart
   ObjectDelete(0, "BTN_TEST_BUY");
   ObjectDelete(0, "BTN_TEST_SELL");

   // Row 0: Prominent Dark Status & Signal Box
   ObjectDelete(0, "BOX_AUTOBOT_BG");
   ObjectCreate(0, "BOX_AUTOBOT_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "BOX_AUTOBOT_BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "BOX_AUTOBOT_BG", OBJPROP_XDISTANCE, startX);
   ObjectSetInteger(0, "BOX_AUTOBOT_BG", OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, "BOX_AUTOBOT_BG", OBJPROP_XSIZE, totalW);
   ObjectSetInteger(0, "BOX_AUTOBOT_BG", OBJPROP_YSIZE, 38);
   ObjectSetInteger(0, "BOX_AUTOBOT_BG", OBJPROP_BGCOLOR, C'15,23,42');
   ObjectSetInteger(0, "BOX_AUTOBOT_BG", OBJPROP_BORDER_COLOR, C'51,65,85');

   ObjectDelete(0, "LBL_AUTOBOT_BADGE");
   ObjectCreate(0, "LBL_AUTOBOT_BADGE", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "LBL_AUTOBOT_BADGE", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "LBL_AUTOBOT_BADGE", OBJPROP_XDISTANCE, startX + 10);
   ObjectSetInteger(0, "LBL_AUTOBOT_BADGE", OBJPROP_YDISTANCE, startY + 5);
   ObjectSetString(0, "LBL_AUTOBOT_BADGE", OBJPROP_FONT, "Segoe UI Bold");
   ObjectSetInteger(0, "LBL_AUTOBOT_BADGE", OBJPROP_FONTSIZE, 9);
   if(InpEnableAutoPilot)
   {
      ObjectSetString(0, "LBL_AUTOBOT_BADGE", OBJPROP_TEXT, "🤖 AUTO-PILOT TRADING BOT: ACTIVE");
      ObjectSetInteger(0, "LBL_AUTOBOT_BADGE", OBJPROP_COLOR, C'52,211,153'); // Emerald green
   }
   else
   {
      ObjectSetString(0, "LBL_AUTOBOT_BADGE", OBJPROP_TEXT, "✋ AUTO-PILOT DISABLED (MANUAL ONLY)");
      ObjectSetInteger(0, "LBL_AUTOBOT_BADGE", OBJPROP_COLOR, C'248,113,113'); // Red
   }

   ObjectDelete(0, "LBL_AUTOBOT_SIGNAL");
   ObjectCreate(0, "LBL_AUTOBOT_SIGNAL", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "LBL_AUTOBOT_SIGNAL", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "LBL_AUTOBOT_SIGNAL", OBJPROP_XDISTANCE, startX + 10);
   ObjectSetInteger(0, "LBL_AUTOBOT_SIGNAL", OBJPROP_YDISTANCE, startY + 20);
   ObjectSetString(0, "LBL_AUTOBOT_SIGNAL", OBJPROP_FONT, "Segoe UI Semibold");
   ObjectSetInteger(0, "LBL_AUTOBOT_SIGNAL", OBJPROP_FONTSIZE, 8);
   if(InpEnableAutoPilot)
   {
      ObjectSetString(0, "LBL_AUTOBOT_SIGNAL", OBJPROP_TEXT, "Waiting for release | 10 Limits + 2 Barcode Waves Armed");
      ObjectSetInteger(0, "LBL_AUTOBOT_SIGNAL", OBJPROP_COLOR, C'148,163,184');
   }
   else
   {
      ObjectSetString(0, "LBL_AUTOBOT_SIGNAL", OBJPROP_TEXT, "Live Auto-Pilot STOPPED | Manual Buttons & Hotkeys Only");
      ObjectSetInteger(0, "LBL_AUTOBOT_SIGNAL", OBJPROP_COLOR, C'203,213,225');
   }

   // Row 1: Lot Selector
   int r1 = startY + 44;
   CreateButton("BTN_LOT_MINUS", "-", startX, r1, 30, 26, C'30,41,59', clrWhite, 11);
   CreateEditBox("EDT_LOT_SIZE", DoubleToString(g_currentLot, 2), startX + 32, r1, 60, 26);
   CreateButton("BTN_LOT_PLUS", "+", startX + 94, r1, 30, 26, C'30,41,59', clrWhite, 11);
   
   CreateButton("BTN_LOT_001", ".01", startX + 128, r1, 36, 26, C'15,23,42', C'148,163,184', 8);
   CreateButton("BTN_LOT_005", ".05", startX + 166, r1, 36, 26, C'15,23,42', C'148,163,184', 8);
   CreateButton("BTN_LOT_010", ".10", startX + 204, r1, 36, 26, C'15,23,42', C'148,163,184', 8);
   CreateButton("BTN_LOT_020", ".20", startX + 242, r1, 36, 26, C'15,23,42', C'148,163,184', 8);

   // Row 2: Barcode Buy/Sell Buttons
   int r2 = r1 + 32;
   CreateButton("BTN_BUY",  "▲ BUY BARCODE [B]",  startX, r2, btnW, btnH, C'22,163,74', clrWhite);
   CreateButton("BTN_SELL", "▼ SELL BARCODE [S]", startX + btnW + gap, r2, btnW, btnH, C'220,38,38', clrWhite);

   // Row 3: 80% Margin Limit Sniper Buttons (Armed with 3-Year Empiric Wick Offsets)
   int r3 = r2 + btnH + gap;
   string kTxt = StringFormat("K: BUY LIMIT (-$%.0f)", g_activeSpikeOffset);
   string lTxt = StringFormat("L: SELL LIMIT (+$%.0f)", g_activeSpikeOffset);
   CreateButton("BTN_KLIMIT", kTxt, startX, r3, btnW, 30, C'15,23,42', C'56,189,248');
   CreateButton("BTN_LLIMIT", lTxt, startX + btnW + gap, r3, btnW, 30, C'15,23,42', C'248,113,113');

   // Row 4: Panic Close Kill Switch
   int r4 = r3 + 34;
   CreateButton("BTN_CLOSE", "✖ PANIC CLOSE ALL [X]", startX, r4, totalW, 38, C'185,28,28', clrWhite);

   // Row 5: Dynamic Intelligence Display
   int r5 = r4 + 42;
   ObjectDelete(0, "LBL_STATUS");
   ObjectCreate(0, "LBL_STATUS", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "LBL_STATUS", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "LBL_STATUS", OBJPROP_XDISTANCE, startX);
   ObjectSetInteger(0, "LBL_STATUS", OBJPROP_YDISTANCE, r5);
   ObjectSetString(0, "LBL_STATUS", OBJPROP_FONT, "Segoe UI");
   ObjectSetInteger(0, "LBL_STATUS", OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, "LBL_STATUS", OBJPROP_COLOR, C'148,163,184');
}

// Inspect live calendar & calibrate Wick Limit + Take Profit dynamically
void CalibrateNewsTargets()
{
   if(!InpAutoCalibrateNews) return;

   datetime now = TimeCurrent();
   MqlCalendarValue values[];
   // Scan -1 hour up to +12 hours (43200s) to calibrate targets for FOMC/NFP/CPI well before release
   int count = CalendarValueHistory(values, now - 3600, now + 43200, "US");
   
   bool eventFound = false;

   if(count > 0)
   {
      int targetIdx = -1;
      datetime nearestTime = 0;

      // Priority 1: Check if an event was published in the last 5 minutes
      for(int i = 0; i < count; i++)
      {
         bool hasActual = (values[i].actual_value != LONG_MIN && 
                           values[i].actual_value != WRONG_VALUE && 
                           values[i].actual_value > -9000000000000000000LL &&
                           values[i].time <= now &&
                           (now - values[i].time) <= 300);

         if(hasActual)
         {
            MqlCalendarEvent ev;
            if(CalendarEventById(values[i].event_id, ev))
            {
               string low = ev.name; StringToLower(low);
               if(StringFind(low, "retail") >= 0 || StringFind(low, "fomc") >= 0 ||
                  StringFind(low, "interest rate") >= 0 || StringFind(low, "federal funds") >= 0 ||
                  StringFind(low, "cpi") >= 0 || StringFind(low, "nonfarm") >= 0)
               {
                  targetIdx = i;
                  break;
               }
            }
         }
      }

      // Priority 2: If no live release right now, select the CHRONOLOGICALLY NEAREST upcoming target
      if(targetIdx < 0)
      {
         for(int i = 0; i < count; i++)
         {
            if(values[i].time >= (now - 60))
            {
               MqlCalendarEvent ev;
               if(CalendarEventById(values[i].event_id, ev))
               {
                  string low = ev.name; StringToLower(low);
                  if(StringFind(low, "retail") >= 0 || StringFind(low, "fomc") >= 0 ||
                     StringFind(low, "interest rate") >= 0 || StringFind(low, "federal funds") >= 0 ||
                     StringFind(low, "cpi") >= 0 || StringFind(low, "nonfarm") >= 0)
                  {
                     if(nearestTime == 0 || values[i].time < nearestTime)
                     {
                        nearestTime = values[i].time;
                        targetIdx = i;
                     }
                  }
               }
            }
         }
      }

      if(targetIdx >= 0)
      {
         MqlCalendarEvent ev;
         if(CalendarEventById(values[targetIdx].event_id, ev))
         {
            string low = ev.name; StringToLower(low);
            
            bool hasActual = (values[targetIdx].actual_value != LONG_MIN && 
                              values[targetIdx].actual_value != WRONG_VALUE && 
                              values[targetIdx].actual_value > -9000000000000000000LL &&
                              values[targetIdx].time <= now &&
                              (now - values[targetIdx].time) <= 300);

            bool hasForecast = (values[targetIdx].forecast_value != LONG_MIN && 
                                values[targetIdx].forecast_value != WRONG_VALUE && 
                                values[targetIdx].forecast_value > -9000000000000000000LL);

            bool hasPrev = (values[targetIdx].prev_value != LONG_MIN && 
                            values[targetIdx].prev_value != WRONG_VALUE && 
                            values[targetIdx].prev_value > -9000000000000000000LL);

            double mult = MathPow(10.0, ev.digits);
            if(mult <= 0) mult = 1.0;

            double actual   = hasActual ? ((double)values[targetIdx].actual_value / mult) : WRONG_VALUE;
            double forecast = hasForecast ? ((double)values[targetIdx].forecast_value / mult) : WRONG_VALUE;
            double prev     = hasPrev ? ((double)values[targetIdx].prev_value / mult) : WRONG_VALUE;
            double bench    = (forecast != WRONG_VALUE) ? forecast : prev;
            double diff     = (actual != WRONG_VALUE && bench != WRONG_VALUE) ? MathAbs(actual - bench) : 0.0;

            bool isTarget = false;

            if(StringFind(low, "retail") >= 0)
            {
               g_activeNewsName = "Retail Sales (MoM)";
               g_activeTier = "SOLID"; 
               g_activeSpikeOffset = 16.0; // $16.00 (160 pip wick)
               g_activeTPDist = 35.0;      // $35.00 (350 pip TP)
               isTarget = true;
            }
            else if(StringFind(low, "interest rate") >= 0 || StringFind(low, "fomc") >= 0 || 
                    StringFind(low, "federal funds") >= 0 || StringFind(low, "fed funds") >= 0)
            {
               g_activeNewsName = "FOMC Rate Decision";
               g_activeTier = "BLOWOUT"; 
               g_activeSpikeOffset = 22.0; // 220 pip manipulation wick limit
               g_activeTPDist = 50.0;      // 500 pip TP target
               isTarget = true;
            }
            else if(StringFind(low, "nonfarm") >= 0 || StringFind(low, "non farm") >= 0)
            {
               g_activeNewsName = "Nonfarm Payrolls (NFP)";
               if(diff > 68.0)      { g_activeTier = "BLOWOUT"; g_activeSpikeOffset = 25.0; g_activeTPDist = 55.0; }
               else if(diff > 30.0) { g_activeTier = "SOLID";   g_activeSpikeOffset = 20.0; g_activeTPDist = 45.0; }
               else                 { g_activeTier = "MODEST";  g_activeSpikeOffset = 18.0; g_activeTPDist = 25.0; }
               isTarget = true;
            }
            else if(StringFind(low, "cpi") >= 0 || StringFind(low, "consumer price") >= 0)
            {
               g_activeNewsName = "Consumer Price Index (CPI)";
               if(diff > 0.25)      { g_activeTier = "BLOWOUT"; g_activeSpikeOffset = 22.0; g_activeTPDist = 50.0; }
               else if(diff > 0.12) { g_activeTier = "SOLID";   g_activeSpikeOffset = 16.0; g_activeTPDist = 38.0; }
               else                 { g_activeTier = "MODEST";  g_activeSpikeOffset = 12.0; g_activeTPDist = 25.0; }
               isTarget = true;
            }

            if(isTarget)
            {
               eventFound = true;

               // Auto-Pilot Execution on Real-Time Calendar Release ONLY
               if(InpEnableAutoPilot && hasActual && bench != WRONG_VALUE && values[targetIdx].id != 0 && values[targetIdx].id != g_lastTradedValueId)
               {
                  if(MathAbs(actual - bench) > 0.0001)
                  {
                     int signalDir = 0; // +1 = Strong USD -> SELL GOLD, -1 = Weak USD -> BUY GOLD
                     if(StringFind(low, "unemployment rate") >= 0 || StringFind(low, "jobless claims") >= 0)
                     {
                        signalDir = (actual > bench) ? -1 : 1; // Higher unemployment -> Weak USD -> Buy Gold (-1)
                     }
                     else
                     {
                        signalDir = (actual > bench) ? 1 : -1; // Higher Rate/CPI/NFP/PCE/Retail -> Strong USD -> Sell Gold (+1)
                     }

                     g_lastTradedValueId = values[targetIdx].id;
                     ENUM_ORDER_TYPE spikeLimitType = (signalDir == 1) ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_BUY_LIMIT;
                     ENUM_ORDER_TYPE barcodeType    = (signalDir == 1) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;

                     string dirName = (signalDir == 1) ? "SELL GOLD (Strong USD)" : "BUY GOLD (Weak USD)";
                     PrintFormat("🚀 [AUTO-PILOT ALERT TRIGGERED]: %s | Direction: %s | Actual: %.2f vs Forecast: %.2f", 
                                 ev.name, dirName, actual, bench);

                     if(InpEnableAudioAlert)
                     {
                        PrintFormat("🤖 AUTO-PILOT TRIGGERED: %s -> %s!", ev.name, dirName);
                     }

                     // Step 1: Immediately arm 10 Spike Limits across the manipulation wick depth
                     if(InpAutoArmLimits)
                     {
                        ArmSpikeLimits(spikeLimitType);
                     }

                     // Step 2: Schedule the post-spike Barcode market blast
                     if(InpAutoBarcode)
                     {
                        g_signalTriggerTime = TimeCurrent();
                        g_lastWaveTime = 0;
                        g_wavesFired = 0;
                        g_pendingBarcodeType = barcodeType;
                        g_barcodePending = true;
                        PrintFormat("⏳ Post-spike Barcode armed: Will fire %d barcode waves (First wave in %d seconds) in direction %s...", 
                                    InpBarcodeWaveCount, InpBarcodeDelaySecs, dirName);
                     }
                     return;
                  }
               }
            }
         }
      }
   }
   
   if(!eventFound)
   {
      // Fallback when standing by
      g_activeNewsName = "Standby (Pre-News)";
      g_activeTier = "STANDARD";
      g_activeSpikeOffset = InpFallbackSpikeDist;
      g_activeTPDist = InpFallbackTPDist;
   }
}

void CheckAutoBarcodeTimer()
{
   if(!InpEnableAutoPilot || !g_barcodePending || g_pendingBarcodeType == WRONG_VALUE) return;

   datetime now = TimeCurrent();

   // Wave 1: The moment the adverse spike window finishes (or price starts moving) AND margin allows
   if(g_wavesFired == 0)
   {
      if(now - g_signalTriggerTime >= InpBarcodeDelaySecs)
      {
         double lotPerStripe = 0.0;
         if(CanAffordBarcode(g_pendingBarcodeType, lotPerStripe))
         {
            PrintFormat("🔥 [BARCODE WAVE 1 FIRING]: Margin verified! Executing 10 stripes at %.2f lots...", lotPerStripe);
            ExecuteBarcode(g_pendingBarcodeType, lotPerStripe);
            g_wavesFired = 1;
            g_lastWaveTime = now;

            if(InpBarcodeWaveCount <= 1)
            {
               g_barcodePending = false;
               g_pendingBarcodeType = WRONG_VALUE;
            }
         }
      }
   }
   // Wave 2: The moment equity/free margin unlocks from Wave 1 profits, fire the next wave!
   else if(g_wavesFired < InpBarcodeWaveCount)
   {
      // Check every 250ms if margin/equity has expanded enough to fund Wave 2
      if(now - g_lastWaveTime >= 2) // At least 2 seconds after Wave 1
      {
         double lotPerStripe2 = 0.0;
         if(CanAffordBarcode(g_pendingBarcodeType, lotPerStripe2))
         {
            g_wavesFired++;
            PrintFormat("🔥🔥 [BARCODE WAVE %d/%d FIRING]: Equity expanded! Free margin unlocked. Firing 10 stripes at %.2f lots!", 
                        g_wavesFired, InpBarcodeWaveCount, lotPerStripe2);
            ExecuteBarcode(g_pendingBarcodeType, lotPerStripe2);
            g_lastWaveTime = now;

            if(g_wavesFired >= InpBarcodeWaveCount)
            {
               g_barcodePending = false;
               g_pendingBarcodeType = WRONG_VALUE;
            }
         }
      }
   }
}

void UpdateHUDStatus()
{
   string textVal = ObjectGetString(0, "EDT_LOT_SIZE", OBJPROP_TEXT);
   double enteredLot = StringToDouble(textVal);
   if(enteredLot >= 0.01 && enteredLot <= 50.0) g_currentLot = NormalizeDouble(enteredLot, 2);

   CalibrateNewsTargets();
   CheckAutoBarcodeTimer();

   // Update Limit button texts with live calibrated spike wick distances
   ObjectSetString(0, "BTN_KLIMIT", OBJPROP_TEXT, StringFormat("K: BUY LIMIT (-$%.0f)", g_activeSpikeOffset));
   ObjectSetString(0, "BTN_LLIMIT", OBJPROP_TEXT, StringFormat("L: SELL LIMIT (+$%.0f)", g_activeSpikeOffset));

   if(InpEnableAutoPilot)
   {
      ObjectSetString(0, "LBL_AUTOBOT_BADGE", OBJPROP_TEXT, "🤖 AUTO-PILOT NEWS ROBOT: ACTIVE");
      ObjectSetInteger(0, "LBL_AUTOBOT_BADGE", OBJPROP_COLOR, C'52,211,153'); // Emerald Green
      if(g_barcodePending)
      {
         ObjectSetString(0, "LBL_AUTOBOT_SIGNAL", OBJPROP_TEXT, StringFormat("⏳ POST-SPIKE BARCODE ARMED: Firing Wave %d/%d...", g_wavesFired + 1, InpBarcodeWaveCount));
         ObjectSetInteger(0, "LBL_AUTOBOT_SIGNAL", OBJPROP_COLOR, C'251,191,36'); // Amber Yellow
      }
      else
      {
         ObjectSetString(0, "LBL_AUTOBOT_SIGNAL", OBJPROP_TEXT, StringFormat("Ready for release: 10 Limits (%d%% Margin) + %d Barcode Waves", (int)InpMarginPercent, InpBarcodeWaveCount));
         ObjectSetInteger(0, "LBL_AUTOBOT_SIGNAL", OBJPROP_COLOR, C'148,163,184');
      }
   }
   else
   {
      ObjectSetString(0, "LBL_AUTOBOT_BADGE", OBJPROP_TEXT, "✋ AUTO-PILOT DISABLED: MANUAL ONLY");
      ObjectSetInteger(0, "LBL_AUTOBOT_BADGE", OBJPROP_COLOR, C'248,113,113'); // Red
      ObjectSetString(0, "LBL_AUTOBOT_SIGNAL", OBJPROP_TEXT, "Use B/S or K/L hotkeys to trade manually");
      ObjectSetInteger(0, "LBL_AUTOBOT_SIGNAL", OBJPROP_COLOR, C'148,163,184');
   }

   string info = StringFormat("Stripe: %.2f | 70%% Wick Offset: $%.0f (%d p) | Target TP: +$%.0f (%d p)", 
                              g_currentLot, g_activeSpikeOffset, (int)(g_activeSpikeOffset*10), g_activeTPDist, (int)(g_activeTPDist*10));
   ObjectSetString(0, "LBL_STATUS", OBJPROP_TEXT, info);
   ChartRedraw(0);
}

int OnInit()
{
   trade.SetExpertMagicNumber(999111);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   g_currentLot = InpDefaultLot;

   DrawHUD();
   UpdateHUDStatus();
   EventSetMillisecondTimer(250); // Ultra-fast 250ms reaction cycle
   PrintFormat(">>> NEWS TERMINAL 5.00 ACTIVE: Calibrated Wick Limits & Dynamic TP Running! <<<");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectDelete(0, "BOX_AUTOBOT_BG");
   ObjectDelete(0, "LBL_AUTOBOT_BADGE");
   ObjectDelete(0, "LBL_AUTOBOT_SIGNAL");
   ObjectDelete(0, "BTN_LOT_MINUS");
   ObjectDelete(0, "EDT_LOT_SIZE");
   ObjectDelete(0, "BTN_LOT_PLUS");
   ObjectDelete(0, "BTN_LOT_001");
   ObjectDelete(0, "BTN_LOT_005");
   ObjectDelete(0, "BTN_LOT_010");
   ObjectDelete(0, "BTN_LOT_020");
   ObjectDelete(0, "BTN_BUY");
   ObjectDelete(0, "BTN_SELL");
   ObjectDelete(0, "BTN_KLIMIT");
   ObjectDelete(0, "BTN_LLIMIT");
   ObjectDelete(0, "BTN_CLOSE");
   ObjectDelete(0, "LBL_STATUS");
   ChartRedraw(0);
}

void OnTimer()
{
   UpdateHUDStatus();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == "BTN_LOT_PLUS")
      {
         g_currentLot = NormalizeDouble(g_currentLot + 0.01, 2);
         ObjectSetString(0, "EDT_LOT_SIZE", OBJPROP_TEXT, DoubleToString(g_currentLot, 2));
         ObjectSetInteger(0, "BTN_LOT_PLUS", OBJPROP_STATE, false);
      }
      else if(sparam == "BTN_LOT_MINUS")
      {
         if(g_currentLot > 0.01) g_currentLot = NormalizeDouble(g_currentLot - 0.01, 2);
         ObjectSetString(0, "EDT_LOT_SIZE", OBJPROP_TEXT, DoubleToString(g_currentLot, 2));
         ObjectSetInteger(0, "BTN_LOT_MINUS", OBJPROP_STATE, false);
      }
      else if(sparam == "BTN_LOT_001") { g_currentLot = 0.01; ObjectSetString(0, "EDT_LOT_SIZE", OBJPROP_TEXT, "0.01"); ObjectSetInteger(0, sparam, OBJPROP_STATE, false); }
      else if(sparam == "BTN_LOT_005") { g_currentLot = 0.05; ObjectSetString(0, "EDT_LOT_SIZE", OBJPROP_TEXT, "0.05"); ObjectSetInteger(0, sparam, OBJPROP_STATE, false); }
      else if(sparam == "BTN_LOT_010") { g_currentLot = 0.10; ObjectSetString(0, "EDT_LOT_SIZE", OBJPROP_TEXT, "0.10"); ObjectSetInteger(0, sparam, OBJPROP_STATE, false); }
      else if(sparam == "BTN_LOT_020") { g_currentLot = 0.20; ObjectSetString(0, "EDT_LOT_SIZE", OBJPROP_TEXT, "0.20"); ObjectSetInteger(0, sparam, OBJPROP_STATE, false); }
      else if(sparam == "BTN_BUY")
      {
         ExecuteBarcode(ORDER_TYPE_BUY);
         ObjectSetInteger(0, "BTN_BUY", OBJPROP_STATE, false);
      }
      else if(sparam == "BTN_SELL")
      {
         ExecuteBarcode(ORDER_TYPE_SELL);
         ObjectSetInteger(0, "BTN_SELL", OBJPROP_STATE, false);
      }
      else if(sparam == "BTN_KLIMIT")
      {
         ArmSpikeLimits(ORDER_TYPE_BUY_LIMIT);
         ObjectSetInteger(0, "BTN_KLIMIT", OBJPROP_STATE, false);
      }
      else if(sparam == "BTN_LLIMIT")
      {
         ArmSpikeLimits(ORDER_TYPE_SELL_LIMIT);
         ObjectSetInteger(0, "BTN_LLIMIT", OBJPROP_STATE, false);
      }
      else if(sparam == "BTN_CLOSE")
      {
         ExecuteEmergencyClose();
         ObjectSetInteger(0, "BTN_CLOSE", OBJPROP_STATE, false);
      }
      UpdateHUDStatus();
   }

   if(id == CHARTEVENT_OBJECT_ENDEDIT && sparam == "EDT_LOT_SIZE")
   {
      UpdateHUDStatus();
   }

   if(id == CHARTEVENT_KEYDOWN)
   {
      if(lparam == 83 || lparam == 115) ExecuteBarcode(ORDER_TYPE_SELL); // S
      else if(lparam == 66 || lparam == 98) ExecuteBarcode(ORDER_TYPE_BUY); // B
      else if(lparam == 76 || lparam == 108) ArmSpikeLimits(ORDER_TYPE_SELL_LIMIT); // L
      else if(lparam == 75 || lparam == 107) ArmSpikeLimits(ORDER_TYPE_BUY_LIMIT); // K
      else if(lparam == 88 || lparam == 120) ExecuteEmergencyClose(); // X
   }
}

bool CanAffordBarcode(ENUM_ORDER_TYPE orderType, double &outLotPerStripe)
{
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double leverage = (double)AccountInfoInteger(ACCOUNT_LEVERAGE);
   if(leverage <= 0) leverage = 100.0;

   // 70% of currently available free margin
   double targetMargin = freeMargin * (MathMin(InpMarginPercent, 95.0) / 100.0);
   double price = (orderType == ORDER_TYPE_SELL) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double marginForOneLot = 0.0;

   if(!OrderCalcMargin(orderType, _Symbol, 1.0, price, marginForOneLot) || marginForOneLot <= 0)
   {
      marginForOneLot = (price * 100.0) / leverage;
   }

   double totalLots = targetMargin / marginForOneLot;
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotStep <= 0) lotStep = 0.01;
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(minLot <= 0) minLot = 0.01;

   // Divide into InpNumberOfStripes (default 10 stripes)
   int numStripes = (InpNumberOfStripes > 0) ? InpNumberOfStripes : 10;
   double lotPerStripe = MathFloor((totalLots / (double)numStripes) / lotStep) * lotStep;

   // If 70% of margin can afford at least 10x minLot (e.g. 10 x 0.01 = 0.10 lot total)
   if(lotPerStripe >= minLot)
   {
      outLotPerStripe = NormalizeDouble(lotPerStripe, 2);
      return true;
   }
   
   // If not enough for 10 stripes, check if free margin can at least afford 1 stripe of minLot
   if(freeMargin >= (marginForOneLot * minLot * 1.5))
   {
      outLotPerStripe = minLot;
      return true;
   }

   return false;
}

void ExecuteBarcode(ENUM_ORDER_TYPE orderType, double customLot = 0.0)
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double lotToUse = (customLot > 0.0) ? customLot : g_currentLot;

   int filled = 0;
   for(int i = 0; i < InpNumberOfStripes; i++)
   {
      // Check free margin before each stripe to prevent margin rejection
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(freeMargin <= 5.0) break; // Leave safety buffer

      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if(orderType == ORDER_TYPE_SELL)
      {
         double tp = (g_activeTPDist > 0) ? NormalizeDouble(bid - g_activeTPDist, digits) : 0.0;
         if(trade.Sell(lotToUse, _Symbol, bid, 0.0, tp, "Barcode Stripe")) filled++;
      }
      else
      {
         double tp = (g_activeTPDist > 0) ? NormalizeDouble(ask + g_activeTPDist, digits) : 0.0;
         if(trade.Buy(lotToUse, _Symbol, ask, 0.0, tp, "Barcode Stripe")) filled++;
      }
      Sleep(20);
   }
   PrintFormat("✅ BARCODE EXECUTED: %d/%d stripes filled at %.2f lots on %s (TP: +$%.2f [%d pips])", 
               filled, InpNumberOfStripes, lotToUse, _Symbol, g_activeTPDist, (int)(g_activeTPDist*10));
}

void ArmSpikeLimits(ENUM_ORDER_TYPE orderType)
{
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double leverage = (double)AccountInfoInteger(ACCOUNT_LEVERAGE);
   if(leverage <= 0) leverage = 100.0;

   double targetMargin = freeMargin * (MathMin(InpMarginPercent, 95.0) / 100.0);
   double marginForOneLot = 0.0;
   if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, 1.0, SymbolInfoDouble(_Symbol, SYMBOL_ASK), marginForOneLot) || marginForOneLot <= 0)
   {
      marginForOneLot = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) * 100.0) / leverage;
   }

   double totalLots = targetMargin / marginForOneLot;
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotStep <= 0) lotStep = 0.01;
   totalLots = MathFloor(totalLots / lotStep) * lotStep;
   totalLots = MathMax(totalLots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));

   int numStripes = (InpNumberOfLimitStripes > 0) ? InpNumberOfLimitStripes : 10;
   double stripeLot = NormalizeDouble(totalLots / (double)numStripes, 2);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   if(stripeLot < minLot) stripeLot = minLot;
   if(stripeLot > maxLot) stripeLot = maxLot;
   
   // Snap to broker volume step
   stripeLot = MathFloor(stripeLot / lotStep) * lotStep;
   if(stripeLot < minLot) stripeLot = minLot;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   datetime expiry = TimeCurrent() + (InpLimitExpiryMins * 60);

   int placed = 0;
   for(int i = 0; i < numStripes; i++)
   {
      // Tightly laddered around the empirical wick depth (+- InpLadderStep per order)
      double offset = g_activeSpikeOffset + ((double)i * InpLadderStep);
      if(orderType == ORDER_TYPE_SELL_LIMIT)
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double p = NormalizeDouble(ask + offset, digits);
         double tp = (g_activeTPDist > 0) ? NormalizeDouble(p - g_activeTPDist, digits) : 0.0;
         if(trade.SellLimit(stripeLot, p, _Symbol, 0.0, tp, ORDER_TIME_SPECIFIED, expiry, "Spike Sell Limit")) placed++;
      }
      else
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double p = NormalizeDouble(bid - offset, digits);
         double tp = (g_activeTPDist > 0) ? NormalizeDouble(p + g_activeTPDist, digits) : 0.0;
         if(trade.BuyLimit(stripeLot, p, _Symbol, 0.0, tp, ORDER_TIME_SPECIFIED, expiry, "Spike Buy Limit")) placed++;
      }
      Sleep(10);
   }
   PrintFormat("✅ SPIKE LIMITS ARMED on %s: %d/%d orders placed at %.2f lots each (Total: ~%.2f lots, Base Wick Offset: $%.2f, Step: $%.2f, TP: +$%.2f)", 
               _Symbol, placed, numStripes, stripeLot, (stripeLot * placed), g_activeSpikeOffset, InpLadderStep, g_activeTPDist);
}

void ExecuteEmergencyClose()
{
   int total = PositionsTotal();
   if(total == 0 && OrdersTotal() == 0) return;

   // 1. Collect all position tickets first into memory
   ulong posTickets[];
   ArrayResize(posTickets, total);
   int posCount = 0;
   for(int i = total - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t > 0)
      {
         posTickets[posCount] = t;
         posCount++;
      }
   }

   // 2. Delete all pending limit orders immediately
   int orders = OrdersTotal();
   for(int i = orders - 1; i >= 0; i--)
   {
      ulong oticket = OrderGetTicket(i);
      if(oticket > 0) trade.OrderDelete(oticket);
   }

   // 3. Fire non-blocking asynchronous close orders in parallel to broker bridge
   int fired = 0;
   for(int i = 0; i < posCount; i++)
   {
      ulong ticket = posTickets[i];
      if(!PositionSelectByTicket(ticket)) continue;

      ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double volume = PositionGetDouble(POSITION_VOLUME);
      string sym = PositionGetString(POSITION_SYMBOL);

      MqlTradeRequest request;
      MqlTradeResult result;
      ZeroMemory(request);
      ZeroMemory(result);

      request.action       = TRADE_ACTION_DEAL;
      request.position     = ticket;
      request.symbol       = sym;
      request.volume       = volume;
      request.deviation    = InpSlippagePoints;
      request.type_filling = ORDER_FILLING_IOC;

      if(ptype == POSITION_TYPE_BUY)
      {
         request.type  = ORDER_TYPE_SELL;
         request.price = SymbolInfoDouble(sym, SYMBOL_BID);
      }
      else
      {
         request.type  = ORDER_TYPE_BUY;
         request.price = SymbolInfoDouble(sym, SYMBOL_ASK);
      }

      // Parallel async dispatch: does NOT wait or sleep between orders
      if(OrderSendAsync(request, result))
      {
         fired++;
      }
      else
      {
         // Fallback sync close if async unsupported by broker
         trade.PositionClose(ticket, InpSlippagePoints);
         fired++;
      }
   }

   PrintFormat("⚡ NON-BLOCKING KILL SWITCH: %d close orders broadcast instantly to broker on %s!", fired, _Symbol);
}
