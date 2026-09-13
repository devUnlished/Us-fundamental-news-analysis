//+------------------------------------------------------------------+
//|                                           EmergencyNewsClose.mq4 |
//|                                  High-Impact News Auto-Liquidator|
//|                  Loop-retries closing all positions until cleared|
//+------------------------------------------------------------------+
#property copyright "News Sniper Terminal"
#property link      "https://github.com/devUnlished/Us-fundamental-news-analysis"
#property version   "1.00"
#property strict
#property show_inputs

//--- Inputs
input int      MaxRetries       = 50;        // Max retry attempts per ticket
input int      RetryDelayMs     = 100;       // Delay between retries in milliseconds
input int      SlippagePoints   = 300;       // Slippage allowance in points (Gold ~ 30 pips)
input bool     CloseOnlyCurrent = false;     // True = Only current chart symbol (e.g. XAUUSD), False = ALL symbols

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
   Print(">>> EMERGENCY NEWS CLOSE INITIATED <<<");
   
   int totalClosed = 0;
   int failedCount = 0;
   
   // Keep looping through open orders until no matching orders remain
   bool ordersRemaining = true;
   int outerSafetyLoop = 0;
   
   while(ordersRemaining && outerSafetyLoop < 100)
   {
      ordersRemaining = false;
      outerSafetyLoop++;
      
      int totalOrders = OrdersTotal();
      if(totalOrders == 0) break;
      
      // Loop backwards to safely close orders
      for(int i = totalOrders - 1; i >= 0; i--)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
         
         // Filter by symbol if requested
         if(CloseOnlyCurrent && OrderSymbol() != Symbol()) continue;
         
         // Only market orders (BUY = 0, SELL = 1)
         int type = OrderType();
         if(type != OP_BUY && type != OP_SELL) continue;
         
         ordersRemaining = true; // Found at least one order to close
         
         int ticket = OrderTicket();
         double lots = OrderLots();
         string sym = OrderSymbol();
         
         bool closed = false;
         int attempts = 0;
         
         while(!closed && attempts < MaxRetries)
         {
            attempts++;
            RefreshRates();
            
            double closePrice = (type == OP_BUY) ? MarketInfo(sym, MODE_BID) : MarketInfo(sym, MODE_ASK);
            
            ResetLastError();
            closed = OrderClose(ticket, lots, closePrice, SlippagePoints, clrRed);
            
            if(closed)
            {
               totalClosed++;
               PrintFormat("Ticket #%d (%s %.2f lots) CLOSED on attempt %d at %.2f", ticket, sym, lots, attempts, closePrice);
               break;
            }
            else
            {
               int err = GetLastError();
               PrintFormat("Ticket #%d Attempt %d failed. Error %d (%s). Retrying in %dms...", 
                           ticket, attempts, err, ErrorDescription(err), RetryDelayMs);
               Sleep(RetryDelayMs);
            }
         }
         
         if(!closed)
         {
            failedCount++;
            PrintFormat("FAILED to close Ticket #%d after %d attempts.", ticket, MaxRetries);
         }
      }
      
      Sleep(50); // Small cooldown between sweep rounds
   }
   
   string resultMsg = StringFormat("EMERGENCY CLOSE COMPLETE:\nTotal Closed: %d\nFailed: %d", totalClosed, failedCount);
   Print(resultMsg);
   Alert(resultMsg);
}

//+------------------------------------------------------------------+
//| Human-readable error helper                                      |
//+------------------------------------------------------------------+
string ErrorDescription(int err)
{
   switch(err)
   {
      case 0:   return "No error";
      case 1:   return "No error returned, but result unknown";
      case 2:   return "Common error";
      case 3:   return "Invalid trade parameters";
      case 4:   return "Trade server is busy";
      case 6:   return "No connection with trade server";
      case 128: return "Trade timeout";
      case 129: return "Invalid price";
      case 130: return "Invalid stops";
      case 131: return "Invalid trade volume";
      case 135: return "Price changed";
      case 136: return "Off quotes";
      case 137: return "Broker is busy";
      case 138: return "Requote";
      case 141: return "Too many requests";
      case 146: return "Trade context is busy";
      default:  return "Error code " + IntegerToString(err);
   }
}
