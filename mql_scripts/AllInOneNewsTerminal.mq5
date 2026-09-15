//+------------------------------------------------------------------+
//|                                     AllInOneNewsTerminal.mq5     |
//|            High-Impact News Execution & Liquidation Engine       |
//|    Combines: Barcode Spammer, Spike Limits, and Emergency Close  |
//|    PURE MARKET EXECUTION: Zero SL / Zero TP (Manual Kill Switch) |
//+------------------------------------------------------------------+
#property copyright "News Sniper Terminal"
#property link      "https://github.com/devUnlished/Us-fundamental-news-analysis"
#property version   "3.00"

#include <Trade\Trade.mqh>

input group "=== 1. BARCODE SPAMMER SETTINGS ===";
input int      InpNumberOfStripes   = 8;       // Number of barcode stripes per trigger
input double   InpLotPerStripe      = 0.01;    // Lot size per stripe

input group "=== 2. SPIKE LIMIT SNIPER SETTINGS ===";
input double   InpMarginPercent     = 80.0;    // Margin to use for Limit Orders (% of Free Margin)
input double   InpSpikeDistance     = 2.00;    // Spike distance in Gold $ above/below market
input int      InpLimitExpiryMins   = 5;       // Auto-cancel unfilled limits after N minutes

input group "=== 3. EMERGENCY CLOSE SETTINGS ===";
input int      InpMaxRetries        = 50;      // Retry attempts on broker requote
input int      InpSlippagePoints    = 300;     // Slippage allowance in points (30 pips)

input group "=== 4. KEYBOARD CONTROLS ===";
input string   KeySellBarcode       = "S";     // [S] = Fire SELL Barcode
input string   KeyBuyBarcode        = "B";     // [B] = Fire BUY Barcode
input string   KeySellLimit         = "L";     // [L] = Arm 80% Margin SELL LIMITS
input string   KeyBuyLimit          = "K";     // [K] = Arm 80% Margin BUY LIMITS
input string   KeyPanicClose        = "X";     // [X] = PANIC CLOSE ALL POSITIONS

CTrade trade;
int code_S = 83, code_B = 66, code_L = 76, code_K = 75, code_X = 88;

void CreateButton(string name, string text, int x, int y, int w, int h, color bg, color fg)
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
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_COLOR, fg);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrNONE);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void DrawHUD()
{
   int startX = 20;
   int startY = 60;
   int btnW = 125;
   int btnH = 38;
   int gap = 8;

   CreateButton("BTN_BUY",  "▲ BUY BARCODE [B]",  startX, startY, btnW, btnH, C'22,163,74', clrWhite);
   CreateButton("BTN_SELL", "▼ SELL BARCODE [S]", startX + btnW + gap, startY, btnW, btnH, C'220,38,38', clrWhite);
   
   CreateButton("BTN_KLIMIT", "K: BUY LIMIT (80%)", startX, startY + btnH + gap, btnW, 30, C'15,23,42', C'56,189,248');
   CreateButton("BTN_LLIMIT", "L: SELL LIMIT (80%)", startX + btnW + gap, startY + btnH + gap, btnW, 30, C'15,23,42', C'248,113,113');

   CreateButton("BTN_CLOSE", "✖ PANIC CLOSE ALL [X]", startX, startY + (btnH + gap) * 2 - 2, (btnW * 2) + gap, 42, C'185,28,28', clrWhite);
}

int OnInit()
{
   trade.SetExpertMagicNumber(999111);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   string s = KeySellBarcode; StringToUpper(s); if(StringLen(s)>0) code_S = (int)StringGetCharacter(s,0);
   string b = KeyBuyBarcode;  StringToUpper(b); if(StringLen(b)>0) code_B = (int)StringGetCharacter(b,0);
   string l = KeySellLimit;   StringToUpper(l); if(StringLen(l)>0) code_L = (int)StringGetCharacter(l,0);
   string k = KeyBuyLimit;    StringToUpper(k); if(StringLen(k)>0) code_K = (int)StringGetCharacter(k,0);
   string x = KeyPanicClose;  StringToUpper(x); if(StringLen(x)>0) code_X = (int)StringGetCharacter(x,0);

   DrawHUD();
   ChartRedraw(0);
   PrintFormat(">>> NEWS TERMINAL RUNNING PURE EXECUTION (NO SL / NO TP). Control with [X] Kill Switch! <<<");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   ObjectDelete(0, "BTN_BUY");
   ObjectDelete(0, "BTN_SELL");
   ObjectDelete(0, "BTN_KLIMIT");
   ObjectDelete(0, "BTN_LLIMIT");
   ObjectDelete(0, "BTN_CLOSE");
   ChartRedraw(0);
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // Mouse Button Clicks
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == "BTN_BUY")
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
      ChartRedraw(0);
   }

   // Keyboard Hotkeys
   if(id == CHARTEVENT_KEYDOWN)
   {
      if(lparam == code_S || lparam == 115) // 'S' or 's'
      {
         ExecuteBarcode(ORDER_TYPE_SELL);
      }
      else if(lparam == code_B || lparam == 98) // 'B' or 'b'
      {
         ExecuteBarcode(ORDER_TYPE_BUY);
      }
      else if(lparam == code_L || lparam == 108) // 'L'
      {
         ArmSpikeLimits(ORDER_TYPE_SELL_LIMIT);
      }
      else if(lparam == code_K || lparam == 107) // 'K'
      {
         ArmSpikeLimits(ORDER_TYPE_BUY_LIMIT);
      }
      else if(lparam == code_X || lparam == 120) // 'X'
      {
         ExecuteEmergencyClose();
      }
   }
}

// 1. Pure Barcode Execution: Zero SL, Zero TP
void ExecuteBarcode(ENUM_ORDER_TYPE orderType)
{
   int filled = 0;
   for(int i = 0; i < InpNumberOfStripes; i++)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if(orderType == ORDER_TYPE_SELL)
      {
         // Pure Execution: 0.0 Stop Loss, 0.0 Take Profit
         if(trade.Sell(InpLotPerStripe, _Symbol, bid, 0.0, 0.0, "Barcode Stripe")) filled++;
      }
      else
      {
         // Pure Execution: 0.0 Stop Loss, 0.0 Take Profit
         if(trade.Buy(InpLotPerStripe, _Symbol, ask, 0.0, 0.0, "Barcode Stripe")) filled++;
      }
      Sleep(20);
   }
   PrintFormat("✅ BARCODE EXECUTED: %d/%d stripes filled on %s (NO SL / NO TP)", filled, InpNumberOfStripes, _Symbol);
}

// 2. Pure Spike Limits: Zero SL, Zero TP
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

   double halfLot = NormalizeDouble(totalLots / 2.0, 2);
   if(halfLot < 0.01) halfLot = totalLots;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   datetime expiry = TimeCurrent() + (InpLimitExpiryMins * 60);

   for(int i = 0; i < 2; i++)
   {
      double offset = InpSpikeDistance + (i * 0.50);
      if(orderType == ORDER_TYPE_SELL_LIMIT)
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double p = NormalizeDouble(ask + offset, digits);
         // Zero SL and Zero TP
         trade.SellLimit(halfLot, p, _Symbol, 0.0, 0.0, ORDER_TIME_SPECIFIED, expiry, "Spike Sell Limit");
      }
      else
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double p = NormalizeDouble(bid - offset, digits);
         // Zero SL and Zero TP
         trade.BuyLimit(halfLot, p, _Symbol, 0.0, 0.0, ORDER_TIME_SPECIFIED, expiry, "Spike Buy Limit");
      }
   }
   PrintFormat("✅ 80%% LIMITS ARMED on %s (~%.2f lots, NO SL / NO TP)", _Symbol, totalLots);
}

// 3. Kill Switch: Instant Panic Close
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
