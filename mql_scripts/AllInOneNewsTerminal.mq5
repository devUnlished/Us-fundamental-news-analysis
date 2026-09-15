//+------------------------------------------------------------------+
//|                                     AllInOneNewsTerminal.mq5     |
//|            High-Impact News Execution & Liquidation Engine       |
//|    NEW: On-Screen Interactive LOT INPUT BOX directly on HUD!     |
//|    Click [-] or [+] or edit lot directly on screen!              |
//+------------------------------------------------------------------+
#property copyright "News Sniper Terminal"
#property link      "https://github.com/devUnlished/Us-fundamental-news-analysis"
#property version   "4.00"

#include <Trade\Trade.mqh>

input group "=== BARCODE SETTINGS ===";
input int      InpNumberOfStripes   = 10;      // Number of barcode stripes per trigger
input double   InpDefaultLot        = 0.05;    // Starting Lot size per stripe

input group "=== DYNAMIC TAKE PROFIT ===";
input bool     InpEnableDynamicTP   = true;    // Auto-set TP based on Expected News Pips
input double   InpDefaultTPDistance = 4.00;    // Default TP in Gold $ (e.g. $4.00 = 40 pips)

input group "=== EMERGENCY CLOSE ===";
input int      InpMaxRetries        = 50;      // Retry attempts on broker requote
input int      InpSlippagePoints    = 300;     // Slippage allowance in points (30 pips)

CTrade trade;
double g_currentLot = 0.05;
string g_activeNewsName = "None";

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
   int startY = 50;
   int btnW = 135;
   int btnH = 38;
   int gap = 6;

   // Row 1: Interactive Lot Size Controller
   CreateButton("BTN_LOT_MINUS", "-", startX, startY, 32, 28, C'30,41,59', clrWhite, 12);
   CreateEditBox("EDT_LOT_SIZE", DoubleToString(g_currentLot, 2), startX + 34, startY, 65, 28);
   CreateButton("BTN_LOT_PLUS", "+", startX + 101, startY, 32, 28, C'30,41,59', clrWhite, 12);
   
   // Preset Quick Lot Buttons: [0.01] [0.05] [0.10] [0.20]
   CreateButton("BTN_LOT_001", ".01", startX + 138, startY, 32, 28, C'15,23,42', C'148,163,184', 8);
   CreateButton("BTN_LOT_005", ".05", startX + 172, startY, 32, 28, C'15,23,42', C'148,163,184', 8);
   CreateButton("BTN_LOT_010", ".10", startX + 206, startY, 32, 28, C'15,23,42', C'148,163,184', 8);
   CreateButton("BTN_LOT_020", ".20", startX + 240, startY, 32, 28, C'15,23,42', C'148,163,184', 8);

   // Row 2: Big Buy / Sell Barcode
   int row2Y = startY + 34;
   CreateButton("BTN_BUY",  "▲ BUY BARCODE [B]",  startX, row2Y, btnW, btnH, C'22,163,74', clrWhite);
   CreateButton("BTN_SELL", "▼ SELL BARCODE [S]", startX + btnW + gap, row2Y, btnW, btnH, C'220,38,38', clrWhite);

   // Row 3: Panic Close Kill Switch
   int row3Y = row2Y + btnH + gap;
   CreateButton("BTN_CLOSE", "✖ PANIC CLOSE ALL [X]", startX, row3Y, (btnW * 2) + gap, 40, C'185,28,28', clrWhite);

   // Row 4: Live Status Bar
   int row4Y = row3Y + 44;
   ObjectDelete(0, "LBL_STATUS");
   ObjectCreate(0, "LBL_STATUS", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "LBL_STATUS", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "LBL_STATUS", OBJPROP_XDISTANCE, startX);
   ObjectSetInteger(0, "LBL_STATUS", OBJPROP_YDISTANCE, row4Y);
   ObjectSetString(0, "LBL_STATUS", OBJPROP_FONT, "Segoe UI");
   ObjectSetInteger(0, "LBL_STATUS", OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, "LBL_STATUS", OBJPROP_COLOR, C'148,163,184');
}

double GetDynamicExpectedTP()
{
   if(!InpEnableDynamicTP) return InpDefaultTPDistance;
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
            if(StringFind(low, "nonfarm") >= 0 || StringFind(low, "cpi") >= 0 || StringFind(low, "interest rate") >= 0 || StringFind(low, "fomc") >= 0)
            {
               g_activeNewsName = ev.name;
               return 8.00; // Tier 1: ~80 pips
            }
            else if(StringFind(low, "retail sales") >= 0 || StringFind(low, "pce") >= 0 || StringFind(low, "gdp") >= 0)
            {
               g_activeNewsName = ev.name;
               return 5.00; // Tier 2: ~50 pips
            }
            else if(StringFind(low, "jobless") >= 0 || StringFind(low, "sentiment") >= 0 || StringFind(low, "adp") >= 0)
            {
               g_activeNewsName = ev.name;
               return 3.00; // Tier 3: ~30 pips
            }
         }
      }
   }
   return InpDefaultTPDistance;
}

void UpdateHUDStatus()
{
   // Read lot size directly from the HUD edit box if edited by user
   string textVal = ObjectGetString(0, "EDT_LOT_SIZE", OBJPROP_TEXT);
   double enteredLot = StringToDouble(textVal);
   if(enteredLot >= 0.01 && enteredLot <= 50.0)
   {
      g_currentLot = NormalizeDouble(enteredLot, 2);
   }

   double tpDist = GetDynamicExpectedTP();
   string info = StringFormat("Active Stripe: %.2f (x10 = %.2f lots total) | Dynamic TP: +$%.2f (%s)", 
                              g_currentLot, g_currentLot * InpNumberOfStripes, tpDist, g_activeNewsName);
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
   PrintFormat(">>> NEWS TERMINAL 4.00 ACTIVE ON %s <<<", _Symbol);
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
      else if(lparam == 88 || lparam == 120) ExecuteEmergencyClose(); // X
   }
}

void ExecuteBarcode(ENUM_ORDER_TYPE orderType)
{
   UpdateHUDStatus();
   double tpDist = GetDynamicExpectedTP();
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   int filled = 0;
   for(int i = 0; i < InpNumberOfStripes; i++)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if(orderType == ORDER_TYPE_SELL)
      {
         double tp = (tpDist > 0) ? NormalizeDouble(bid - tpDist, digits) : 0.0;
         if(trade.Sell(g_currentLot, _Symbol, bid, 0.0, tp, "Barcode Stripe")) filled++;
      }
      else
      {
         double tp = (tpDist > 0) ? NormalizeDouble(ask + tpDist, digits) : 0.0;
         if(trade.Buy(g_currentLot, _Symbol, ask, 0.0, tp, "Barcode Stripe")) filled++;
      }
      Sleep(20);
   }
   PrintFormat("✅ BARCODE COMPLETED: %d/%d stripes filled at %.2f lots on %s (TP: +$%.2f, NO SL)", 
               filled, InpNumberOfStripes, g_currentLot, _Symbol, tpDist);
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

   Alert(StringFormat("🚨 EMERGENCY CLOSE: Liquidated %d positions on %s!", closed, _Symbol));
}
