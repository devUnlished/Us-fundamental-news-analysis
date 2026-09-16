//+------------------------------------------------------------------+
//|                                           CloseAllPositions.mq5  |
//+------------------------------------------------------------------+
#property script_show_inputs false
#include <Trade\Trade.mqh>

void OnStart()
{
   CTrade trade;
   trade.SetDeviationInPoints(300);
   int closed = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(trade.PositionClose(ticket)) closed++;
      }
   }
   
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0) trade.OrderDelete(ticket);
   }
   
   PrintFormat(">>> EMERGENCY PURGE COMPLETED: Closed %d open positions, deleted all pending orders <<<", closed);
}
