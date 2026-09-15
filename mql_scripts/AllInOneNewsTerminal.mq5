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
input int      InpLimitExpiryMins   = 15;      // Auto-cancel unfilled limits after N minutes

input group "=== EMERGENCY CLOSE ===";
input int      InpMaxRetries        = 50;      // Retry attempts on broker requote
input int      InpSlippagePoints    = 300;     // Slippage allowance in points (30 pips)

CTrade trade;
double g_currentLot = 0.05;
string g_activeNewsName = "Standby (Normal)";
double g_activeSpikeOffset = 18.00; // in Gold dollars ($18.00 = 180 pips)
double g_activeTPDist = 30.00;      // in Gold dollars ($30.00 = 300 pips)
string g_activeTier = "STANDARD";

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
   int startY = 45;
   int btnW = 140;
   int btnH = 36;
   int gap = 6;

   // Row 1: Lot Selector
   CreateButton("BTN_LOT_MINUS", "-", startX, startY, 30, 26, C'30,41,59', clrWhite, 11);
   CreateEditBox("EDT_LOT_SIZE", DoubleToString(g_currentLot, 2), startX + 32, startY, 60, 26);
   CreateButton("BTN_LOT_PLUS", "+", startX + 94, startY, 30, 26, C'30,41,59', clrWhite, 11);
   
   CreateButton("BTN_LOT_001", ".01", startX + 128, startY, 36, 26, C'15,23,42', C'148,163,184', 8);
   CreateButton("BTN_LOT_005", ".05", startX + 166, startY, 36, 26, C'15,23,42', C'148,163,184', 8);
   CreateButton("BTN_LOT_010", ".10", startX + 204, startY, 36, 26, C'15,23,42', C'148,163,184', 8);
   CreateButton("BTN_LOT_020", ".20", startX + 242, startY, 36, 26, C'15,23,42', C'148,163,184', 8);

   // Row 2: Barcode Buy/Sell Buttons
   int r2 = startY + 32;
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
   CreateButton("BTN_CLOSE", "✖ PANIC CLOSE ALL [X]", startX, r4, (btnW * 2) + gap, 38, C'185,28,28', clrWhite);

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
   int count = CalendarValueHistory(values, now - 300, now + 300, "US");
   
   if(count > 0)
   {
      for(int i = 0; i < count; i++)
      {
         MqlCalendarEvent ev;
         if(CalendarEventById(values[i].event_id, ev))
         {
            string low = ev.name; StringToLower(low);
            double actual = (double)values[i].actual_value;
            double forecast = (double)values[i].forecast_value;
            double prev = (double)values[i].prev_value;
            double bench = (forecast != WRONG_VALUE) ? forecast : prev;
            double diff = (actual != WRONG_VALUE && bench != WRONG_VALUE) ? MathAbs(actual - bench) : 0.0;

            if(StringFind(low, "nonfarm") >= 0 || StringFind(low, "non farm") >= 0)
            {
               g_activeNewsName = "Nonfarm Payrolls (NFP)";
               if(diff > 68.0)      { g_activeTier = "BLOWOUT"; g_activeSpikeOffset = 25.0; g_activeTPDist = 55.0; } // 250 pip wick, 550 pip TP
               else if(diff > 30.0) { g_activeTier = "SOLID";   g_activeSpikeOffset = 20.0; g_activeTPDist = 45.0; } // 200 pip wick, 450 pip TP
               else                 { g_activeTier = "MODEST";  g_activeSpikeOffset = 18.0; g_activeTPDist = 25.0; } // 180 pip wick, 250 pip TP
               return;
            }
            else if(StringFind(low, "cpi") >= 0 || StringFind(low, "consumer price") >= 0)
            {
               g_activeNewsName = "Consumer Price Index (CPI)";
               if(diff > 0.25)      { g_activeTier = "BLOWOUT"; g_activeSpikeOffset = 22.0; g_activeTPDist = 50.0; } // 220 pip wick, 500 pip TP
               else if(diff > 0.12) { g_activeTier = "SOLID";   g_activeSpikeOffset = 16.0; g_activeTPDist = 38.0; } // 160 pip wick, 380 pip TP
               else                 { g_activeTier = "MODEST";  g_activeSpikeOffset = 12.0; g_activeTPDist = 25.0; } // 120 pip wick, 250 pip TP
               return;
            }
            else if(StringFind(low, "interest rate") >= 0 || StringFind(low, "fomc") >= 0)
            {
               g_activeNewsName = "FOMC Rate Decision";
               g_activeTier = "BLOWOUT"; g_activeSpikeOffset = 22.0; g_activeTPDist = 50.0;
               return;
            }
            else if(StringFind(low, "retail sales") >= 0 || StringFind(low, "pce") >= 0)
            {
               g_activeNewsName = ev.name;
               if(diff > 0.35)      { g_activeTier = "BLOWOUT"; g_activeSpikeOffset = 18.0; g_activeTPDist = 35.0; }
               else                 { g_activeTier = "SOLID";   g_activeSpikeOffset = 14.0; g_activeTPDist = 25.0; }
               return;
            }
         }
      }
   }
   
   // Fallback when standing by
   g_activeNewsName = "Standby (Pre-News)";
   g_activeTier = "STANDARD";
   g_activeSpikeOffset = InpFallbackSpikeDist;
   g_activeTPDist = InpFallbackTPDist;
}

void UpdateHUDStatus()
{
   string textVal = ObjectGetString(0, "EDT_LOT_SIZE", OBJPROP_TEXT);
   double enteredLot = StringToDouble(textVal);
   if(enteredLot >= 0.01 && enteredLot <= 50.0) g_currentLot = NormalizeDouble(enteredLot, 2);

   CalibrateNewsTargets();

   // Update Limit button texts with live calibrated spike wick distances
   ObjectSetString(0, "BTN_KLIMIT", OBJPROP_TEXT, StringFormat("K: BUY LIMIT (-$%.0f)", g_activeSpikeOffset));
   ObjectSetString(0, "BTN_LLIMIT", OBJPROP_TEXT, StringFormat("L: SELL LIMIT (+$%.0f)", g_activeSpikeOffset));

   string info = StringFormat("Active Stripe: %.2f (10x = %.2f lots) | Spike Wick: $%.0f (%d pips) | Target TP: +$%.0f (%d pips)", 
                              g_currentLot, g_currentLot * InpNumberOfStripes, g_activeSpikeOffset, (int)(g_activeSpikeOffset*10), g_activeTPDist, (int)(g_activeTPDist*10));
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
   EventSetTimer(1);
   PrintFormat(">>> NEWS TERMINAL 5.00 ACTIVE: Calibrated Wick Limits & Dynamic TP Running! <<<");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
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

void ExecuteBarcode(ENUM_ORDER_TYPE orderType)
{
   UpdateHUDStatus();
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   int filled = 0;
   for(int i = 0; i < InpNumberOfStripes; i++)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if(orderType == ORDER_TYPE_SELL)
      {
         double tp = (g_activeTPDist > 0) ? NormalizeDouble(bid - g_activeTPDist, digits) : 0.0;
         if(trade.Sell(g_currentLot, _Symbol, bid, 0.0, tp, "Barcode Stripe")) filled++;
      }
      else
      {
         double tp = (g_activeTPDist > 0) ? NormalizeDouble(ask + g_activeTPDist, digits) : 0.0;
         if(trade.Buy(g_currentLot, _Symbol, ask, 0.0, tp, "Barcode Stripe")) filled++;
      }
      Sleep(20);
   }
   PrintFormat("✅ BARCODE EXECUTED: %d/%d stripes filled at %.2f lots on %s (TP: +$%.2f [%d pips])", 
               filled, InpNumberOfStripes, g_currentLot, _Symbol, g_activeTPDist, (int)(g_activeTPDist*10));
}

void ArmSpikeLimits(ENUM_ORDER_TYPE orderType)
{
   UpdateHUDStatus();
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

   double halfLot = NormalizeDouble(totalLots / 2.0, 2);
   if(halfLot < 0.01) halfLot = totalLots;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   datetime expiry = TimeCurrent() + (InpLimitExpiryMins * 60);

   for(int i = 0; i < 2; i++)
   {
      double offset = g_activeSpikeOffset + (i * 3.0); // Split limit ladder
      if(orderType == ORDER_TYPE_SELL_LIMIT)
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double p = NormalizeDouble(ask + offset, digits);
         double tp = (g_activeTPDist > 0) ? NormalizeDouble(p - g_activeTPDist, digits) : 0.0;
         trade.SellLimit(halfLot, p, _Symbol, 0.0, tp, ORDER_TIME_SPECIFIED, expiry, "Spike Sell Limit");
      }
      else
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double p = NormalizeDouble(bid - offset, digits);
         double tp = (g_activeTPDist > 0) ? NormalizeDouble(p + g_activeTPDist, digits) : 0.0;
         trade.BuyLimit(halfLot, p, _Symbol, 0.0, tp, ORDER_TIME_SPECIFIED, expiry, "Spike Buy Limit");
      }
   }
   PrintFormat("✅ 80%% SPIKE LIMITS ARMED on %s (~%.2f lots, Wick Offset: +$%.0f, TP: +$%.0f)", 
               _Symbol, totalLots, g_activeSpikeOffset, g_activeTPDist);
}

void ExecuteEmergencyClose()
{
   int closed = 0;
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         int attempts = 0;
         while(attempts < InpMaxRetries)
         {
            attempts++;
            if(trade.PositionClose(ticket, InpSlippagePoints))
            {
               closed++;
               break;
            }
            Sleep(80);
         }
      }
   }

   int orders = OrdersTotal();
   for(int i = orders - 1; i >= 0; i--)
   {
      ulong oticket = OrderGetTicket(i);
      if(oticket > 0) trade.OrderDelete(oticket);
   }

   Alert(StringFormat("🚨 KILL SWITCH ACTIVATED: Liquidated %d positions on %s!", closed, _Symbol));
}
