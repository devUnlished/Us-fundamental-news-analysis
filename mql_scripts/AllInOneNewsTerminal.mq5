//+------------------------------------------------------------------+
//|                                     AllInOneNewsTerminal.mq5     |
//|            High-Impact News Execution & Liquidation Engine       |
//|    NEW: Calibrated Spike Limits & Take Profits derived from      |
//|         3-Year Forensic Manipulation Wick & True Move Data       |
//+------------------------------------------------------------------+
#property copyright "News Sniper Terminal"
#property link      "https://github.com/devUnlished/Us-fundamental-news-analysis"
#property version   "5.21"

#include <Trade\Trade.mqh>

input group "=== BARCODE SETTINGS ===";
input int      InpNumberOfStripes   = 10;      // Number of barcode stripes per trigger
input double   InpDefaultLot        = 0.05;    // Starting Lot size per stripe

input group "=== DYNAMIC CALIBRATION ===";
input bool     InpAutoCalibrateNews = true;    // Auto-calibrate Limit Distance & TP to live news release!
input double   InpFallbackSpikeDist = 18.0;    // Fallback Limit Offset in Gold $ ($18.00 = 180 pips)
input double   InpFallbackTPDist    = 75.0;    // Fallback Take Profit in Gold $ ($75.00 = 750 pips)

input group "=== STRADDLE BREAKOUT BARCODE (G KEY) ===";
input double   InpStopDistance      = 10.0;    // Breakout Distance in Gold $ ($10.00 = 100 pips)
input double   InpStopTPDistance    = 75.0;    // Take Profit in Gold $ ($75.00 = 750 pips)
input double   InpStopSLDistance    = 0.0;     // Stop Loss in Gold $ (0 for none)
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

input group "=== MCP COMMAND LINK ===";
input bool     InpAllowMCP          = false;   // Allow external MCP agent commands via command file (OFF = manual only)
input double   InpMCPMaxRiskUSD     = 2.0;     // Max $ risk per MCP-fired barcode (0 = no EA-side cap)

CTrade trade;
double g_currentLot = 0.05;
int    g_currentStripes = 10;
string g_activeNewsName = "Standby (Normal)";
double g_activeSpikeOffset = 18.00; // in Gold dollars ($18.00 = 180 pips)
double g_activeTPDist = 75.00;      // in Gold dollars ($75.00 = 750 pips)
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
int             g_barcodeMaxLiveSeen = 0;
int             g_barcodeBaseOpenCount = 0;
datetime        g_barcodeStartTime = 0;
datetime        g_barcodeLastFireTime = 0;
double          g_barcodeStripeLot = 0.01;
double          g_learnedMinMargin = 0.0;

// MCP command-link state (lets the external agent call the same functions as the panel buttons)
#define MCP_CMD_FILE "mcp_cmd.txt"
#define MCP_ACK_FILE "mcp_ack.txt"
#define MCP_CMD_MAX_AGE_SEC 60
string   g_mcpLastNonce = "";
string   g_mcpLastCmd = "none";
string   g_mcpLastResult = "";
datetime g_mcpLastCmdTime = 0;
double   g_mcpSL = 0.0;      // Absolute SL price for one MCP-fired barcode run (0 = none)
double   g_mcpTP = 0.0;      // Absolute TP price for one MCP-fired barcode run (0 = engine default)
bool     g_mcpArmedRun = false; // One-shot latch: next StartBarcodeEngine keeps SL/TP, else clears

int    GetBarcodePositionsCount(ENUM_POSITION_TYPE targetPosType = WRONG_VALUE);
double GetMarginRequired(ENUM_ORDER_TYPE orderType, double lot);
void   ExecuteBarcode(ENUM_ORDER_TYPE orderType, double customLot = 0.0, double customSL = 0.0, double customTP = 0.0);
void   StartBarcodeEngine(ENUM_ORDER_TYPE orderType, int targetStripes, double lot, double customSL = 0.0, double customTP = 0.0);
void   ProcessBarcodeEngine();
void   ClearBarcodeGlobals();
void   SaveBarcodeGlobals();
void ArmSpikeLimits(ENUM_ORDER_TYPE orderType);
void ExecuteStraddleStops();
void ToggleStraddleWatch();
void ArmStraddleWatch();
void DisarmStraddleWatch();
void DrawStraddleLines(double buyTrig, double buyTP, double sellTrig, double sellTP);
void CheckStraddleBreakout();
bool CanAffordBarcode(ENUM_ORDER_TYPE orderType, double &outLotPerStripe);
double GetPipSize();
ENUM_ORDER_TYPE_FILLING GetFillingMode();
void RemoveChartTextClutter();
void PollMCPCommand();
void WriteMCPAck(string status, string nonce, string detail);
string ExecuteMCPCommand(string cmdLine, bool &ok);
bool MCPProtectionValid(double bid, double ask, double sl, double tp, ENUM_ORDER_TYPE type, string &reason);
string MCPFireBarcode(ENUM_ORDER_TYPE type, string &parts[], int count, bool &ok);

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
   int r8_y   = r7_y + (int)(20 * scale);
   int totalH = (r8_y - startY) + (int)(22 * scale) + pad;

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
   string straddleTxt = StringFormat("STRADDLE BREAKOUT BARCODE [G] (±$%.0f)", InpStopDistance);
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

   // Row 8: MCP command-link status (external agent visibility)
   ObjectDelete(0, "LBL_MCP");
   ObjectCreate(0, "LBL_MCP", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "LBL_MCP", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "LBL_MCP", OBJPROP_XDISTANCE, startX);
   ObjectSetInteger(0, "LBL_MCP", OBJPROP_YDISTANCE, r8_y);
   ObjectSetString(0, "LBL_MCP", OBJPROP_FONT, "Segoe UI");
   ObjectSetInteger(0, "LBL_MCP", OBJPROP_FONTSIZE, fsStatus);
   ObjectSetInteger(0, "LBL_MCP", OBJPROP_COLOR, C'100,116,139');
}

// Inspect live calendar & calibrate Wick Limit + Take Profit dynamically
void CalibrateNewsTargets()
{
   if(!InpAutoCalibrateNews) return;

   datetime now = TimeCurrent();
   static datetime lastCalibCheck = 0;
   if(now - lastCalibCheck < 10) return;
   lastCalibCheck = now;

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
               g_activeTPDist = 75.0;      // 750 pip ($75.00) TP target
               isTarget = true;
            }
            else if(StringFind(low, "nonfarm") >= 0 || StringFind(low, "non farm") >= 0)
            {
               g_activeNewsName = "Nonfarm Payrolls (NFP)";
               if(diff > 68.0)      { g_activeTier = "BLOWOUT"; g_activeSpikeOffset = 25.0; g_activeTPDist = 75.0; }
               else if(diff > 30.0) { g_activeTier = "SOLID";   g_activeSpikeOffset = 20.0; g_activeTPDist = 75.0; }
               else                 { g_activeTier = "MODEST";  g_activeSpikeOffset = 18.0; g_activeTPDist = 75.0; }
               isTarget = true;
            }
            else if(StringFind(low, "cpi") >= 0 || StringFind(low, "consumer price") >= 0)
            {
               g_activeNewsName = "Consumer Price Index (CPI)";
               if(diff > 0.25)      { g_activeTier = "BLOWOUT"; g_activeSpikeOffset = 22.0; g_activeTPDist = 75.0; }
               else if(diff > 0.12) { g_activeTier = "SOLID";   g_activeSpikeOffset = 16.0; g_activeTPDist = 75.0; }
               else                 { g_activeTier = "MODEST";  g_activeSpikeOffset = 12.0; g_activeTPDist = 75.0; }
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
      string info = StringFormat("⚡ FILLING %s: %d/%d open (%.2f lot) | Margin: $%.1f | TP: +$%.0f", 
                                 dirStr, liveStripes, g_barcodeTarget, g_barcodeStripeLot, AccountInfoDouble(ACCOUNT_MARGIN_FREE), g_activeTPDist);
      ObjectSetString(0, "LBL_STATUS", OBJPROP_TEXT, info);
      ObjectSetInteger(0, "LBL_STATUS", OBJPROP_COLOR, C'250,204,21'); // Amber yellow
   }
   else if(g_straddleArmed)
   {
      string info = StringFormat("⚡ ARMED: BUY >= %.2f | SELL <= %.2f | TP: ±$%.0f | %dx %.2f", 
                                 g_straddleBuyTrigger, g_straddleSellTrigger, g_activeTPDist, g_currentStripes, g_currentLot);
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
      ObjectSetString(0, "BTN_STRADDLE", OBJPROP_TEXT, StringFormat("⚡ ARMED: BREAKOUT WATCH [G] (±$%.0f)", InpStopDistance));
      ObjectSetInteger(0, "BTN_STRADDLE", OBJPROP_BGCOLOR, C'202,138,4'); // Vibrant Gold Amber
      ObjectSetInteger(0, "BTN_STRADDLE", OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, "BTN_STRADDLE", OBJPROP_BORDER_COLOR, C'250,204,21'); // Bright yellow border
   }
   else
   {
      ObjectSetString(0, "BTN_STRADDLE", OBJPROP_TEXT, StringFormat("STRADDLE BREAKOUT BARCODE [G] (±$%.0f)", InpStopDistance));
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

   // MCP command-link status line: always visible so the human sees agent activity
   if(!InpAllowMCP)
   {
      ObjectSetString(0, "LBL_MCP", OBJPROP_TEXT, "MCP LINK: OFF (manual only)");
      ObjectSetInteger(0, "LBL_MCP", OBJPROP_COLOR, C'100,116,139');
   }
   else if(g_mcpLastCmdTime > 0 && TimeCurrent() - g_mcpLastCmdTime < 300)
   {
      ObjectSetString(0, "LBL_MCP", OBJPROP_TEXT, StringFormat("MCP: %s -> %s", g_mcpLastCmd, g_mcpLastResult));
      ObjectSetInteger(0, "LBL_MCP", OBJPROP_COLOR, C'52,211,153');
   }
   else
   {
      ObjectSetString(0, "LBL_MCP", OBJPROP_TEXT, "MCP LINK: ARMED | last: none");
      ObjectSetInteger(0, "LBL_MCP", OBJPROP_COLOR, C'52,211,153');
   }

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

   RemoveChartTextClutter();
   DrawHUD();
   UpdateHUDStatus();
   EventSetMillisecondTimer(50); // Superfast 50ms reaction cycle
   FileDelete(MCP_CMD_FILE); // Never execute a leftover command from a previous session
   FileDelete(MCP_ACK_FILE);
   PrintFormat(">>> NEWS TERMINAL 5.21 ACTIVE: Calibrated Wick Limits & Dynamic TP ($%.0f) Running! MCP link: %s <<<", g_activeTPDist, InpAllowMCP ? "ARMED" : "OFF");

   // Retain armed stops across timeframe switches!
   string gvPrefix = StringFormat("AION_%s_", _Symbol);
   if(GlobalVariableCheck(gvPrefix + "ARMED") && GlobalVariableGet(gvPrefix + "ARMED") > 0.5)
   {
      g_straddleArmed       = true;
      g_straddleBuyTrigger  = GlobalVariableGet(gvPrefix + "BUY_TRIG");
      g_straddleSellTrigger = GlobalVariableGet(gvPrefix + "SELL_TRIG");
      g_straddleArmTime     = (datetime)GlobalVariableGet(gvPrefix + "ARM_TIME");
      double buyTP          = GlobalVariableGet(gvPrefix + "BUY_TP");
      double sellTP         = GlobalVariableGet(gvPrefix + "SELL_TP");

      DrawStraddleLines(g_straddleBuyTrigger, buyTP, g_straddleSellTrigger, sellTP);
      UpdateHUDStatus();
      PrintFormat("🔄 [TIMEFRAME SWITCH]: Retained active Breakout Stops on %s! Buy: %.2f | Sell: %.2f",
                  _Symbol, g_straddleBuyTrigger, g_straddleSellTrigger);
   }

   // Restore active barcode engine across timeframe switches!
   string bcPrefix = StringFormat("AION_%s_BC_", _Symbol);
   if(GlobalVariableCheck(bcPrefix + "ACTIVE") && GlobalVariableGet(bcPrefix + "ACTIVE") > 0.5)
   {
      g_barcodeActive        = true;
      g_barcodeType          = (ENUM_ORDER_TYPE)(int)GlobalVariableGet(bcPrefix + "TYPE");
      g_barcodeTarget        = (int)GlobalVariableGet(bcPrefix + "TARGET");
      g_barcodeFilled        = (int)GlobalVariableGet(bcPrefix + "FILLED");
      g_barcodeMaxLiveSeen   = (int)GlobalVariableGet(bcPrefix + "MAXLIVE");
      g_barcodeBaseOpenCount = (int)GlobalVariableGet(bcPrefix + "BASEOPEN");
      g_barcodeStartTime     = (datetime)GlobalVariableGet(bcPrefix + "START_TIME");
      g_barcodeLastFireTime  = (datetime)GlobalVariableGet(bcPrefix + "LAST_FIRE");
      g_barcodeStripeLot     = GlobalVariableGet(bcPrefix + "LOT");
      g_mcpSL                = GlobalVariableGet(bcPrefix + "SL");
      g_mcpTP                = GlobalVariableGet(bcPrefix + "TP");

      PrintFormat("🔄 [TIMEFRAME SWITCH]: Retained active Barcode Engine on %s! %s Target: %d | Filled: %d | Lot: %.2f",
                  _Symbol, (g_barcodeType == ORDER_TYPE_BUY) ? "BUY" : "SELL", g_barcodeTarget, g_barcodeFilled, g_barcodeStripeLot);
   }

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();

   // Only disarm if actually removing EA or terminal closing - NEVER on timeframe switch!
   if(reason == REASON_CHARTCHANGE || reason == REASON_PARAMETERS)
   {
      SaveBarcodeGlobals();
   }
   else
   {
      DisarmStraddleWatch();
      ClearBarcodeGlobals();
   }

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
   ObjectDelete(0, "LBL_MCP");

   if(reason != REASON_CHARTCHANGE && reason != REASON_PARAMETERS)
   {
      ObjectDelete(0, "LINE_STRADDLE_BUY");
      ObjectDelete(0, "LINE_STRADDLE_BUY_TP");
      ObjectDelete(0, "LINE_STRADDLE_SELL");
      ObjectDelete(0, "LINE_STRADDLE_SELL_TP");
      ChartSetInteger(0, CHART_SCALEFIX, false);
   }
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
   PollMCPCommand();
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

double GetMarginRequired(ENUM_ORDER_TYPE orderType, double lot)
{
   if(lot <= 0.0) return 0.0;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price = (orderType == ORDER_TYPE_SELL) ? bid : ask;

   double reqMargin = 0.0;
   bool ok = OrderCalcMargin(orderType, _Symbol, lot, price, reqMargin);

   bool isGold = (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0);
   double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   if(contractSize <= 0.0) contractSize = isGold ? 100.0 : 100000.0;

   long acctLev = AccountInfoInteger(ACCOUNT_LEVERAGE);
   if(acctLev <= 0) acctLev = 100;
   double effectiveLev = (double)acctLev;
   // Retail brokers strictly enforce max 1:100 leverage on Gold (e.g. XM Global, IC Markets, Exness)
   if(isGold && effectiveLev > 100.0) effectiveLev = 100.0;

   double formulaMargin = (price * contractSize * lot) / effectiveLev;

   // Trust the broker's own figure first: OrderCalcMargin reflects live server
   // rules (FBS gold here is ~1:500, not 1:100). The formula is a fallback for
   // when the calc fails, never an override of a sane server value.
   if(!ok || reqMargin <= 0.0)
   {
      reqMargin = formulaMargin;
   }

   // Also verify SYMBOL_MARGIN_INITIAL if explicitly configured by broker
   double marginInitial = SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL);
   if(marginInitial > 0.0)
   {
      double initialTotal = marginInitial * lot;
      if(initialTotal > reqMargin) reqMargin = initialTotal;
   }

   // Respect learned live broker rejection threshold
   if(g_learnedMinMargin > 0.0 && lot >= 0.01)
   {
      double minFloor = g_learnedMinMargin * (lot / 0.01);
      if(reqMargin < minFloor) reqMargin = minFloor;
   }

   return reqMargin;
}

bool CanAffordBarcode(ENUM_ORDER_TYPE orderType, double &outLotPerStripe)
{
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double marginForOneLot = GetMarginRequired(orderType, 1.0);
   if(marginForOneLot <= 0.0) marginForOneLot = 4128.0;

   // 70% of currently available free margin
   double targetMargin = freeMargin * (MathMin(InpMarginPercent, 95.0) / 100.0);

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
   if(freeMargin >= (marginForOneLot * minLot * 1.2))
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

void ClearBarcodeGlobals()
{
   string gvPrefix = StringFormat("AION_%s_BC_", _Symbol);
   GlobalVariableDel(gvPrefix + "ACTIVE");
   GlobalVariableDel(gvPrefix + "TYPE");
   GlobalVariableDel(gvPrefix + "TARGET");
   GlobalVariableDel(gvPrefix + "FILLED");
   GlobalVariableDel(gvPrefix + "MAXLIVE");
   GlobalVariableDel(gvPrefix + "BASEOPEN");
   GlobalVariableDel(gvPrefix + "START_TIME");
   GlobalVariableDel(gvPrefix + "LAST_FIRE");
   GlobalVariableDel(gvPrefix + "LOT");
   GlobalVariableDel(gvPrefix + "SL");
   GlobalVariableDel(gvPrefix + "TP");
}

void SaveBarcodeGlobals()
{
   if(!g_barcodeActive)
   {
      ClearBarcodeGlobals();
      return;
   }
   string gvPrefix = StringFormat("AION_%s_BC_", _Symbol);
   GlobalVariableSet(gvPrefix + "ACTIVE", 1.0);
   GlobalVariableSet(gvPrefix + "TYPE", (double)g_barcodeType);
   GlobalVariableSet(gvPrefix + "TARGET", (double)g_barcodeTarget);
   GlobalVariableSet(gvPrefix + "FILLED", (double)g_barcodeFilled);
   GlobalVariableSet(gvPrefix + "MAXLIVE", (double)g_barcodeMaxLiveSeen);
   GlobalVariableSet(gvPrefix + "BASEOPEN", (double)g_barcodeBaseOpenCount);
   GlobalVariableSet(gvPrefix + "START_TIME", (double)g_barcodeStartTime);
   GlobalVariableSet(gvPrefix + "LAST_FIRE", (double)g_barcodeLastFireTime);
   GlobalVariableSet(gvPrefix + "LOT", g_barcodeStripeLot);
   GlobalVariableSet(gvPrefix + "SL", g_mcpSL);
   GlobalVariableSet(gvPrefix + "TP", g_mcpTP);
}

void StartBarcodeEngine(ENUM_ORDER_TYPE orderType, int targetStripes, double lot, double customSL = 0.0, double customTP = 0.0)
{
   // One-shot MCP protection: an MCP fire command sets the latch + SL/TP just
   // before calling in. Any other (manual/hotkey/straddle) start clears stale values.
   if(customSL > 0.0 || customTP > 0.0)
   {
      g_mcpSL = customSL;
      g_mcpTP = customTP;
      g_mcpArmedRun = false;
   }
   else if(!g_mcpArmedRun)
   {
      g_mcpSL = 0.0;
      g_mcpTP = 0.0;
   }
   else
   {
      g_mcpArmedRun = false;
   }
   g_barcodeActive = true;
   g_barcodeType   = orderType;
   g_barcodeTarget = (targetStripes > 0) ? targetStripes : 10;
   g_barcodeFilled = 0;
   g_barcodeMaxLiveSeen = 0;
   
   ENUM_POSITION_TYPE targetPosType = (orderType == ORDER_TYPE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   g_barcodeBaseOpenCount = GetBarcodePositionsCount(targetPosType);
   
   g_barcodeStartTime = TimeCurrent();
   g_barcodeLastFireTime = 0;

   // Determine stripe lot: if selected lot is unaffordable even for 1 stripe, dynamically scale to what free margin allows
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double req = GetMarginRequired(orderType, lot);
   double buffer = 2.50;

   if(freeMargin < (req + buffer))
   {
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      if(minLot <= 0.0) minLot = 0.01;
      double minReq = GetMarginRequired(orderType, minLot);

      if(freeMargin >= (minReq + buffer))
      {
         double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
         if(lotStep <= 0.0) lotStep = 0.01;
         double affordable = MathFloor(((freeMargin - buffer) * (minLot / minReq)) / lotStep) * lotStep;
         affordable = NormalizeDouble(affordable, 2);
         if(affordable < minLot) affordable = minLot;
         if(affordable > lot) affordable = lot;
         g_barcodeStripeLot = NormalizeDouble(affordable, 2);
         PrintFormat("⚠️ [MARGIN ADAPTATION]: Free Margin $%.2f cannot afford %.2f lot. Scaled stripe lot to %.2f.",
                     freeMargin, lot, g_barcodeStripeLot);
      }
      else
      {
         g_barcodeStripeLot = (lot > 0.0) ? NormalizeDouble(lot, 2) : 0.01;
      }
   }
   else
   {
      g_barcodeStripeLot = (lot > 0.0) ? NormalizeDouble(lot, 2) : 0.01;
   }

   trade.SetTypeFilling(GetFillingMode());
   trade.SetExpertMagicNumber(999111);
   trade.SetDeviationInPoints(InpSlippagePoints);

   double effTP = (InpStopTPDistance > 0.0) ? InpStopTPDistance : g_activeTPDist;
   string dir = (orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL";
   PrintFormat("🚀 [BARCODE ENGINE STARTED]: %s %d stripes at %.2f lots | TP: +$%.0f on %s (Existing open: %d | Free Margin: $%.2f)",
               dir, g_barcodeTarget, g_barcodeStripeLot, effTP, _Symbol, g_barcodeBaseOpenCount, freeMargin);

   SaveBarcodeGlobals();
   ProcessBarcodeEngine(); // Fire available initial stripes immediately
}

void ProcessBarcodeEngine()
{
   if(!g_barcodeActive || g_barcodeType == WRONG_VALUE) return;

   ENUM_POSITION_TYPE targetPosType = (g_barcodeType == ORDER_TYPE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   int liveStripes = GetBarcodePositionsCount(targetPosType);
   int newlyOpened = liveStripes - g_barcodeBaseOpenCount;
   if(newlyOpened < 0) newlyOpened = 0;

   if(newlyOpened > g_barcodeMaxLiveSeen)
   {
      g_barcodeMaxLiveSeen = newlyOpened;
   }

   // Reconcile async orders after 1.5 seconds if some were rejected by broker
   if(TimeCurrent() - g_barcodeLastFireTime > 1 && g_barcodeFilled > newlyOpened)
   {
      g_barcodeFilled = newlyOpened;
   }

   int currentProgress = MathMax(g_barcodeFilled, newlyOpened);

   // Check if the user's stripe target has been completely achieved
   if(newlyOpened >= g_barcodeTarget)
   {
      PrintFormat("🎉 [BARCODE FULLY FILLED]: All %d/%d stripes active on %s! Engine complete.", 
                  newlyOpened, g_barcodeTarget, _Symbol);
      g_barcodeActive = false;
      ClearBarcodeGlobals();
      g_barcodeMaxLiveSeen = 0;
      g_mcpSL = 0.0; g_mcpTP = 0.0;
      UpdateHUDStatus();
      return;
   }

   // If stripes were opened and now all stripes closed (e.g. hit TP or closed by trader), finish engine.
   // Safety: must have actually had confirmed live stripes (g_barcodeMaxLiveSeen > 0)
   // AND at least 3 seconds must have passed since firing so in-flight orders are done.
   if(g_barcodeMaxLiveSeen > 0 && liveStripes == 0 && (TimeCurrent() - g_barcodeLastFireTime >= 3))
   {
      PrintFormat("🏁 [BARCODE FINISHED]: Open stripes closed/TP reached on %s (peak: %d positions). Disarming engine.", 
                  _Symbol, g_barcodeMaxLiveSeen);
      g_barcodeActive = false;
      ClearBarcodeGlobals();
      g_barcodeMaxLiveSeen = 0;
      g_mcpSL = 0.0; g_mcpTP = 0.0;
      UpdateHUDStatus();
      return;
   }

   // Active window timeout: 15 minutes for the news breakout momentum to play out
   if(TimeCurrent() - g_barcodeStartTime > 900)
   {
      PrintFormat("⏱️ [BARCODE TIMEOUT]: Active window (15m) ended. Filled %d/%d stripes on %s.", 
                  newlyOpened, g_barcodeTarget, _Symbol);
      g_barcodeActive = false;
      ClearBarcodeGlobals();
      g_barcodeMaxLiveSeen = 0;
      g_mcpSL = 0.0; g_mcpTP = 0.0;
      UpdateHUDStatus();
      return;
   }

   double reqMargin = GetMarginRequired(g_barcodeType, g_barcodeStripeLot);
   double safetyBuffer = 2.50; // $2.50 margin buffer to prevent [No money] rejection
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

   // If free margin cannot afford another stripe right now, wait for floating profit to expand margin!
   if(freeMargin < (reqMargin + safetyBuffer))
   {
      static datetime lastWaitPrint = 0;
      if(TimeCurrent() - lastWaitPrint >= 5)
      {
         PrintFormat("⏳ [BARCODE WAITING]: need $%.2f margin, have $%.2f free. Waiting for margin expansion (%d/%d filled).",
                     reqMargin + safetyBuffer, freeMargin, newlyOpened, g_barcodeTarget);
         lastWaitPrint = TimeCurrent();
      }
      return;
   }

   int canAfford = (int)MathFloor((freeMargin - safetyBuffer) / reqMargin);
   if(canAfford <= 0) return;

   int remaining = g_barcodeTarget - currentProgress;
   if(remaining <= 0) return;

   int toFireNow = MathMin(canAfford, remaining);
   if(toFireNow > 30) toFireNow = 30;
   if(toFireNow <= 0) return;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   int firedInThisBurst = 0;

   trade.SetTypeFilling(GetFillingMode());
   trade.SetExpertMagicNumber(999111);
   trade.SetDeviationInPoints(InpSlippagePoints);

   for(int i = 0; i < toFireNow; i++)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double price = (g_barcodeType == ORDER_TYPE_SELL) ? bid : ask;

      double tp = 0.0;
      double effTPDist = (InpStopTPDistance > 0.0) ? InpStopTPDistance : g_activeTPDist;
      if(effTPDist > 0.0)
      {
         tp = (g_barcodeType == ORDER_TYPE_SELL) ? NormalizeDouble(bid - effTPDist, digits) : NormalizeDouble(ask + effTPDist, digits);
      }

      // MCP-protected run: apply command SL/TP, revalidated every burst.
      // If protection went invalid (price moved through it), abort the run:
      // an MCP-protected barcode never fires naked.
      double sl = 0.0;
      if(g_mcpSL > 0.0 || g_mcpTP > 0.0)
      {
         string mcpWhy = "";
         if(!MCPProtectionValid(bid, ask, g_mcpSL, g_mcpTP, g_barcodeType, mcpWhy))
         {
            PrintFormat("🛑 [BARCODE ABORTED]: MCP protection invalid at fire time (%s). Engine stopped, no naked fill.", mcpWhy);
            g_barcodeActive = false;
            ClearBarcodeGlobals();
            g_barcodeMaxLiveSeen = 0;
            g_mcpSL = 0.0; g_mcpTP = 0.0;
            UpdateHUDStatus();
            return;
         }
         if(g_mcpSL > 0.0) sl = NormalizeDouble(g_mcpSL, digits);
         if(g_mcpTP > 0.0) tp = NormalizeDouble(g_mcpTP, digits);
      }

      string comment = StringFormat("Barcode %d/%d", currentProgress + firedInThisBurst + 1, g_barcodeTarget);

      MqlTradeRequest request;
      MqlTradeResult  result;
      ZeroMemory(request);
      ZeroMemory(result);

      request.action       = TRADE_ACTION_DEAL;
      request.symbol       = _Symbol;
      request.volume       = g_barcodeStripeLot;
      request.type         = g_barcodeType;
      request.price        = price;
      request.sl           = sl;
      request.tp           = tp;
      request.deviation    = InpSlippagePoints;
      request.magic        = 999111;
      request.comment      = comment;
      request.type_filling = GetFillingMode();

      bool ok = false;
      if(OrderSendAsync(request, result))
      {
         ok = true;
         firedInThisBurst++;
         g_barcodeFilled++;
         g_barcodeLastFireTime = TimeCurrent();
      }
      else
      {
         // Fallback sync send
         if(g_barcodeType == ORDER_TYPE_BUY)
            ok = trade.Buy(g_barcodeStripeLot, _Symbol, ask, sl, tp, comment);
         else
            ok = trade.Sell(g_barcodeStripeLot, _Symbol, bid, sl, tp, comment);

         if(ok && (trade.ResultRetcode() == TRADE_RETCODE_DONE || trade.ResultRetcode() == TRADE_RETCODE_PLACED))
         {
            firedInThisBurst++;
            g_barcodeFilled++;
            g_barcodeLastFireTime = TimeCurrent();
         }
         else
         {
            uint ret = trade.ResultRetcode();
            if(ret == TRADE_RETCODE_NO_MONEY || ret == 10019)
            {
               g_learnedMinMargin = MathMax(g_learnedMinMargin, AccountInfoDouble(ACCOUNT_MARGIN_FREE) + 2.0);
            }
            PrintFormat("⚠️ [BARCODE RETRY LATER]: Order send paused (code %u: %s). Free Margin: $%.2f",
                        ret, trade.ResultRetcodeDescription(), AccountInfoDouble(ACCOUNT_MARGIN_FREE));
            break;
         }
      }
   }

   if(firedInThisBurst > 0)
   {
      double effTPDist = (InpStopTPDistance > 0.0) ? InpStopTPDistance : g_activeTPDist;
      int currentOpen = GetBarcodePositionsCount(targetPosType);
      PrintFormat("⚡ [BARCODE BURST]: Fired %d stripes! Current Open: %d/%d (Free Margin: $%.2f | TP: +$%.0f)",
                  firedInThisBurst, currentOpen, g_barcodeTarget, AccountInfoDouble(ACCOUNT_MARGIN_FREE), effTPDist);
      UpdateHUDStatus();

      if(currentOpen - g_barcodeBaseOpenCount >= g_barcodeTarget)
      {
         PrintFormat("🎉 [BARCODE FULLY FILLED]: All %d/%d stripes successfully filled on %s!", 
                     g_barcodeTarget, g_barcodeTarget, _Symbol);
         g_barcodeActive = false;
         ClearBarcodeGlobals();
         g_barcodeMaxLiveSeen = 0;
         g_mcpSL = 0.0; g_mcpTP = 0.0;
         UpdateHUDStatus();
      }
      else
      {
         SaveBarcodeGlobals();
      }
   }
}

void ExecuteBarcode(ENUM_ORDER_TYPE orderType, double customLot = 0.0, double customSL = 0.0, double customTP = 0.0)
{
   double lot = (customLot > 0.0) ? customLot : g_currentLot;
   int stripes = (g_currentStripes > 0) ? g_currentStripes : InpNumberOfStripes;
   StartBarcodeEngine(orderType, stripes, lot, customSL, customTP);
}

void ArmSpikeLimits(ENUM_ORDER_TYPE orderType)
{
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double marginForOneLot = GetMarginRequired(ORDER_TYPE_BUY, 1.0);
   if(marginForOneLot <= 0.0) marginForOneLot = 4128.0;

   double targetMargin = freeMargin * (MathMin(InpMarginPercent, 95.0) / 100.0);

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
         bool res = trade.SellLimit(stripeLot, p, _Symbol, 0.0, tp, ORDER_TIME_SPECIFIED, expiry, "Spike Sell Limit");
         if(!res && (trade.ResultRetcode() == TRADE_RETCODE_INVALID_EXPIRATION || trade.ResultRetcode() == 10022))
         {
            res = trade.SellLimit(stripeLot, p, _Symbol, 0.0, tp, ORDER_TIME_GTC, 0, "Spike Sell Limit");
         }
         if(res) placed++;
      }
      else
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double p = NormalizeDouble(bid - offset, digits);
         double tp = (g_activeTPDist > 0) ? NormalizeDouble(p + g_activeTPDist, digits) : 0.0;
         bool res = trade.BuyLimit(stripeLot, p, _Symbol, 0.0, tp, ORDER_TIME_SPECIFIED, expiry, "Spike Buy Limit");
         if(!res && (trade.ResultRetcode() == TRADE_RETCODE_INVALID_EXPIRATION || trade.ResultRetcode() == 10022))
         {
            res = trade.BuyLimit(stripeLot, p, _Symbol, 0.0, tp, ORDER_TIME_GTC, 0, "Spike Buy Limit");
         }
         if(res) placed++;
      }
   }
   PrintFormat("✅ SPIKE LIMITS ARMED on %s: %d/%d orders placed at %.2f lots each (Total: ~%.2f lots, Base Wick Offset: $%.2f, Step: $%.2f, TP: +$%.2f)", 
               _Symbol, placed, numStripes, stripeLot, (stripeLot * placed), g_activeSpikeOffset, InpLadderStep, g_activeTPDist);
}

void ExecuteEmergencyClose()
{
   g_barcodeActive = false;
   ClearBarcodeGlobals();
   g_barcodeMaxLiveSeen = 0;
   g_mcpSL = 0.0; g_mcpTP = 0.0; g_mcpArmedRun = false;
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

   trade.SetTypeFilling(GetFillingMode());

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
      request.type_filling = GetFillingMode();

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
   double dist = InpStopDistance;
   if(StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0)
   {
      dist = InpStopDistance * GetPipSize();
   }

   // Minimum broker stop level check
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minAllowedDist = (double)stopsLevel * point;
   if(dist < minAllowedDist) dist = minAllowedDist;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double tpDist = (InpStopTPDistance > 0.0) ? InpStopTPDistance : g_activeTPDist;

   g_straddleBuyTrigger  = NormalizeDouble(ask + dist, digits);
   g_straddleSellTrigger = NormalizeDouble(bid - dist, digits);
   double buyTP          = NormalizeDouble(g_straddleBuyTrigger + tpDist, digits);
   double sellTP         = NormalizeDouble(g_straddleSellTrigger - tpDist, digits);

   g_straddleArmed = true;
   g_straddleArmTime = TimeCurrent();

   // Persist armed state in Terminal Global Variables so timeframe changes NEVER wipe out armed stops!
   string gvPrefix = StringFormat("AION_%s_", _Symbol);
   GlobalVariableSet(gvPrefix + "ARMED", 1.0);
   GlobalVariableSet(gvPrefix + "BUY_TRIG", g_straddleBuyTrigger);
   GlobalVariableSet(gvPrefix + "SELL_TRIG", g_straddleSellTrigger);
   GlobalVariableSet(gvPrefix + "BUY_TP", buyTP);
   GlobalVariableSet(gvPrefix + "SELL_TP", sellTP);
   GlobalVariableSet(gvPrefix + "ARM_TIME", (double)g_straddleArmTime);

   DrawStraddleLines(g_straddleBuyTrigger, buyTP, g_straddleSellTrigger, sellTP);
   UpdateHUDStatus();

   PrintFormat("⚡ [BREAKOUT WATCH ARMED [G]]: %s | Buy Stop: %.2f (TP: %.2f) | Sell Stop: %.2f (TP: %.2f) | Barcode: %dx %.2f",
               _Symbol, g_straddleBuyTrigger, buyTP, g_straddleSellTrigger, sellTP, g_currentStripes, g_currentLot);
}

void RemoveChartTextClutter()
{
   ChartSetInteger(0, CHART_SHOW_OBJECT_DESCR, false);
   ChartSetInteger(0, CHART_SHOW_TRADE_HISTORY, false);

   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      
      // Never delete our own UI panel elements
      if(StringFind(name, "BTN_") == 0 || StringFind(name, "LBL_") == 0 ||
         StringFind(name, "BOX_") == 0 || StringFind(name, "EDT_") == 0 ||
         StringFind(name, "LINE_STRADDLE") == 0)
      {
         continue;
      }
      
      ENUM_OBJECT type = (ENUM_OBJECT)ObjectGetInteger(0, name, OBJPROP_TYPE);
      if(type == OBJ_ARROW || type == OBJ_ARROW_BUY || type == OBJ_ARROW_SELL ||
         type == OBJ_ARROW_CHECK || type == OBJ_ARROW_DOWN || type == OBJ_ARROW_UP ||
         type == OBJ_ARROW_STOP || type == OBJ_TEXT)
      {
         ObjectDelete(0, name);
      }
      else if(type == OBJ_TREND)
      {
         string text = ObjectGetString(0, name, OBJPROP_TEXT);
         if(StringFind(text, "->") >= 0 || StringFind(name, "#") >= 0)
         {
            ObjectDelete(0, name);
         }
      }
   }
   ChartRedraw(0);
}

void DrawStraddleLines(double buyTrig, double buyTP, double sellTrig, double sellTP)
{
   // Turn off text clutter globally across the chart
   RemoveChartTextClutter();

   double tpDist = (InpStopTPDistance > 0.0) ? InpStopTPDistance : g_activeTPDist;

   // 1. BUY STOP TRIGGER LINE (Lime Green, Solid, Width 2, Selectable)
   ObjectDelete(0, "LINE_STRADDLE_BUY");
   ObjectCreate(0, "LINE_STRADDLE_BUY", OBJ_HLINE, 0, 0, buyTrig);
   ObjectSetInteger(0, "LINE_STRADDLE_BUY", OBJPROP_COLOR, clrLime);
   ObjectSetInteger(0, "LINE_STRADDLE_BUY", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, "LINE_STRADDLE_BUY", OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, "LINE_STRADDLE_BUY", OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, "LINE_STRADDLE_BUY", OBJPROP_SELECTED, false);
   ObjectSetString(0, "LINE_STRADDLE_BUY", OBJPROP_TOOLTIP, StringFormat("BUY STOP Trigger (+$%.0f)", InpStopDistance));

   // 2. BUY STOP TAKE PROFIT LINE (Mint Green, Dashed, Width 2, Selectable)
   ObjectDelete(0, "LINE_STRADDLE_BUY_TP");
   ObjectCreate(0, "LINE_STRADDLE_BUY_TP", OBJ_HLINE, 0, 0, buyTP);
   ObjectSetInteger(0, "LINE_STRADDLE_BUY_TP", OBJPROP_COLOR, C'52,211,153');
   ObjectSetInteger(0, "LINE_STRADDLE_BUY_TP", OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, "LINE_STRADDLE_BUY_TP", OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, "LINE_STRADDLE_BUY_TP", OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, "LINE_STRADDLE_BUY_TP", OBJPROP_SELECTED, false);
   ObjectSetString(0, "LINE_STRADDLE_BUY_TP", OBJPROP_TOOLTIP, StringFormat("BUY TP (+$%.0f)", tpDist));

   // 3. SELL STOP TRIGGER LINE (Neon Red, Solid, Width 2, Selectable)
   ObjectDelete(0, "LINE_STRADDLE_SELL");
   ObjectCreate(0, "LINE_STRADDLE_SELL", OBJ_HLINE, 0, 0, sellTrig);
   ObjectSetInteger(0, "LINE_STRADDLE_SELL", OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, "LINE_STRADDLE_SELL", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, "LINE_STRADDLE_SELL", OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, "LINE_STRADDLE_SELL", OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, "LINE_STRADDLE_SELL", OBJPROP_SELECTED, false);
   ObjectSetString(0, "LINE_STRADDLE_SELL", OBJPROP_TOOLTIP, StringFormat("SELL STOP Trigger (-$%.0f)", InpStopDistance));

   // 4. SELL STOP TAKE PROFIT LINE (Coral Red, Dashed, Width 2, Selectable)
   ObjectDelete(0, "LINE_STRADDLE_SELL_TP");
   ObjectCreate(0, "LINE_STRADDLE_SELL_TP", OBJ_HLINE, 0, 0, sellTP);
   ObjectSetInteger(0, "LINE_STRADDLE_SELL_TP", OBJPROP_COLOR, C'248,113,113');
   ObjectSetInteger(0, "LINE_STRADDLE_SELL_TP", OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, "LINE_STRADDLE_SELL_TP", OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, "LINE_STRADDLE_SELL_TP", OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, "LINE_STRADDLE_SELL_TP", OBJPROP_SELECTED, false);
   ObjectSetString(0, "LINE_STRADDLE_SELL_TP", OBJPROP_TOOLTIP, StringFormat("SELL TP (-$%.0f)", tpDist));

   ChartRedraw(0);
}

void DisarmStraddleWatch()
{
   string gvPrefix = StringFormat("AION_%s_", _Symbol);
   GlobalVariableDel(gvPrefix + "ARMED");
   GlobalVariableDel(gvPrefix + "BUY_TRIG");
   GlobalVariableDel(gvPrefix + "SELL_TRIG");
   GlobalVariableDel(gvPrefix + "BUY_TP");
   GlobalVariableDel(gvPrefix + "SELL_TP");
   GlobalVariableDel(gvPrefix + "ARM_TIME");

   if(!g_straddleArmed && ObjectFind(0, "LINE_STRADDLE_BUY") < 0 && ObjectFind(0, "LINE_STRADDLE_SELL") < 0) return;
   
   g_straddleArmed = false;
   g_straddleBuyTrigger = 0.0;
   g_straddleSellTrigger = 0.0;
   g_straddleArmTime = 0;

   ObjectDelete(0, "LINE_STRADDLE_BUY");
   ObjectDelete(0, "LINE_STRADDLE_BUY_TP");
   ObjectDelete(0, "LINE_STRADDLE_SELL");
   ObjectDelete(0, "LINE_STRADDLE_SELL_TP");

   RemoveChartTextClutter();

   // Restore natural flexible price scaling
   ChartSetInteger(0, CHART_SCALEFIX, false);

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
         PrintFormat("⏳ [BREAKOUT WATCH EXPIRED]: %d minute timeout reached without breakout. Disarming...", InpStopExpiryMins);
         DisarmStraddleWatch();
         return;
      }
   }

   // Sync dynamic trigger levels if user moved lines on chart
   if(ObjectFind(0, "LINE_STRADDLE_BUY") >= 0)
   {
      double p = ObjectGetDouble(0, "LINE_STRADDLE_BUY", OBJPROP_PRICE);
      if(p > 0.0) g_straddleBuyTrigger = p;
   }
   if(ObjectFind(0, "LINE_STRADDLE_SELL") >= 0)
   {
      double p = ObjectGetDouble(0, "LINE_STRADDLE_SELL", OBJPROP_PRICE);
      if(p > 0.0) g_straddleSellTrigger = p;
   }

   double buyTPFromLine = 0.0, sellTPFromLine = 0.0;
   if(ObjectFind(0, "LINE_STRADDLE_BUY_TP") >= 0)
      buyTPFromLine = ObjectGetDouble(0, "LINE_STRADDLE_BUY_TP", OBJPROP_PRICE);
   if(ObjectFind(0, "LINE_STRADDLE_SELL_TP") >= 0)
      sellTPFromLine = ObjectGetDouble(0, "LINE_STRADDLE_SELL_TP", OBJPROP_PRICE);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0) return; // Guard against broker disconnect/zero-quote glitch
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double tpDist = (InpStopTPDistance > 0.0) ? InpStopTPDistance : g_activeTPDist;

   // 1. Upward Breakout
   if(ask >= g_straddleBuyTrigger && g_straddleBuyTrigger > 0.0)
   {
      double triggerLvl = g_straddleBuyTrigger;
      DisarmStraddleWatch(); // Immediately disarm to prevent duplicate firing

      double sl = 0.0;
      if(InpStopSLDistance > 0.0)
         sl = NormalizeDouble(ask - InpStopSLDistance, digits);

      double tp = 0.0;
      if(buyTPFromLine > ask)
         tp = NormalizeDouble(buyTPFromLine, digits);
      else if(tpDist > 0.0)
         tp = NormalizeDouble(ask + tpDist, digits);

      PrintFormat("🚀🚀 [BREAKOUT BUY TRIGGERED]: Ask %.2f crossed trigger %.2f (+$%.2f / %.1fp)! Firing %d barcode stripes at %.2f lots (SL: %.2f | TP: %.2f)...",
                  ask, triggerLvl, InpStopDistance, InpStopDistance * 10.0, g_currentStripes, g_currentLot, sl, tp);
      ExecuteBarcode(ORDER_TYPE_BUY, 0.0, sl, tp);
      return;
   }

   // 2. Downward Breakout
   if(bid <= g_straddleSellTrigger && g_straddleSellTrigger > 0.0)
   {
      double triggerLvl = g_straddleSellTrigger;
      DisarmStraddleWatch(); // Immediately disarm to prevent duplicate firing

      double sl = 0.0;
      if(InpStopSLDistance > 0.0)
         sl = NormalizeDouble(bid + InpStopSLDistance, digits);

      double tp = 0.0;
      if(sellTPFromLine > 0.0 && sellTPFromLine < bid)
         tp = NormalizeDouble(sellTPFromLine, digits);
      else if(tpDist > 0.0)
         tp = NormalizeDouble(bid - tpDist, digits);

      PrintFormat("🚀🚀 [BREAKOUT SELL TRIGGERED]: Bid %.2f crossed trigger %.2f (-$%.2f / %.1fp)! Firing %d barcode stripes at %.2f lots (SL: %.2f | TP: %.2f)...",
                  bid, triggerLvl, InpStopDistance, InpStopDistance * 10.0, g_currentStripes, g_currentLot, sl, tp);
      ExecuteBarcode(ORDER_TYPE_SELL, 0.0, sl, tp);
      return;
   }
}

//+------------------------------------------------------------------+
//| MCP COMMAND LINK                                                 |
//| File-based command queue so the external MCP agent calls the     |
//| exact same functions as the panel buttons and hotkeys.           |
//|                                                                  |
//| Protocol (MQL5/Files):                                           |
//|   mcp_cmd.txt line 1: COMMAND [args...]                          |
//|   mcp_cmd.txt line 2: TS=<TimeGMT seconds> NONCE=<unique token>   |
//|   mcp_ack.txt: STATUS NONCE detail...  (STATUS = OK or ERR)       |
//| Fire commands take atomic SL=/TP= (absolute prices):             |
//|   BUY_BARCODE SL=4125.20 TP=4131.20                              |
//| Safety: single-use file (deleted on read), 60s freshness window, |
//| nonce replay guard, whitelisted commands only, gated behind      |
//| InpAllowMCP. Naked MCP fires refused while InpMCPMaxRiskUSD > 0;  |
//| computed risk must fit the cap. Every command is journaled and   |
//| shown on the panel.                                              |
//+------------------------------------------------------------------+
void WriteMCPAck(string status, string nonce, string detail)
{
   int h = FileOpen(MCP_ACK_FILE, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h == INVALID_HANDLE) return;
   FileWriteString(h, StringFormat("%s %s %s\n", status, nonce, detail));
   FileClose(h);
}

void PollMCPCommand()
{
   // Throttle: ~5 checks/sec on the 50ms timer is plenty for an agent link
   static int tick = 0;
   if((tick++ % 4) != 0) return;

   string found = "";
   long search = FileFindFirst(MCP_CMD_FILE, found);
   if(search == INVALID_HANDLE) return;
   FileFindClose(search);

   int h = FileOpen(MCP_CMD_FILE, FILE_READ|FILE_TXT|FILE_ANSI);
   if(h == INVALID_HANDLE) return;
   string cmdLine = "";
   string metaLine = "";
   if(!FileIsEnding(h)) cmdLine = FileReadString(h);
   if(!FileIsEnding(h)) metaLine = FileReadString(h);
   FileClose(h);
   StringTrimRight(cmdLine); StringTrimLeft(cmdLine);
   StringTrimRight(metaLine); StringTrimLeft(metaLine);

   // Parse "TS=<n> NONCE=<token>"
   long ts = 0;
   string nonce = "";
   string meta[];
   int m = StringSplit(metaLine, ' ', meta);
   for(int i = 0; i < m; i++)
   {
      if(StringFind(meta[i], "TS=") == 0)
         ts = StringToInteger(StringSubstr(meta[i], 3));
      else if(StringFind(meta[i], "NONCE=") == 0)
         nonce = StringSubstr(meta[i], 6);
   }

   // Single-use: consume immediately so nothing can execute twice
   FileDelete(MCP_CMD_FILE);

   if(cmdLine == "" || nonce == "")
   {
      WriteMCPAck("ERR", nonce, "MALFORMED expected 'COMMAND [args]' + 'TS=<n> NONCE=<t>'");
      return;
   }
   if(nonce == g_mcpLastNonce)
   {
      WriteMCPAck("ERR", nonce, "DUPLICATE nonce already executed");
      return;
   }
   if(MathAbs((long)TimeGMT() - ts) > MCP_CMD_MAX_AGE_SEC)
   {
      WriteMCPAck("ERR", nonce, "STALE command older than 60s");
      return;
   }
   if(!InpAllowMCP)
   {
      WriteMCPAck("ERR", nonce, "DISABLED set InpAllowMCP=true to arm the link");
      PrintFormat("MCP CMD REJECTED (link off): %s", cmdLine);
      return;
   }

   g_mcpLastNonce = nonce;
   bool ok = false;
   string detail = ExecuteMCPCommand(cmdLine, ok);
   string word = cmdLine;
   int sp = StringFind(cmdLine, " ");
   if(sp > 0) word = StringSubstr(cmdLine, 0, sp);
   StringToUpper(word);
   g_mcpLastCmd = word;
   g_mcpLastResult = StringSubstr((ok ? "OK " : "ERR ") + detail, 0, 72);
   g_mcpLastCmdTime = TimeCurrent();
   WriteMCPAck(ok ? "OK" : "ERR", nonce, detail);
   PrintFormat("MCP CMD %s: %s -> %s", ok ? "OK" : "ERR", cmdLine, detail);
   UpdateHUDStatus();
}

string ExecuteMCPCommand(string cmdLine, bool &ok)
{
   ok = false;
   string raw[];
   int n = StringSplit(cmdLine, ' ', raw);
   string parts[];
   ArrayResize(parts, n);
   int c = 0;
   for(int i = 0; i < n; i++)
   {
      string t = raw[i];
      StringTrimRight(t); StringTrimLeft(t);
      if(t != "") { parts[c] = t; c++; }
   }
   if(c == 0) return "EMPTY command";
   ArrayResize(parts, c);
   string cmd = parts[0];
   StringToUpper(cmd);

   if(cmd == "PING")
   {
      ok = true;
      return StringFormat("EA alive | equity $%.2f | positions %d | orders %d | straddle %s",
                          AccountInfoDouble(ACCOUNT_EQUITY), PositionsTotal(), OrdersTotal(),
                          g_straddleArmed ? "ARMED" : "OFF");
   }
   if(cmd == "STATUS")
   {
      ok = true;
      return StringFormat("lot=%.2f stripes=%d spike=$%.0f tp=+$%.0f barcode=%s straddle=%s autopilot=%s",
                          g_currentLot, g_currentStripes, g_activeSpikeOffset, g_activeTPDist,
                          g_barcodeActive ? "ACTIVE" : "IDLE", g_straddleArmed ? "ARMED" : "OFF",
                          InpEnableAutoPilot ? "ON" : "OFF");
   }
   if(cmd == "SET_LOT")
   {
      if(c < 2) return "SET_LOT needs a value, e.g. SET_LOT 0.10";
      double v = NormalizeDouble(StringToDouble(parts[1]), 2);
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if(minLot <= 0) minLot = 0.01;
      if(maxLot <= 0) maxLot = 50.0;
      if(step <= 0) step = 0.01;
      if(v < minLot || v > maxLot) return StringFormat("lot %.2f outside broker range %.2f-%.2f", v, minLot, maxLot);
      v = MathFloor(v / step + 0.5) * step;
      v = NormalizeDouble(v, 2);
      g_currentLot = v;
      ObjectSetString(0, "EDT_LOT_SIZE", OBJPROP_TEXT, DoubleToString(v, 2));
      ok = true;
      return StringFormat("lot=%.2f", v);
   }
   if(cmd == "SET_STRIPES")
   {
      if(c < 2) return "SET_STRIPES needs a value, e.g. SET_STRIPES 20";
      int v = (int)StringToInteger(parts[1]);
      if(v < 1 || v > 100) return "stripes must be 1-100";
      g_currentStripes = v;
      ok = true;
      return StringFormat("stripes=%d", v);
   }
   if(cmd == "BUY_BARCODE")
      return MCPFireBarcode(ORDER_TYPE_BUY, parts, c, ok);
   if(cmd == "SELL_BARCODE")
      return MCPFireBarcode(ORDER_TYPE_SELL, parts, c, ok);
   if(cmd == "BUY_LIMIT" || cmd == "SELL_LIMIT" || cmd == "STRADDLE")
   {
      for(int i = 1; i < c; i++)
      {
         string a = parts[i]; StringToUpper(a);
         if(StringFind(a, "SL=") == 0 || StringFind(a, "TP=") == 0)
            return "SL=/TP= supported on BUY_BARCODE/SELL_BARCODE only";
      }
   }
   if(cmd == "BUY_LIMIT")
   {
      ArmSpikeLimits(ORDER_TYPE_BUY_LIMIT);
      ok = true;
      return StringFormat("buy limits armed | wick $%.0f", g_activeSpikeOffset);
   }
   if(cmd == "SELL_LIMIT")
   {
      ArmSpikeLimits(ORDER_TYPE_SELL_LIMIT);
      ok = true;
      return StringFormat("sell limits armed | wick $%.0f", g_activeSpikeOffset);
   }
   if(cmd == "STRADDLE")
   {
      ExecuteStraddleStops();
      ok = true;
      return g_straddleArmed ? StringFormat("watch ARMED (+-$%.0f)", InpStopDistance) : "watch DISARMED";
   }
   if(cmd == "PANIC_CLOSE")
   {
      int p = PositionsTotal();
      int o = OrdersTotal();
      ExecuteEmergencyClose();
      ok = true;
      return StringFormat("flattened %d positions %d orders", p, o);
   }
   return "UNKNOWN_COMMAND " + parts[0];
}

// Absolute-price SL/TP must sit on the correct side with broker stops-level clearance.
// Zero values mean "unset" and skip that side's checks.
bool MCPProtectionValid(double bid, double ask, double sl, double tp, ENUM_ORDER_TYPE type, string &reason)
{
   reason = "";
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0) point = 0.01;
   double stopMin = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
   if(type == ORDER_TYPE_BUY)
   {
      if(sl > 0.0)
      {
         if(!(sl < bid)) { reason = "BUY needs SL below bid"; return false; }
         if(bid - sl < stopMin) { reason = "SL inside stops level"; return false; }
      }
      if(tp > 0.0)
      {
         if(!(tp > ask)) { reason = "BUY needs TP above ask"; return false; }
         if(tp - ask < stopMin) { reason = "TP inside stops level"; return false; }
      }
   }
   else
   {
      if(sl > 0.0)
      {
         if(!(sl > ask)) { reason = "SELL needs SL above ask"; return false; }
         if(sl - ask < stopMin) { reason = "SL inside stops level"; return false; }
      }
      if(tp > 0.0)
      {
         if(!(tp < bid)) { reason = "SELL needs TP below bid"; return false; }
         if(bid - tp < stopMin) { reason = "TP inside stops level"; return false; }
      }
   }
   return true;
}

// MCP barcode fire with optional atomic SL=/TP= (absolute prices).
// Enforces the EA-side dollar risk cap: when InpMCPMaxRiskUSD > 0, naked MCP
// fires are refused and computed worst-case risk must fit the cap.
string MCPFireBarcode(ENUM_ORDER_TYPE type, string &parts[], int count, bool &ok)
{
   ok = false;
   double sl = 0.0, tp = 0.0;
   for(int i = 1; i < count; i++)
   {
      string a = parts[i];
      int eq = StringFind(a, "=");
      if(eq <= 0) return "bad arg '" + a + "' (use SL=<price> TP=<price>)";
      string k = StringSubstr(a, 0, eq); StringToUpper(k);
      double v = StringToDouble(StringSubstr(a, eq + 1));
      if(k == "SL") sl = v;
      else if(k == "TP") tp = v;
      else return "unknown arg '" + k + "' (use SL=<price> TP=<price>)";
   }
   if(sl < 0.0 || tp < 0.0) return "SL/TP must be positive prices";

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   string reason = "";
   if(!MCPProtectionValid(bid, ask, sl, tp, type, reason))
      return "invalid protection: " + reason;

   int stripes = (g_currentStripes > 0) ? g_currentStripes : InpNumberOfStripes;
   double lot = g_currentLot;
   double risk = 0.0;
   if(sl > 0.0)
   {
      double entry = (type == ORDER_TYPE_BUY) ? ask : bid;
      double contract = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      if(contract <= 0.0) contract = 100.0;
      risk = stripes * lot * MathAbs(entry - sl) * contract;
   }
   if(InpMCPMaxRiskUSD > 0.0)
   {
      if(sl <= 0.0)
         return StringFormat("naked MCP fire refused: EA risk cap $%.2f requires SL=", InpMCPMaxRiskUSD);
      if(risk > InpMCPMaxRiskUSD)
         return StringFormat("risk $%.2f exceeds EA cap $%.2f (cut stripes/lot or tighten SL)", risk, InpMCPMaxRiskUSD);
   }

   g_mcpSL = sl; g_mcpTP = tp; g_mcpArmedRun = true;
   ExecuteBarcode(type, 0.0, sl, tp);
   ok = true;
   if(sl > 0.0)
      return StringFormat("engine started %d stripes x %.2f SL=%.2f TP=%.2f risk~$%.2f (fills async, verify positions)",
                          stripes, lot, sl, tp, risk);
   return StringFormat("engine started %d stripes x %.2f NO PROTECTION (EA cap disabled)", stripes, lot);
}
