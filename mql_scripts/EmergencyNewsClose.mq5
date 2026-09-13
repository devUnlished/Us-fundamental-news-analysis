//+------------------------------------------------------------------+
//|                                           EmergencyNewsClose.mq5 |
//|                                  High-Impact News Auto-Liquidator|
//|                  Loop-retries closing all positions until cleared|
//+------------------------------------------------------------------+
#property copyright "News Sniper Terminal"
#property link      "https://github.com/devUnlished/Us-fundamental-news-analysis"
#property version   "1.00"
#property script_show_inputs

#include <Trade\Trade.mqh>

input ulong    MaxRetries       = 50;        // Max retry attempts per position
input uint     RetryDelayMs     = 100;       // Delay between retries in milliseconds
input ulong    SlippagePoints   = 300;       // Slippage allowance in points (Gold ~ 30 pips)
input bool     CloseOnlyCurrent = false;     // True = Only current chart symbol, False = ALL symbols

CTrade trade;

void OnStart()
{
   Print(">>> EMERGENCY NEWS CLOSE INITIATED (MT5) <<<");
   trade.SetDeviationInPoints(SlippagePoints);
   
   int totalClosed = 0;
   int failedCount = 0;
   
   bool positionsRemaining = true;
   int outerSafety = 0;
   
   while(positionsRemaining && outerSafety < 100)
   {
      positionsRemaining = false;
      outerSafety++;
      
      int total = PositionsTotal();
      if(total == 0) break;
      
      for(int i = total - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         
         string sym = PositionGetString(POSITION_SYMBOL);
         if(CloseOnlyCurrent && sym != _Symbol) continue;
         
         positionsRemaining = true;
         bool closed = false;
         ulong attempts = 0;
         
         while(!closed && attempts < MaxRetries)
         {
            attempts++;
            closed = trade.PositionClose(ticket, SlippagePoints);
            
            if(closed && trade.ResultRetcode() == TRADE_RETCODE_DONE)
            {
               totalClosed++;
               PrintFormat("Ticket #%I64u (%s) CLOSED on attempt %d", ticket, sym, attempts);
               break;
            }
            else
            {
               uint retCode = trade.ResultRetcode();
               PrintFormat("Ticket #%I64u attempt %d failed (RetCode: %u - %s). Retrying in %dms...",
                           ticket, attempts, retCode, trade.ResultRetcodeDescription(), RetryDelayMs);
               Sleep(RetryDelayMs);
            }
         }
         
         if(!closed)
         {
            failedCount++;
            PrintFormat("FAILED to close Ticket #%I64u after %d attempts.", ticket, MaxRetries);
         }
      }
      
      Sleep(50);
   }
   
   string resultMsg = StringFormat("EMERGENCY CLOSE COMPLETE:\nTotal Closed: %d\nFailed: %d", totalClosed, failedCount);
   Print(resultMsg);
   Alert(resultMsg);
}
