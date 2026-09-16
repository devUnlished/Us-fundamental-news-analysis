//+------------------------------------------------------------------+
//|                                     NewsSniper_Gold.mq5          |
//|                Fundamental News Indicator for XAUUSD (Gold)      |
//+------------------------------------------------------------------+
#property copyright "News Sniper"
#property link      "https://github.com/devUnlished/Us-fundamental-news-analysis"
#property version   "1.10"
#property indicator_chart_window
#property indicator_plots 0

int OnInit()
{
   EventKillTimer();
   ObjectsDeleteAll(0, "NewsSniper_");
   Print("NewsSniper_Gold indicator unloaded and all graphics cleaned.");
   return(INIT_FAILED); // Signals MT5 to automatically detach this indicator from the chart
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, "NewsSniper_");
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   return(rates_total);
}
