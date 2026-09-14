//+------------------------------------------------------------------+
//|                                           SpikeLimitSniper.mq5   |
//|                 High-Impact News Spike Limit Sniper EA           |
//|    Calculates Free Margin %, places Limit at spike wick zone     |
//|    Auto-cancels if spike does not hit within ExpiryMinutes       |
//+------------------------------------------------------------------+
#property copyright "News Sniper Terminal"
#property link      "https://github.com/devUnlished/Us-fundamental-news-analysis"
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- Inputs
input group "=== MARGIN & RISK SIZING ===";
input double   InpMarginUsePercent  = 80.0;    // Margin to use (% of Free Margin, max 95%)
input double   InpMaxLotSafety      = 10.0;    // Hard maximum lot cap safety
input int      InpSplitOrders       = 2;       // Split into N laddered limit orders (1 to 3)

input group "=== SPIKE LIMIT ENTRY SETTINGS ===";
input int      InpSpikePipsModest   = 18;      // Spike distance for Modest Surprise (pips)
input int      InpSpikePipsSolid    = 10;      // Spike distance for Solid Surprise (pips)
input int      InpStopLossPips      = 35;      // Stop Loss in pips above/below limit
input int      InpTakeProfitPips    = 60;      // Take Profit in pips from limit entry
input int      InpExpiryMinutes     = 5;       // Auto-cancel limit order if not tagged (minutes)

input group "=== EXECUTION MODE ===";
input bool     InpAutoTradeNews     = true;    // True = Auto-trade built-in calendar releases
input ulong    InpMagicNumber       = 777999;  // Magic number for sniper orders

CTrade trade;
datetime g_lastEvaluatedTime = 0;
string g_lastEventId = "";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   EventSetTimer(1);
   Print(">>> SPIKE LIMIT SNIPER LOADED ON ", _Symbol, " | Margin Sizing: ", InpMarginUsePercent, "% <<<");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
}

//+------------------------------------------------------------------+
//| Timer event: Checks MT5 built-in calendar for live releases      |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(!InpAutoTradeNews) return;

   datetime now = TimeCurrent();
   if(now - g_lastEvaluatedTime < 1) return;
   g_lastEvaluatedTime = now;

   MqlCalendarValue values[];
   datetime fromTime = now - 60;
   datetime toTime = now + 60;

   int count = CalendarValueHistory(values, fromTime, toTime, "US");
   if(count <= 0) return;

   for(int i = 0; i < count; i++)
   {
      if(values[i].actual_value == WRONG_VALUE) continue;

      string evKey = IntegerToString(values[i].event_id) + "_" + TimeToString(values[i].time);
      if(evKey == g_lastEventId) continue;

      MqlCalendarEvent event;
      if(CalendarEventById(values[i].event_id, event))
      {
         double actual = (double)values[i].actual_value;
         double forecast = (double)values[i].forecast_value;
         double prev = (double)values[i].prev_value;
         double benchmark = (forecast != WRONG_VALUE) ? forecast : prev;

         if(benchmark == WRONG_VALUE) continue;

         double diff = actual - benchmark;
         int direction = GetEventDirection(event.name);
         if(direction == 0) continue;

         double usdImpact = diff * direction;
         g_lastEventId = evKey;

         // Determine surprise magnitude (modest vs solid)
         bool isModest = (MathAbs(diff) < 0.25); // Relative threshold
         int spikePips = isModest ? InpSpikePipsModest : InpSpikePipsSolid;

         if(usdImpact > 0)
         {
            PrintFormat("⚡ BEARISH GOLD DETECTED (%s). Arming SELL LIMITS +%d pips above...", event.name, spikePips);
            ArmSpikeLimits(ORDER_TYPE_SELL_LIMIT, spikePips);
         }
         else if(usdImpact < 0)
         {
            PrintFormat("⚡ BULLISH GOLD DETECTED (%s). Arming BUY LIMITS -%d pips below...", event.name, spikePips);
            ArmSpikeLimits(ORDER_TYPE_BUY_LIMIT, spikePips);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manual hotkey triggers via ChartEvent (F9 = Buy, F10 = Sell)     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_KEYDOWN)
   {
      if(lparam == 121) // F10 key -> SELL SPIKE LIMIT
      {
         Print("🔥 MANUAL TRIGGER: Hotkey F10 pressed. Arming SELL LIMIT at spike peak...");
         ArmSpikeLimits(ORDER_TYPE_SELL_LIMIT, InpSpikePipsModest);
      }
      else if(lparam == 120) // F9 key -> BUY SPIKE LIMIT
      {
         Print("🔥 MANUAL TRIGGER: Hotkey F9 pressed. Arming BUY LIMIT at spike low...");
         ArmSpikeLimits(ORDER_TYPE_BUY_LIMIT, InpSpikePipsModest);
      }
   }
}

//+------------------------------------------------------------------+
//| Core Engine: Calculate Dynamic Lot Size based on Margin %        |
//+------------------------------------------------------------------+
double CalculateDynamicLots(double marginPercent, string sym)
{
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double leverage = (double)AccountInfoInteger(ACCOUNT_LEVERAGE);
   if(leverage <= 0) leverage = 100.0;

   // Enforce safety cap on percentage (max 95% to leave buffer for spread)
   double safePercent = MathMin(marginPercent, 95.0);
   double targetMarginToUse = freeMargin * (safePercent / 100.0);

   double marginForOneLot = 0.0;
   if(!OrderCalcMargin(ORDER_TYPE_BUY, sym, 1.0, SymbolInfoDouble(sym, SYMBOL_ASK), marginForOneLot) || marginForOneLot <= 0)
   {
      double contractSize = SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE);
      if(contractSize <= 0) contractSize = 100.0;
      double price = SymbolInfoDouble(sym, SYMBOL_ASK);
      marginForOneLot = (price * contractSize) / leverage;
   }

   double calculatedLots = targetMarginToUse / marginForOneLot;

   // Normalize to broker step & limits
   double lotStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double minLot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);

   if(lotStep <= 0) lotStep = 0.01;
   calculatedLots = MathFloor(calculatedLots / lotStep) * lotStep;

   calculatedLots = MathMin(calculatedLots, InpMaxLotSafety);
   calculatedLots = MathMin(calculatedLots, maxLot);
   calculatedLots = MathMax(calculatedLots, minLot);

   return NormalizeDouble(calculatedLots, 2);
}

//+------------------------------------------------------------------+
//| Place Laddered Limit Orders at the Projected Sweep Wick          |
//+------------------------------------------------------------------+
void ArmSpikeLimits(ENUM_ORDER_TYPE orderType, int spikePips)
{
   double totalLots = CalculateDynamicLots(InpMarginUsePercent, _Symbol);
   if(totalLots <= 0)
   {
      Print("❌ Insufficient free margin to arm sniper limits.");
      return;
   }

   int numSplits = MathMax(1, MathMin(InpSplitOrders, 3));
   double lotPerOrder = NormalizeDouble(totalLots / numSplits, 2);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   if(lotPerOrder < minLot)
   {
      numSplits = 1;
      lotPerOrder = totalLots;
   }

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double pipMultiplier = (digits == 3 || digits == 5) ? 10.0 : 1.0;
   double pipSize = point * pipMultiplier;

   datetime expiryTime = TimeCurrent() + (InpExpiryMinutes * 60);

   PrintFormat("🎯 SIZING: Account Free Margin: %.2f | Target Lot Size: %.2f across %d orders (%.2f lots/order)",
               AccountInfoDouble(ACCOUNT_MARGIN_FREE), totalLots, numSplits, lotPerOrder);

   for(int step = 0; step < numSplits; step++)
   {
      double stepOffset = spikePips + (step * 5); // Ladder orders (e.g. +18, +23, +28 pips)
      double limitPrice = 0.0;
      double sl = 0.0;
      double tp = 0.0;

      if(orderType == ORDER_TYPE_SELL_LIMIT)
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         limitPrice = NormalizeDouble(ask + (stepOffset * pipSize), digits);
         sl = NormalizeDouble(limitPrice + (InpStopLossPips * pipSize), digits);
         tp = NormalizeDouble(limitPrice - (InpTakeProfitPips * pipSize), digits);

         bool placed = trade.SellLimit(lotPerOrder, limitPrice, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiryTime, "Sniper Spike Sell Limit");
         if(placed)
         {
            PrintFormat("✅ ARM SELL LIMIT #%d at %.2f | SL: %.2f | TP: %.2f | Expiry: %d min",
                        step + 1, limitPrice, sl, tp, InpExpiryMinutes);
         }
         else
         {
            PrintFormat("❌ Failed to place Sell Limit #%d. Retcode: %u (%s)", step + 1, trade.ResultRetcode(), trade.ResultRetcodeDescription());
         }
      }
      else if(orderType == ORDER_TYPE_BUY_LIMIT)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         limitPrice = NormalizeDouble(bid - (stepOffset * pipSize), digits);
         sl = NormalizeDouble(limitPrice - (InpStopLossPips * pipSize), digits);
         tp = NormalizeDouble(limitPrice + (InpTakeProfitPips * pipSize), digits);

         bool placed = trade.BuyLimit(lotPerOrder, limitPrice, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiryTime, "Sniper Spike Buy Limit");
         if(placed)
         {
            PrintFormat("✅ ARM BUY LIMIT #%d at %.2f | SL: %.2f | TP: %.2f | Expiry: %d min",
                        step + 1, limitPrice, sl, tp, InpExpiryMinutes);
         }
         else
         {
            PrintFormat("❌ Failed to place Buy Limit #%d. Retcode: %u (%s)", step + 1, trade.ResultRetcode(), trade.ResultRetcodeDescription());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Event direction classification                                   |
//+------------------------------------------------------------------+
int GetEventDirection(string name)
{
   string lowerName = name;
   StringToLower(lowerName);

   if(StringFind(lowerName, "nonfarm") >= 0 || StringFind(lowerName, "cpi") >= 0 ||
      StringFind(lowerName, "pce") >= 0 || StringFind(lowerName, "fed funds") >= 0 ||
      StringFind(lowerName, "interest rate") >= 0 || StringFind(lowerName, "fomc") >= 0 ||
      StringFind(lowerName, "retail sales") >= 0 || StringFind(lowerName, "gdp") >= 0 ||
      StringFind(lowerName, "pmi") >= 0 || StringFind(lowerName, "ppi") >= 0 ||
      StringFind(lowerName, "jolts") >= 0)
   {
      return 1; // Higher -> Strong USD -> Sell Gold
   }
   else if(StringFind(lowerName, "unemployment rate") >= 0 || StringFind(lowerName, "jobless claims") >= 0)
   {
      return -1; // Higher -> Weak USD -> Buy Gold
   }
   return 0;
}
