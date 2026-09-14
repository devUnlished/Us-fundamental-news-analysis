//+------------------------------------------------------------------+
//|                                           BarcodeNewsSpammer.mq5 |
//|                High-Frequency Barcode Order Spammer (MT5)        |
//|    Fires rapid-fire split micro orders to maximize margin fill   |
//+------------------------------------------------------------------+
#property copyright "News Sniper Terminal"
#property link      "https://github.com/devUnlished/Us-fundamental-news-analysis"
#property version   "1.00"

#include <Trade\Trade.mqh>

input group "=== BARCODE SETTINGS ===";
input int      InpNumberOfOrders    = 10;      // Number of barcode stripes (orders)
input double   InpLotPerStripe      = 0.10;    // Lot size per stripe (e.g. 10 x 0.10 = 1.00 lot)
input int      InpSlippagePoints    = 300;     // Slippage tolerance in points
input int      InpStopLossPips      = 40;      // Stop Loss in pips
input int      InpTakeProfitPips    = 80;      // Take Profit in pips
input ulong    InpMagicNumber       = 888111;  // Magic number

CTrade trade;

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   Print(">>> BARCODE NEWS SPAMMER LOADED. Press F7 for BUY Barcode, F8 for SELL Barcode <<<");
   return(INIT_SUCCEEDED);
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_KEYDOWN)
   {
      if(lparam == 119) // F8 key -> BARCODE SELL
      {
         PrintFormat("🔥 EXECUTING SELL BARCODE: Spreading %d orders of %.2f lots...", InpNumberOfOrders, InpLotPerStripe);
         ExecuteBarcode(ORDER_TYPE_SELL);
      }
      else if(lparam == 118) // F7 key -> BARCODE BUY
      {
         PrintFormat("🔥 EXECUTING BUY BARCODE: Spreading %d orders of %.2f lots...", InpNumberOfOrders, InpLotPerStripe);
         ExecuteBarcode(ORDER_TYPE_BUY);
      }
   }
}

void ExecuteBarcode(ENUM_ORDER_TYPE orderType)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double pipMultiplier = (digits == 3 || digits == 5) ? 10.0 : 1.0;
   double pipSize = point * pipMultiplier;

   int filled = 0;

   for(int i = 0; i < InpNumberOfOrders; i++)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if(orderType == ORDER_TYPE_SELL)
      {
         double sl = (InpStopLossPips > 0) ? NormalizeDouble(bid + (InpStopLossPips * pipSize), digits) : 0;
         double tp = (InpTakeProfitPips > 0) ? NormalizeDouble(bid - (InpTakeProfitPips * pipSize), digits) : 0;
         
         if(trade.Sell(InpLotPerStripe, _Symbol, bid, sl, tp, "Barcode Sell Stripe"))
         {
            filled++;
         }
      }
      else if(orderType == ORDER_TYPE_BUY)
      {
         double sl = (InpStopLossPips > 0) ? NormalizeDouble(ask - (InpStopLossPips * pipSize), digits) : 0;
         double tp = (InpTakeProfitPips > 0) ? NormalizeDouble(ask + (InpTakeProfitPips * pipSize), digits) : 0;

         if(trade.Buy(InpLotPerStripe, _Symbol, ask, sl, tp, "Barcode Buy Stripe"))
         {
            filled++;
         }
      }
      Sleep(20); // 20ms micro-stagger to bypass broker flood throttle
   }

   string msg = StringFormat("BARCODE COMPLETE: %d/%d stripes filled on %s!", filled, InpNumberOfOrders, _Symbol);
   Print(msg);
   Alert(msg);
}
