//+------------------------------------------------------------------+
//|                                           SpikeLimitSniper.mq4   |
//|                 High-Impact News Spike Limit Sniper Script/EA    |
//|    Calculates Free Margin %, places Limit at spike wick zone     |
//|    Auto-cancels if spike does not hit within ExpiryMinutes       |
//+------------------------------------------------------------------+
#property copyright "News Sniper Terminal"
#property link      "https://github.com/devUnlished/Us-fundamental-news-analysis"
#property version   "1.00"
#property strict
#property show_inputs

//--- Inputs
input string   TradeDirection       = "SELL";  // Direction: "SELL" or "BUY"
input double   InpMarginUsePercent  = 80.0;    // Margin to use (% of Free Margin, max 95%)
input double   InpMaxLotSafety      = 10.0;    // Hard maximum lot cap safety
input int      InpSplitOrders       = 2;       // Split into N laddered limit orders (1 to 3)
input int      InpSpikePips         = 18;      // Spike distance in pips (e.g. 18 pips above current ask)
input int      InpStopLossPips      = 35;      // Stop Loss in pips
input int      InpTakeProfitPips    = 60;      // Take Profit in pips
input int      InpExpiryMinutes     = 5;       // Auto-cancel if unfilled after N minutes

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
   Print(">>> SPIKE LIMIT SNIPER EXECUTING ON ", Symbol(), " <<<");

   double freeMargin = AccountFreeMargin();
   double leverage = (double)AccountLeverage();
   if(leverage <= 0) leverage = 100.0;

   // Margin calculation
   double safePercent = MathMin(InpMarginUsePercent, 95.0);
   double targetMargin = freeMargin * (safePercent / 100.0);

   double lotSize = MarketInfo(Symbol(), MODE_LOTSIZE);
   if(lotSize <= 0) lotSize = 100.0;
   double price = Ask;
   double marginForOneLot = (price * lotSize) / leverage;
   if(marginForOneLot <= 0) marginForOneLot = 1000.0;

   double totalLots = targetMargin / marginForOneLot;
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);

   if(lotStep <= 0) lotStep = 0.01;
   totalLots = MathFloor(totalLots / lotStep) * lotStep;
   totalLots = MathMin(totalLots, InpMaxLotSafety);
   totalLots = MathMin(totalLots, maxLot);
   totalLots = MathMax(totalLots, minLot);
   totalLots = NormalizeDouble(totalLots, 2);

   if(totalLots <= 0)
   {
      Alert("Insufficient margin to place limit orders!");
      return;
   }

   int numSplits = MathMax(1, MathMin(InpSplitOrders, 3));
   double lotPerOrder = NormalizeDouble(totalLots / numSplits, 2);
   if(lotPerOrder < minLot)
   {
      numSplits = 1;
      lotPerOrder = totalLots;
   }

   double point = Point;
   int digits = (int)Digits;
   double pipMultiplier = (digits == 3 || digits == 5) ? 10.0 : 1.0;
   double pipSize = point * pipMultiplier;

   datetime expiryTime = TimeCurrent() + (InpExpiryMinutes * 60);

   string dir = TradeDirection;
   StringToUpper(dir);

   for(int step = 0; step < numSplits; step++)
   {
      double stepOffset = InpSpikePips + (step * 5);
      double limitPrice = 0.0;
      double sl = 0.0;
      double tp = 0.0;
      int cmd = 0;

      if(dir == "SELL")
      {
         cmd = OP_SELLLIMIT;
         limitPrice = NormalizeDouble(Ask + (stepOffset * pipSize), digits);
         sl = NormalizeDouble(limitPrice + (InpStopLossPips * pipSize), digits);
         tp = NormalizeDouble(limitPrice - (InpTakeProfitPips * pipSize), digits);
      }
      else
      {
         cmd = OP_BUYLIMIT;
         limitPrice = NormalizeDouble(Bid - (stepOffset * pipSize), digits);
         sl = NormalizeDouble(limitPrice - (InpStopLossPips * pipSize), digits);
         tp = NormalizeDouble(limitPrice + (InpTakeProfitPips * pipSize), digits);
      }

      int ticket = OrderSend(Symbol(), cmd, lotPerOrder, limitPrice, 10, sl, tp, "Sniper Spike Limit", 777999, expiryTime, clrGold);
      if(ticket > 0)
      {
         PrintFormat("Ticket #%d: Placed %s LIMIT %.2f lots at %.2f (SL: %.2f | TP: %.2f | Exp: %d min)",
                     ticket, dir, lotPerOrder, limitPrice, sl, tp, InpExpiryMinutes);
      }
      else
      {
         int err = GetLastError();
         PrintFormat("Failed to place limit order. Error %d", err);
      }
   }

   Alert(StringFormat("ARMED %s LIMITS on %s: %.2f total lots (%.2f lots/order across %d splits)", dir, Symbol(), totalLots, lotPerOrder, numSplits));
}
