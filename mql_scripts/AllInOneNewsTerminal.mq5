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
input double   InpFallbackTPDist    = 55.0;    // Fallback Take Profit in Gold $ ($55.00 = 550 pips)

input group "=== STRADDLE BREAKOUT BARCODE (G KEY) ===";
input double   InpStopDistancePips  = 50.0;    // Breakout Distance in Pips (50 pips = $5.00 on Gold)
input double   InpStopTPDistancePips= 550.0;   // Take Profit in Pips (550 pips = $55.00 on Gold)
input double   InpStopSLDistancePips= 0.0;     // Stop Loss in Pips (0 for none)
input int      InpStopExpiryMins    = 15;      // Auto-disarm watch after N minutes (0 for no timeout)

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

input group "=== UI CUSTOMIZATION ===";
input double   InpUIScale           = 1.0;     // UI Scale Multiplier (1.0 = Standard, 1.2 = Large, 1.5 = 4K)
input int      InpStartX            = 20;      // Panel X Position on Chart
input int      InpStartY            = 30;      // Panel Y Position on Chart

CTrade trade;
double g_currentLot = 0.05;
int    g_currentStripes = 10;
string g_activeNewsName = "Standby (Normal)";
double g_activeSpikeOffset = 18.00; // in Gold dollars ($18.00 = 180 pips)
double g_activeTPDist = 55.00;      // in Gold dollars ($55.00 = 550 pips)
string g_activeTier = "STANDARD";

// Auto-pilot state tracking
ulong  g_lastTradedValueId = 0;
datetime g_signalTriggerTime = 0;
datetime g_lastWaveTime = 0;
int    g_wavesFired = 0;
ENUM_ORDER_TYPE g_pendingBarcodeType = WRONG_VALUE;
bool   g_barcodePending = false;

// Breakout Watch (G key) state tracking
bool     g_straddleArmed = false;
double   g_straddleBuyTrigger = 0.0;
double   g_straddleSellTrigger = 0.0;
datetime g_straddleArmTime = 0;

// Continuous Multi-Wave Barcode Engine (Adds stripes dynamically as margin expands)
bool            g_barcodeActive = false;
ENUM_ORDER_TYPE g_barcodeType   = WRONG_VALUE;
int             g_barcodeTarget = 0;
int             g_barcodeFilled = 0;
int             g_barcodeBaseOpenCount = 0;
datetime        g_barcodeStartTime = 0;
datetime        g_barcodeLastFireTime = 0;

int  GetBarcodePositionsCount(ENUM_POSITION_TYPE targetPosType = WRONG_VALUE);
void ExecuteBarcode(ENUM_ORDER_TYPE orderType, double customLot = 0.0);
void StartBarcodeEngine(ENUM_ORDER_TYPE orderType, int targetStripes, double lot);
void ProcessBarcodeEngine();
void ArmSpikeLimits(ENUM_ORDER_TYPE orderType);
void ExecuteStraddleStops();
void ToggleStraddleWatch();
void ArmStraddleWatch();
void DisarmStraddleWatch();
void CheckStraddleBreakout();
bool CanAffordBarcode(ENUM_ORDER_TYPE orderType, double &outLotPerStripe);
double GetPipSize();
ENUM_ORDER_TYPE_FILLING GetFillingMode();

void CreateButton(string name, string text, int x, int y, int w, int h, color bg, color fg, int fontSize = 10, color border = clrNONE)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI Bold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, fg);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void CreateEditBox(string name, string text, int x, int y, int w, int h, int fontSize = 12)
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
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, C'15,23,42');
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, C'51,65,85');
   ObjectSetInteger(0, name, OBJPROP_ALIGN, ALIGN_CENTER);
}

void DrawHUD()
{
   double scale = (InpUIScale >= 0.7 && InpUIScale <= 3.0) ? InpUIScale : 1.0;
   int startX = InpStartX;
   int startY = InpStartY;
   int pad  = (int)(22 * scale);
   int gapX = (int)(10 * scale);
   int gapY = (int)(16 * scale);

   int totalW = (int)(560 * scale);
   int btnW   = (totalW - gapX) / 2;

   int fsTitle = MathMax(8, (int)(10 * scale));
   int fsSub   = MathMax(8, (int)(9 * scale));
   int fsBtn   = MathMax(8, (int)(10 * scale));
   int fsLot   = MathMax(9, (int)(11 * scale));
   int fsSmall = MathMax(8, (int)(9 * scale));
   int fsStatus= MathMax(8, (int)(9 * scale));

   // Calculate Vertical Offsets with generous vertical spacing from top to bottom
   int r0_title_y = startY + (int)(6 * scale);
   int r0_sub_y   = startY + (int)(30 * scale);

   int r1_y   = startY + (int)(64 * scale);
   int r1_h   = (int)(38 * scale);

   int r2_y   = r1_y + r1_h + gapY;
   int r2_h   = (int)(36 * scale);

   int r3_y   = r2_y + r2_h + gapY + (int)(4 * scale);
   int r3_h   = (int)(46 * scale);

   int r4_y   = r3_y + r3_h + gapY;
   int r4_h   = (int)(44 * scale);

   int r5_y   = r4_y + r4_h + gapY;
   int r5_h   = (int)(44 * scale);

   int r6_y   = r5_y + r5_h + gapY + (int)(4 * scale);
   int r6_h   = (int)(46 * scale);

   int r7_y   = r6_y + r6_h + (int)(18 * scale);
   int totalH = (r7_y - startY) + (int)(22 * scale) + pad;

   // Purge legacy elements
   ObjectDelete(0, "BTN_TEST_BUY");
   ObjectDelete(0, "BTN_TEST_SELL");
   ObjectDelete(0, "BOX_AUTOBOT_BG"); // Remove awkward inner box

   // Background Container Card: guarantees sleek, high-contrast dark card on ANY chart color
   ObjectDelete(0, "BOX_MAIN_BG");
   ObjectCreate(0, "BOX_MAIN_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "BOX_MAIN_BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "BOX_MAIN_BG", OBJPROP_XDISTANCE, startX - pad);
   ObjectSetInteger(0, "BOX_MAIN_BG", OBJPROP_YDISTANCE, startY - pad);
   ObjectSetInteger(0, "BOX_MAIN_BG", OBJPROP_XSIZE, totalW + (pad * 2));
   ObjectSetInteger(0, "BOX_MAIN_BG", OBJPROP_YSIZE, totalH);
   ObjectSetInteger(0, "BOX_MAIN_BG", OBJPROP_BGCOLOR, C'16,22,34'); // Deep sleek midnight slate
   ObjectSetInteger(0, "BOX_MAIN_BG", OBJPROP_BORDER_COLOR, C'51,65,85'); // Crisp border
   ObjectSetInteger(0, "BOX_MAIN_BG", OBJPROP_SELECTABLE, false);

   // Row 0: Header Text (Sits cleanly on container card with plenty of room)
   ObjectDelete(0, "LBL_AUTOBOT_BADGE");
   ObjectCreate(0, "LBL_AUTOBOT_BADGE", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "LBL_AUTOBOT_BADGE", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "LBL_AUTOBOT_BADGE", OBJPROP_XDISTANCE, startX);
   ObjectSetInteger(0, "LBL_AUTOBOT_BADGE", OBJPROP_YDISTANCE, r0_title_y);
   ObjectSetString(0, "LBL_AUTOBOT_BADGE", OBJPROP_FONT, "Segoe UI Bold");
   ObjectSetInteger(0, "LBL_AUTOBOT_BADGE", OBJPROP_FONTSIZE, fsTitle);
   if(InpEnableAutoPilot)
   {
      ObjectSetString(0, "LBL_AUTOBOT_BADGE", OBJPROP_TEXT, "[ON] AUTO-PILOT TRADING BOT: ACTIVE");
      ObjectSetInteger(0, "LBL_AUTOBOT_BADGE", OBJPROP_COLOR, C'52,211,153'); // Emerald green
   }
   else
   {
      ObjectSetString(0, "LBL_AUTOBOT_BADGE", OBJPROP_TEXT, "[OFF] AUTO-PILOT DISABLED: MANUAL ONLY");
      ObjectSetInteger(0, "LBL_AUTOBOT_BADGE", OBJPROP_COLOR, C'248,113,113'); // Coral red
   }

   ObjectDelete(0, "LBL_AUTOBOT_SIGNAL");
   ObjectCreate(0, "LBL_AUTOBOT_SIGNAL", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "LBL_AUTOBOT_SIGNAL", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "LBL_AUTOBOT_SIGNAL", OBJPROP_XDISTANCE, startX);
   ObjectSetInteger(0, "LBL_AUTOBOT_SIGNAL", OBJPROP_YDISTANCE, r0_sub_y);
   ObjectSetString(0, "LBL_AUTOBOT_SIGNAL", OBJPROP_FONT, "Segoe UI");
   ObjectSetInteger(0, "LBL_AUTOBOT_SIGNAL", OBJPROP_FONTSIZE, fsSub);
   if(InpEnableAutoPilot)
   {
      ObjectSetString(0, "LBL_AUTOBOT_SIGNAL", OBJPROP_TEXT, "Waiting for release | 10 Limits + 2 Barcode Waves Armed");
      ObjectSetInteger(0, "LBL_AUTOBOT_SIGNAL", OBJPROP_COLOR, C'148,163,184');
   }
   else
   {
      ObjectSetString(0, "LBL_AUTOBOT_SIGNAL", OBJPROP_TEXT, "Use B/S, K/L, or G hotkeys to trade manually");
      ObjectSetInteger(0, "LBL_AUTOBOT_SIGNAL", OBJPROP_COLOR, C'148,163,184');
   }

   // Row 1: Lot Selector & Presets
   int btnMinusW = (int)(38 * scale);
   int edtLotW   = (int)(80 * scale);
   int btnPlusW  = (int)(38 * scale);
   CreateButton("BTN_LOT_MINUS", "-", startX, r1_y, btnMinusW, r1_h, C'30,41,59', clrWhite, fsLot, C'51,65,85');
   CreateEditBox("EDT_LOT_SIZE", DoubleToString(g_currentLot, 2), startX + btnMinusW + 4, r1_y, edtLotW, r1_h, fsLot);
   CreateButton("BTN_LOT_PLUS", "+", startX + btnMinusW + edtLotW + 8, r1_y, btnPlusW, r1_h, C'30,41,59', clrWhite, fsLot, C'51,65,85');

   int lotCurX = startX + btnMinusW + edtLotW + btnPlusW + (int)(16 * scale);
   int remLotW = (startX + totalW) - lotCurX;
   int lotPresetW = (remLotW - (3 * gapX)) / 4;
   CreateButton("BTN_LOT_001", ".01", lotCurX,                               r1_y, lotPresetW, r1_h, C'30,41,59', C'203,213,225', fsSmall, C'51,65,85');
   CreateButton("BTN_LOT_005", ".05", lotCurX + lotPresetW + gapX,             r1_y, lotPresetW, r1_h, C'30,41,59', C'203,213,225', fsSmall, C'51,65,85');
   CreateButton("BTN_LOT_010", ".10", lotCurX + (lotPresetW + gapX) * 2,       r1_y, lotPresetW, r1_h, C'30,41,59', C'203,213,225', fsSmall, C'51,65,85');
   int lastLotW = (startX + totalW) - (lotCurX + (lotPresetW + gapX) * 3);
   CreateButton("BTN_LOT_020", ".20", lotCurX + (lotPresetW + gapX) * 3,       r1_y, lastLotW,   r1_h, C'30,41,59', C'203,213,225', fsSmall, C'51,65,85');

   // Row 2: Stripes Selector (10, 20, 30, 40, 50, 100)
   int strBtnW = (totalW - (5 * gapX)) / 6;
   CreateButton("BTN_STRIPES_10",  "10x",  startX,                        r2_y, strBtnW, r2_h, C'30,41,59', C'203,213,225', fsSmall, C'51,65,85');
   CreateButton("BTN_STRIPES_20",  "20x",  startX + (strBtnW + gapX),     r2_y, strBtnW, r2_h, C'30,41,59', C'203,213,225', fsSmall, C'51,65,85');
   CreateButton("BTN_STRIPES_30",  "30x",  startX + (strBtnW + gapX) * 2, r2_y, strBtnW, r2_h, C'30,41,59', C'203,213,225', fsSmall, C'51,65,85');
   CreateButton("BTN_STRIPES_40",  "40x",  startX + (strBtnW + gapX) * 3, r2_y, strBtnW, r2_h, C'30,41,59', C'203,213,225', fsSmall, C'51,65,85');
   CreateButton("BTN_STRIPES_50",  "50x",  startX + (strBtnW + gapX) * 4, r2_y, strBtnW, r2_h, C'30,41,59', C'203,213,225', fsSmall, C'51,65,85');
   int lastStrW = (startX + totalW) - (startX + (strBtnW + gapX) * 5);
   CreateButton("BTN_STRIPES_100", "100x", startX + (strBtnW + gapX) * 5, r2_y, lastStrW, r2_h, C'30,41,59', C'203,213,225', fsSmall, C'51,65,85');

   // Row 3: Barcode Buy/Sell Buttons
   CreateButton("BTN_BUY",  "BUY BARCODE [B]",  startX,             r3_y, btnW, r3_h, C'22,101,52', clrWhite, fsBtn, C'34,197,94');
   CreateButton("BTN_SELL", "SELL BARCODE [S]", startX + btnW + gapX, r3_y, btnW, r3_h, C'153,27,27', clrWhite, fsBtn, C'239,68,68');

   // Row 4: Limit Sniper Buttons (with K and L keys explicitly labelled)
   string kTxt = StringFormat("K: BUY LIMIT (-$%.0f)", g_activeSpikeOffset);
   string lTxt = StringFormat("L: SELL LIMIT (+$%.0f)", g_activeSpikeOffset);
   CreateButton("BTN_KLIMIT", kTxt, startX,             r4_y, btnW, r4_h, C'12,74,110', C'56,189,248', fsBtn, C'14,116,144');
   CreateButton("BTN_LLIMIT", lTxt, startX + btnW + gapX, r4_y, btnW, r4_h, C'127,29,29', C'248,113,113', fsBtn, C'185,28,28');

   // Row 5: Straddle Stops (G key)
   string straddleTxt = StringFormat("STRADDLE BREAKOUT BARCODE [G] (±%.0f p)", InpStopDistancePips);
   CreateButton("BTN_STRADDLE", straddleTxt, startX, r5_y, totalW, r5_h, C'66,50,15', C'250,204,21', fsBtn, C'161,98,7');

   // Row 6: Panic Close Kill Switch
   CreateButton("BTN_CLOSE", "[X] PANIC CLOSE ALL POSITIONS", startX, r6_y, totalW, r6_h, C'185,28,28', clrWhite, fsBtn, C'220,38,38');

   // Row 7: Dynamic Intelligence Display
   ObjectDelete(0, "LBL_STATUS");
   ObjectCreate(0, "LBL_STATUS", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "LBL_STATUS", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "LBL_STATUS", OBJPROP_XDISTANCE, startX);
   ObjectSetInteger(0, "LBL_STATUS", OBJPROP_YDISTANCE, r7_y);
   ObjectSetString(0, "LBL_STATUS", OBJPROP_FONT, "Segoe UI");
   ObjectSetInteger(0, "LBL_STATUS", OBJPROP_FONTSIZE, fsStatus);
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
               if(StringFind(low, "fomc") >= 0 || StringFind(low, "interest rate") >= 0 || 
                  StringFind(low, "federal funds") >= 0 || StringFind(low, "fed funds") >= 0 ||
                  StringFind(low, "cpi") >= 0 || StringFind(low, "consumer price") >= 0 ||
                  StringFind(low, "nonfarm") >= 0 || StringFind(low, "non farm") >= 0)
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
                  if(StringFind(low, "fomc") >= 0 || StringFind(low, "interest rate") >= 0 || 
                     StringFind(low, "federal funds") >= 0 || StringFind(low, "fed funds") >= 0 ||
                     StringFind(low, "cpi") >= 0 || StringFind(low, "consumer price") >= 0 ||
                     StringFind(low, "nonfarm") >= 0 || StringFind(low, "non farm") >= 0)
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

            if(StringFind(low, "interest rate") >= 0 || StringFind(low, "fomc") >= 0 || 
               StringFind(low, "federal funds") >= 0 || StringFind(low, "fed funds") >= 0)
            {
               g_activeNewsName = "FOMC Rate Decision";
               g_activeTier = "BLOWOUT"; 
               g_activeSpikeOffset = 22.0; // 220 pip manipulation wick limit
               g_activeTPDist = 55.0;      // 550 pip ($55.00) TP target
               isTarget = true;
            }
            else if(StringFind(low, "nonfarm") >= 0 || StringFind(low, "non farm") >= 0)
            {
               g_activeNewsName = "Nonfarm Payrolls (NFP)";
               if(diff > 68.0)      { g_activeTier = "BLOWOUT"; g_activeSpikeOffset = 25.0; g_activeTPDist = 55.0; }
               else if(diff > 30.0) { g_activeTier = "SOLID";   g_activeSpikeOffset = 20.0; g_activeTPDist = 55.0; }
               else                 { g_activeTier = "MODEST";  g_activeSpikeOffset = 18.0; g_activeTPDist = 55.0; }
               isTarget = true;
            }
            else if(StringFind(low, "cpi") >= 0 || StringFind(low, "consumer price") >= 0)
            {
               g_activeNewsName = "Consumer Price Index (CPI)";
               if(diff > 0.25)      { g_activeTier = "BLOWOUT"; g_activeSpikeOffset = 22.0; g_activeTPDist = 55.0; }
               else if(diff > 0.12) { g_activeTier = "SOLID";   g_activeSpikeOffset = 16.0; g_activeTPDist = 55.0; }
               else                 { g_activeTier = "MODEST";  g_activeSpikeOffset = 12.0; g_activeTPDist = 55.0; }
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

   // Update Limit button texts with live calibrated spike wick distances (K and L hotkeys)
   ObjectSetString(0, "BTN_KLIMIT", OBJPROP_TEXT, StringFormat("K: BUY LIMIT (-$%.0f)", g_activeSpikeOffset));
   ObjectSetString(0, "BTN_LLIMIT", OBJPROP_TEXT, StringFormat("L: SELL LIMIT (+$%.0f)", g_activeSpikeOffset));

   if(InpEnableAutoPilot)
   {
      ObjectSetString(0, "LBL_AUTOBOT_BADGE", OBJPROP_TEXT, "[ON] AUTO-PILOT TRADING BOT: ACTIVE");
      ObjectSetInteger(0, "LBL_AUTOBOT_BADGE", OBJPROP_COLOR, C'52,211,153'); // Emerald Green
      if(g_barcodePending)
      {
         ObjectSetString(0, "LBL_AUTOBOT_SIGNAL", OBJPROP_TEXT, StringFormat("POST-SPIKE BARCODE ARMED: Firing Wave %d/%d...", g_wavesFired + 1, InpBarcodeWaveCount));
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
      ObjectSetString(0, "LBL_AUTOBOT_BADGE", OBJPROP_TEXT, "[OFF] AUTO-PILOT DISABLED: MANUAL ONLY");
      ObjectSetInteger(0, "LBL_AUTOBOT_BADGE", OBJPROP_COLOR, C'248,113,113'); // Coral Red
      ObjectSetString(0, "LBL_AUTOBOT_SIGNAL", OBJPROP_TEXT, "Use B/S, K/L, or G hotkeys to trade manually");
      ObjectSetInteger(0, "LBL_AUTOBOT_SIGNAL", OBJPROP_COLOR, C'148,163,184');
   }

   if(g_barcodeActive)
   {
      ENUM_POSITION_TYPE targetPosType = (g_barcodeType == ORDER_TYPE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      int liveStripes = GetBarcodePositionsCount(targetPosType);
      string dirStr = (g_barcodeType == ORDER_TYPE_BUY) ? "BUY" : "SELL";
      string info = StringFormat("⚡ FILLING %s: %d/%d open | Free Margin: $%.1f | TP: +$%.0f", 
                                 dirStr, liveStripes, g_barcodeTarget, AccountInfoDouble(ACCOUNT_MARGIN_FREE), g_activeTPDist);
      ObjectSetString(0, "LBL_STATUS", OBJPROP_TEXT, info);
      ObjectSetInteger(0, "LBL_STATUS", OBJPROP_COLOR, C'250,204,21'); // Amber yellow
   }
   else
   {
      string info = StringFormat("Stripes: %dx %.2f | Wick: $%.0f (%dp) | Target TP: +$%.0f (%dp)", 
                                 g_currentStripes, g_currentLot, g_activeSpikeOffset, (int)(g_activeSpikeOffset*10), g_activeTPDist, (int)(g_activeTPDist*10));
      ObjectSetString(0, "LBL_STATUS", OBJPROP_TEXT, info);
      ObjectSetInteger(0, "LBL_STATUS", OBJPROP_COLOR, C'148,163,184');
   }

   // Buy / Sell button labels - Clean, exact match to Image 3
   ObjectSetString(0, "BTN_BUY", OBJPROP_TEXT, "BUY BARCODE [B]");
   ObjectSetString(0, "BTN_SELL", OBJPROP_TEXT, "SELL BARCODE [S]");
   ObjectSetString(0, "BTN_CLOSE", OBJPROP_TEXT, "[X] PANIC CLOSE ALL POSITIONS");

   // Straddle Breakout Watch Button Appearance
   if(g_straddleArmed)
   {
      ObjectSetString(0, "BTN_STRADDLE", OBJPROP_TEXT, StringFormat("⚡ ARMED: BREAKOUT WATCH [G] (±%.0f p)", InpStopDistancePips));
      ObjectSetInteger(0, "BTN_STRADDLE", OBJPROP_BGCOLOR, C'202,138,4'); // Vibrant Gold Amber
      ObjectSetInteger(0, "BTN_STRADDLE", OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, "BTN_STRADDLE", OBJPROP_BORDER_COLOR, C'250,204,21'); // Bright yellow border
   }
   else
   {
      ObjectSetString(0, "BTN_STRADDLE", OBJPROP_TEXT, StringFormat("STRADDLE BREAKOUT BARCODE [G] (±%.0f p)", InpStopDistancePips));
      ObjectSetInteger(0, "BTN_STRADDLE", OBJPROP_BGCOLOR, C'66,50,15'); // Dark Bronze
      ObjectSetInteger(0, "BTN_STRADDLE", OBJPROP_COLOR, C'250,204,21');
      ObjectSetInteger(0, "BTN_STRADDLE", OBJPROP_BORDER_COLOR, C'161,98,7');
   }

   // Active button colors
   color activeBg       = C'2,132,199';   // Vibrant Sky Blue
   color activeFg       = clrWhite;
   color activeBorder   = C'56,189,248';  // Light Sky Border
   color inactiveBg     = C'30,41,59';    // Dark Slate
   color inactiveFg     = C'203,213,225';  // Slate-300
   color inactiveBorder = C'51,65,85';    // Slate-700

   // Lot Presets highlight
   bool is001 = (MathAbs(g_currentLot - 0.01) < 0.005);
   bool is005 = (MathAbs(g_currentLot - 0.05) < 0.005);
   bool is010 = (MathAbs(g_currentLot - 0.10) < 0.005);
   bool is020 = (MathAbs(g_currentLot - 0.20) < 0.005);
   ObjectSetInteger(0, "BTN_LOT_001", OBJPROP_BGCOLOR, is001 ? activeBg : inactiveBg);
   ObjectSetInteger(0, "BTN_LOT_001", OBJPROP_COLOR,   is001 ? activeFg : inactiveFg);
   ObjectSetInteger(0, "BTN_LOT_001", OBJPROP_BORDER_COLOR, is001 ? activeBorder : inactiveBorder);

   ObjectSetInteger(0, "BTN_LOT_005", OBJPROP_BGCOLOR, is005 ? activeBg : inactiveBg);
   ObjectSetInteger(0, "BTN_LOT_005", OBJPROP_COLOR,   is005 ? activeFg : inactiveFg);
   ObjectSetInteger(0, "BTN_LOT_005", OBJPROP_BORDER_COLOR, is005 ? activeBorder : inactiveBorder);

   ObjectSetInteger(0, "BTN_LOT_010", OBJPROP_BGCOLOR, is010 ? activeBg : inactiveBg);
   ObjectSetInteger(0, "BTN_LOT_010", OBJPROP_COLOR,   is010 ? activeFg : inactiveFg);
   ObjectSetInteger(0, "BTN_LOT_010", OBJPROP_BORDER_COLOR, is010 ? activeBorder : inactiveBorder);

   ObjectSetInteger(0, "BTN_LOT_020", OBJPROP_BGCOLOR, is020 ? activeBg : inactiveBg);
   ObjectSetInteger(0, "BTN_LOT_020", OBJPROP_COLOR,   is020 ? activeFg : inactiveFg);
   ObjectSetInteger(0, "BTN_LOT_020", OBJPROP_BORDER_COLOR, is020 ? activeBorder : inactiveBorder);

   // Stripes Presets highlight
   ObjectSetInteger(0, "BTN_STRIPES_10",  OBJPROP_BGCOLOR, (g_currentStripes == 10)  ? activeBg : inactiveBg);
   ObjectSetInteger(0, "BTN_STRIPES_10",  OBJPROP_COLOR,   (g_currentStripes == 10)  ? activeFg : inactiveFg);
   ObjectSetInteger(0, "BTN_STRIPES_10",  OBJPROP_BORDER_COLOR, (g_currentStripes == 10)  ? activeBorder : inactiveBorder);

   ObjectSetInteger(0, "BTN_STRIPES_20",  OBJPROP_BGCOLOR, (g_currentStripes == 20)  ? activeBg : inactiveBg);
   ObjectSetInteger(0, "BTN_STRIPES_20",  OBJPROP_COLOR,   (g_currentStripes == 20)  ? activeFg : inactiveFg);
   ObjectSetInteger(0, "BTN_STRIPES_20",  OBJPROP_BORDER_COLOR, (g_currentStripes == 20)  ? activeBorder : inactiveBorder);

   ObjectSetInteger(0, "BTN_STRIPES_30",  OBJPROP_BGCOLOR, (g_currentStripes == 30)  ? activeBg : inactiveBg);
   ObjectSetInteger(0, "BTN_STRIPES_30",  OBJPROP_COLOR,   (g_currentStripes == 30)  ? activeFg : inactiveFg);
   ObjectSetInteger(0, "BTN_STRIPES_30",  OBJPROP_BORDER_COLOR, (g_currentStripes == 30)  ? activeBorder : inactiveBorder);

   ObjectSetInteger(0, "BTN_STRIPES_40",  OBJPROP_BGCOLOR, (g_currentStripes == 40)  ? activeBg : inactiveBg);
   ObjectSetInteger(0, "BTN_STRIPES_40",  OBJPROP_COLOR,   (g_currentStripes == 40)  ? activeFg : inactiveFg);
   ObjectSetInteger(0, "BTN_STRIPES_40",  OBJPROP_BORDER_COLOR, (g_currentStripes == 40)  ? activeBorder : inactiveBorder);

   ObjectSetInteger(0, "BTN_STRIPES_50",  OBJPROP_BGCOLOR, (g_currentStripes == 50)  ? activeBg : inactiveBg);
   ObjectSetInteger(0, "BTN_STRIPES_50",  OBJPROP_COLOR,   (g_currentStripes == 50)  ? activeFg : inactiveFg);
   ObjectSetInteger(0, "BTN_STRIPES_50",  OBJPROP_BORDER_COLOR, (g_currentStripes == 50)  ? activeBorder : inactiveBorder);

   ObjectSetInteger(0, "BTN_STRIPES_100", OBJPROP_BGCOLOR, (g_currentStripes == 100) ? activeBg : inactiveBg);
   ObjectSetInteger(0, "BTN_STRIPES_100", OBJPROP_COLOR,   (g_currentStripes == 100) ? activeFg : inactiveFg);
   ObjectSetInteger(0, "BTN_STRIPES_100", OBJPROP_BORDER_COLOR, (g_currentStripes == 100) ? activeBorder : inactiveBorder);

   ChartRedraw(0);
}

int OnInit()
{
   trade.SetExpertMagicNumber(999111);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFilling(GetFillingMode());
   g_currentLot = InpDefaultLot;
   g_currentStripes = (InpNumberOfStripes > 0) ? InpNumberOfStripes : 10;
   g_activeTPDist = InpFallbackTPDist;

   DrawHUD();
   UpdateHUDStatus();
   EventSetMillisecondTimer(50); // Superfast 50ms reaction cycle
   PrintFormat(">>> NEWS TERMINAL 5.00 ACTIVE: Calibrated Wick Limits & Dynamic TP ($%.0f) Running! <<<", g_activeTPDist);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   DisarmStraddleWatch();
   ObjectDelete(0, "BOX_MAIN_BG");
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
   ObjectDelete(0, "BTN_STRIPES_10");
   ObjectDelete(0, "BTN_STRIPES_20");
   ObjectDelete(0, "BTN_STRIPES_30");
   ObjectDelete(0, "BTN_STRIPES_40");
   ObjectDelete(0, "BTN_STRIPES_50");
   ObjectDelete(0, "BTN_STRIPES_100");
   ObjectDelete(0, "BTN_BUY");
   ObjectDelete(0, "BTN_SELL");
   ObjectDelete(0, "BTN_KLIMIT");
   ObjectDelete(0, "BTN_LLIMIT");
   ObjectDelete(0, "BTN_STRADDLE");
   ObjectDelete(0, "BTN_CLOSE");
   ObjectDelete(0, "LBL_STATUS");
   ObjectDelete(0, "LINE_STRADDLE_BUY");
   ObjectDelete(0, "LINE_STRADDLE_SELL");
   ChartRedraw(0);
}

void OnTick()
{
   CheckStraddleBreakout();
   ProcessBarcodeEngine();
}

void OnTimer()
{
   CheckStraddleBreakout();
   ProcessBarcodeEngine();
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
      else if(sparam == "BTN_STRIPES_10")  { g_currentStripes = 10;  ObjectSetInteger(0, sparam, OBJPROP_STATE, false); }
      else if(sparam == "BTN_STRIPES_20")  { g_currentStripes = 20;  ObjectSetInteger(0, sparam, OBJPROP_STATE, false); }
      else if(sparam == "BTN_STRIPES_30")  { g_currentStripes = 30;  ObjectSetInteger(0, sparam, OBJPROP_STATE, false); }
      else if(sparam == "BTN_STRIPES_40")  { g_currentStripes = 40;  ObjectSetInteger(0, sparam, OBJPROP_STATE, false); }
      else if(sparam == "BTN_STRIPES_50")  { g_currentStripes = 50;  ObjectSetInteger(0, sparam, OBJPROP_STATE, false); }
      else if(sparam == "BTN_STRIPES_100") { g_currentStripes = 100; ObjectSetInteger(0, sparam, OBJPROP_STATE, false); }
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
      else if(sparam == "BTN_STRADDLE")
      {
         ExecuteStraddleStops();
         ObjectSetInteger(0, "BTN_STRADDLE", OBJPROP_STATE, false);
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
      else if(lparam == 71 || lparam == 103) ExecuteStraddleStops(); // G
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

   // Divide into active stripes (default 10 stripes)
   int numStripes = (g_currentStripes > 0) ? g_currentStripes : InpNumberOfStripes;
   double lotPerStripe = MathFloor((totalLots / (double)numStripes) / lotStep) * lotStep;

   // If 70% of margin can afford at least numStripes x minLot (e.g. 10 x 0.01 = 0.10 lot total)
   if(lotPerStripe >= minLot)
   {
      outLotPerStripe = NormalizeDouble(lotPerStripe, 2);
      return true;
   }
   
   // If not enough for all stripes, check if free margin can at least afford 1 stripe of minLot
   if(freeMargin >= (marginForOneLot * minLot * 1.5))
   {
      outLotPerStripe = minLot;
      return true;
   }

   return false;
}

ENUM_ORDER_TYPE_FILLING GetFillingMode()
{
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   if((filling & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   return ORDER_FILLING_RETURN;
}

int GetBarcodePositionsCount(ENUM_POSITION_TYPE targetPosType = WRONG_VALUE)
{
   int count = 0;
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == 999111)
         {
            if(targetPosType == WRONG_VALUE || PositionGetInteger(POSITION_TYPE) == targetPosType)
            {
               count++;
            }
         }
      }
   }
   return count;
}

void StartBarcodeEngine(ENUM_ORDER_TYPE orderType, int targetStripes, double lot)
{
   g_barcodeActive = true;
   g_barcodeType   = orderType;
   g_barcodeTarget = (targetStripes > 0) ? targetStripes : 10;
   g_barcodeFilled = 0;
   
   ENUM_POSITION_TYPE targetPosType = (orderType == ORDER_TYPE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   g_barcodeBaseOpenCount = GetBarcodePositionsCount(targetPosType);
   
   g_barcodeStartTime = TimeCurrent();
   g_barcodeLastFireTime = 0;

   trade.SetTypeFilling(GetFillingMode());
   trade.SetExpertMagicNumber(999111);
   trade.SetDeviationInPoints(InpSlippagePoints);

   string dir = (orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL";
   PrintFormat("🚀 [BARCODE ENGINE STARTED]: %s %d stripes at %.2f lots | TP: +$%.0f on %s (Existing open: %d)",
               dir, g_barcodeTarget, lot, g_activeTPDist, _Symbol, g_barcodeBaseOpenCount);

   ProcessBarcodeEngine(); // Fire available initial stripes immediately
}

void ProcessBarcodeEngine()
{
   if(!g_barcodeActive || g_barcodeType == WRONG_VALUE) return;

   ENUM_POSITION_TYPE targetPosType = (g_barcodeType == ORDER_TYPE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   int liveStripes = GetBarcodePositionsCount(targetPosType);
   int newlyOpened = liveStripes - g_barcodeBaseOpenCount;
   if(newlyOpened < 0) newlyOpened = 0;

   int currentProgress = MathMax(g_barcodeFilled, newlyOpened);

   // Check if the user's stripe target has been completely achieved
   if(currentProgress >= g_barcodeTarget)
   {
      PrintFormat("🎉 [BARCODE FULLY FILLED]: All %d/%d stripes active on %s! Engine complete.", 
                  currentProgress, g_barcodeTarget, _Symbol);
      g_barcodeActive = false;
      UpdateHUDStatus();
      return;
   }

   // If stripes were opened and now all stripes closed (e.g. hit TP or closed by trader), finish engine
   if(g_barcodeFilled > 0 && liveStripes == 0)
   {
      PrintFormat("🏁 [BARCODE FINISHED]: Open stripes closed/TP reached on %s. Disarming engine.", _Symbol);
      g_barcodeActive = false;
      UpdateHUDStatus();
      return;
   }

   // Active window timeout: 15 minutes for the news breakout momentum to play out
   if(TimeCurrent() - g_barcodeStartTime > 900)
   {
      PrintFormat("⏱️ [BARCODE TIMEOUT]: Active window (15m) ended. Filled %d/%d stripes on %s.", 
                  currentProgress, g_barcodeTarget, _Symbol);
      g_barcodeActive = false;
      UpdateHUDStatus();
      return;
   }

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price = (g_barcodeType == ORDER_TYPE_SELL) ? bid : ask;

   // Margin calculation for 1 stripe of g_currentLot
   double reqMargin = 0.0;
   if(!OrderCalcMargin(g_barcodeType, _Symbol, g_currentLot, price, reqMargin) || reqMargin <= 0.0)
   {
      double leverage = (double)AccountInfoInteger(ACCOUNT_LEVERAGE);
      if(leverage <= 0) leverage = 100.0;
      reqMargin = (price * 100.0 * g_currentLot) / leverage;
   }

   double safetyBuffer = 1.50; // $1.50 margin buffer to prevent [No money] rejection
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

   // If free margin cannot afford another stripe right now, wait for floating profit to expand margin!
   if(freeMargin < (reqMargin + safetyBuffer))
   {
      return;
   }

   trade.SetTypeFilling(GetFillingMode());
   trade.SetExpertMagicNumber(999111);
   trade.SetDeviationInPoints(InpSlippagePoints);

   int canAfford = (int)MathFloor((freeMargin - safetyBuffer) / reqMargin);
   if(canAfford <= 0) return;

   int remaining = g_barcodeTarget - currentProgress;
   int toFireNow = MathMin(canAfford, remaining);

   int firedInThisBurst = 0;
   for(int i = 0; i < toFireNow; i++)
   {
      // Re-verify live free margin immediately before every trade dispatch
      freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(freeMargin < (reqMargin + safetyBuffer))
      {
         PrintFormat("⏳ [BARCODE MARGIN PAUSE]: Consumed available margin. %d/%d open. Waiting for floating profit to expand margin...",
                     GetBarcodePositionsCount(targetPosType), g_barcodeTarget);
         break;
      }

      ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double tp = 0.0;
      if(g_activeTPDist > 0.0)
      {
         tp = (g_barcodeType == ORDER_TYPE_SELL) ? NormalizeDouble(bid - g_activeTPDist, digits) : NormalizeDouble(ask + g_activeTPDist, digits);
      }

      string comment = StringFormat("Barcode %d/%d", currentProgress + firedInThisBurst + 1, g_barcodeTarget);
      bool ok = false;
      if(g_barcodeType == ORDER_TYPE_BUY)
         ok = trade.Buy(g_currentLot, _Symbol, ask, 0.0, tp, comment);
      else
         ok = trade.Sell(g_currentLot, _Symbol, bid, 0.0, tp, comment);

      if(ok && (trade.ResultRetcode() == TRADE_RETCODE_DONE || trade.ResultRetcode() == TRADE_RETCODE_PLACED))
      {
         firedInThisBurst++;
         g_barcodeFilled++;
         g_barcodeLastFireTime = TimeCurrent();
      }
      else
      {
         uint ret = trade.ResultRetcode();
         PrintFormat("⚠️ [BARCODE RETRY LATER]: Order send paused (code %u: %s). Free Margin: $%.2f",
                     ret, trade.ResultRetcodeDescription(), AccountInfoDouble(ACCOUNT_MARGIN_FREE));
         break;
      }
   }

   if(firedInThisBurst > 0)
   {
      int currentOpen = GetBarcodePositionsCount(targetPosType);
      PrintFormat("⚡ [BARCODE BURST]: Fired %d stripes! Current Open: %d/%d (Free Margin: $%.2f | TP: +$%.0f)",
                  firedInThisBurst, currentOpen, g_barcodeTarget, AccountInfoDouble(ACCOUNT_MARGIN_FREE), g_activeTPDist);
      UpdateHUDStatus();

      if(currentOpen - g_barcodeBaseOpenCount >= g_barcodeTarget || g_barcodeFilled >= g_barcodeTarget)
      {
         PrintFormat("🎉 [BARCODE FULLY FILLED]: All %d/%d stripes successfully filled on %s!", 
                     g_barcodeTarget, g_barcodeTarget, _Symbol);
         g_barcodeActive = false;
         UpdateHUDStatus();
      }
   }
}

void ExecuteBarcode(ENUM_ORDER_TYPE orderType, double customLot = 0.0)
{
   double lot = (customLot > 0.0) ? customLot : g_currentLot;
   int stripes = (g_currentStripes > 0) ? g_currentStripes : InpNumberOfStripes;
   StartBarcodeEngine(orderType, stripes, lot);
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

   trade.SetExpertMagicNumber(999222);
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
   g_barcodeActive = false;
   g_barcodeTarget = 0;
   g_barcodeFilled = 0;
   DisarmStraddleWatch();
   UpdateHUDStatus();

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

double GetPipSize()
{
   string sym = _Symbol;
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);

   if(StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0)
   {
      // 1 pip on Gold is universally $0.10 (10 cents)
      return 0.10;
   }
   if(digits == 3 || digits == 5) return point * 10.0;
   return point;
}

void ArmStraddleWatch()
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double pipSize = GetPipSize();
   double dist = InpStopDistancePips * pipSize; // 50 pips = $5.00 on Gold

   // Minimum broker stop level check
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minAllowedDist = (double)stopsLevel * point;
   if(dist < minAllowedDist) dist = minAllowedDist;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   g_straddleBuyTrigger  = NormalizeDouble(ask + dist, digits);
   g_straddleSellTrigger = NormalizeDouble(bid - dist, digits);
   g_straddleArmed = true;
   g_straddleArmTime = TimeCurrent();

   // Draw visual trigger lines on the chart
   ObjectDelete(0, "LINE_STRADDLE_BUY");
   ObjectCreate(0, "LINE_STRADDLE_BUY", OBJ_HLINE, 0, 0, g_straddleBuyTrigger);
   ObjectSetInteger(0, "LINE_STRADDLE_BUY", OBJPROP_COLOR, C'34,197,94'); // Vibrant green
   ObjectSetInteger(0, "LINE_STRADDLE_BUY", OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, "LINE_STRADDLE_BUY", OBJPROP_WIDTH, 2);
   ObjectSetString(0, "LINE_STRADDLE_BUY", OBJPROP_TEXT, StringFormat("⚡ BREAKOUT BUY: %dx %.2f (TP +$%.0f)", g_currentStripes, g_currentLot, g_activeTPDist));

   ObjectDelete(0, "LINE_STRADDLE_SELL");
   ObjectCreate(0, "LINE_STRADDLE_SELL", OBJ_HLINE, 0, 0, g_straddleSellTrigger);
   ObjectSetInteger(0, "LINE_STRADDLE_SELL", OBJPROP_COLOR, C'239,68,68'); // Vibrant red
   ObjectSetInteger(0, "LINE_STRADDLE_SELL", OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, "LINE_STRADDLE_SELL", OBJPROP_WIDTH, 2);
   ObjectSetString(0, "LINE_STRADDLE_SELL", OBJPROP_TEXT, StringFormat("⚡ BREAKOUT SELL: %dx %.2f (TP -$%.0f)", g_currentStripes, g_currentLot, g_activeTPDist));

   UpdateHUDStatus();
   ChartRedraw(0);

   PrintFormat("⚡ [BREAKOUT WATCH ARMED [G]]: Waiting on %s! Buy Trigger >= %.2f (+%.0fp) | Sell Trigger <= %.2f (-%.0fp) | Barcode: %dx %.2f | TP: +$%.0f",
               _Symbol, g_straddleBuyTrigger, InpStopDistancePips, g_straddleSellTrigger, InpStopDistancePips, g_currentStripes, g_currentLot, g_activeTPDist);
}

void DisarmStraddleWatch()
{
   if(!g_straddleArmed && ObjectFind(0, "LINE_STRADDLE_BUY") < 0 && ObjectFind(0, "LINE_STRADDLE_SELL") < 0) return;
   g_straddleArmed = false;
   g_straddleBuyTrigger = 0.0;
   g_straddleSellTrigger = 0.0;
   g_straddleArmTime = 0;
   ObjectDelete(0, "LINE_STRADDLE_BUY");
   ObjectDelete(0, "LINE_STRADDLE_SELL");
   UpdateHUDStatus();
   ChartRedraw(0);
}

void ToggleStraddleWatch()
{
   if(g_straddleArmed)
   {
      DisarmStraddleWatch();
      Print("⏸️ [BREAKOUT WATCH DISARMED]: Breakout watch cancelled by user.");
   }
   else
   {
      ArmStraddleWatch();
   }
}

void ExecuteStraddleStops()
{
   ToggleStraddleWatch();
}

void CheckStraddleBreakout()
{
   if(!g_straddleArmed) return;

   // Auto-expiration timeout
   if(InpStopExpiryMins > 0 && g_straddleArmTime > 0)
   {
      if(TimeCurrent() - g_straddleArmTime >= (InpStopExpiryMins * 60))
      {
         Print("⏳ [BREAKOUT WATCH EXPIRED]: 15 minute timeout reached without breakout. Disarming...");
         DisarmStraddleWatch();
         return;
      }
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // 1. Upward Breakout
   if(ask >= g_straddleBuyTrigger && g_straddleBuyTrigger > 0.0)
   {
      double triggerLvl = g_straddleBuyTrigger;
      DisarmStraddleWatch(); // Immediately disarm to prevent duplicate firing
      PrintFormat("🚀🚀 [BREAKOUT BUY TRIGGERED]: Ask %.2f crossed trigger %.2f (+%.0fp)! Firing %d barcode stripes at %.2f lots with TP +$%.0f...",
                  ask, triggerLvl, InpStopDistancePips, g_currentStripes, g_currentLot, g_activeTPDist);
      ExecuteBarcode(ORDER_TYPE_BUY);
      return;
   }

   // 2. Downward Breakout
   if(bid <= g_straddleSellTrigger && g_straddleSellTrigger > 0.0)
   {
      double triggerLvl = g_straddleSellTrigger;
      DisarmStraddleWatch(); // Immediately disarm to prevent duplicate firing
      PrintFormat("🚀🚀 [BREAKOUT SELL TRIGGERED]: Bid %.2f crossed trigger %.2f (-%.0fp)! Firing %d barcode stripes at %.2f lots with TP +$%.0f...",
                  bid, triggerLvl, InpStopDistancePips, g_currentStripes, g_currentLot, g_activeTPDist);
      ExecuteBarcode(ORDER_TYPE_SELL);
      return;
   }
}
