//+------------------------------------------------------------------+
//|                                           BarcodeNewsSpammer.mq4 |
//|                High-Frequency Barcode Order Spammer (MT4)        |
//|    Fires rapid-fire split micro orders to maximize margin fill   |
//+------------------------------------------------------------------+
#property copyright "News Sniper Terminal"
#property link      "https://github.com/devUnlished/Us-fundamental-news-analysis"
#property version   "1.00"
#property strict
#property show_inputs

//--- Inputs
input string   TradeDirection       = "SELL";  // "SELL" or "BUY"
input int      InpNumberOfOrders    = 10;      // Number of barcode stripes (orders)
input double   InpLotPerStripe      = 0.10;    // Lot size per stripe
input int      InpSlippagePoints    = 300;     // Slippage tolerance in points
input int      InpStopLossPips      = 40;      // Stop Loss in pips
input int      InpTakeProfitPips    = 80;      // Take Profit in pips

void OnStart()
{
   Print(">>> EXECUTING BARCODE NEWS SPAMMER (MT4) <<<");

   double point = Point;
   int digits = (int)Digits;
   double pipMultiplier = (digits == 3 || digits == 5) ? 10.0 : 1.0;
   double pipSize = point * pipMultiplier;

   string dir = TradeDirection;
   StringToUpper(dir);

   int filled = 0;

   for(int i = 0; i < InpNumberOfOrders; i++)
   {
      RefreshRates();
      int cmd = (dir == "SELL") ? OP_SELL : OP_BUY;
      double price = (dir == "SELL") ? Bid : Ask;
      double sl = 0;
      double tp = 0;

      if(dir == "SELL")
      {
         sl = (InpStopLossPips > 0) ? NormalizeDouble(price + (InpStopLossPips * pipSize), digits) : 0;
         tp = (InpTakeProfitPips > 0) ? NormalizeDouble(price - (InpTakeProfitPips * pipSize), digits) : 0;
      }
      else
      {
         sl = (InpStopLossPips > 0) ? NormalizeDouble(price - (InpStopLossPips * pipSize), digits) : 0;
         tp = (InpTakeProfitPips > 0) ? NormalizeDouble(price + (InpTakeProfitPips * pipSize), digits) : 0;
      }

      int ticket = OrderSend(Symbol(), cmd, InpLotPerStripe, price, InpSlippagePoints, sl, tp, "Barcode Stripe", 888111, 0, clrGold);
      if(ticket > 0)
      {
         filled++;
      }
      Sleep(25); // Micro-pause to prevent broker context congestion
   }

   Alert(StringFormat("BARCODE COMPLETE: %d/%d stripes filled on %s!", filled, InpNumberOfOrders, Symbol()));
}
