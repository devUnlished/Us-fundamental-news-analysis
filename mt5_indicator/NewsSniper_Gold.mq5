//+------------------------------------------------------------------+
//|                                     NewsSniper_Gold.mq5          |
//|                Fundamental News Indicator for XAUUSD (Gold)      |
//+------------------------------------------------------------------+
#property copyright "News Sniper"
#property link      "https://github.com/devUnlished/Us-fundamental-news-analysis"
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0

input bool InpEnableSound = true; // Enable Audio Chime
input bool InpShowDashboard = true; // Show On-Screen HUD

string g_lastSignal = "STANDBY";
string g_lastNews = "None";
datetime g_lastCheckTime = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   EventSetTimer(1); // 1 second fast timer
   CreateHUD();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, "NewsSniper_");
}

//+------------------------------------------------------------------+
//| Timer event: checks MT5 built-in Economic Calendar               |
//+------------------------------------------------------------------+
void OnTimer()
{
   datetime now = TimeCurrent();
   if(now - g_lastCheckTime < 1) return;
   g_lastCheckTime = now;

   // Query calendar events from MT5 native database
   MqlCalendarValue values[];
   datetime fromTime = now - 60; // Check last 60 seconds
   datetime toTime = now + 60;

   int count = CalendarValueHistory(values, fromTime, toTime, "US");
   if(count > 0)
   {
      for(int i = 0; i < count; i++)
      {
         if(values[i].actual_value != WRONG_VALUE)
         {
            MqlCalendarEvent event;
            if(CalendarEventById(values[i].event_id, event))
            {
               EvaluateNews(event.name, (double)values[i].actual_value, (double)values[i].forecast_value, (double)values[i].prev_value);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Evaluates USD news impact on Gold (XAUUSD)                       |
//+------------------------------------------------------------------+
void EvaluateNews(string name, double actual, double forecast, double prev)
{
   double benchmark = (forecast != WRONG_VALUE) ? forecast : prev;
   if(benchmark == WRONG_VALUE) return;

   string lowerName = name;
   StringToLower(lowerName);

   int direction = 0; // +1: Higher = Strong USD, -1: Higher = Weak USD

   if(StringFind(lowerName, "nonfarm") >= 0 || StringFind(lowerName, "non farm") >= 0 ||
      StringFind(lowerName, "cpi") >= 0 || StringFind(lowerName, "retail sales") >= 0 ||
      StringFind(lowerName, "pmi") >= 0)
   {
      direction = 1;
   }
   else if(StringFind(lowerName, "unemployment rate") >= 0 || StringFind(lowerName, "jobless") >= 0)
   {
      direction = -1;
   }

   if(direction == 0) return;

   double diff = actual - benchmark;
   double usdImpact = diff * direction;

   if(usdImpact > 0)
   {
      g_lastSignal = "SELL GOLD (Strong USD)";
      g_lastNews = name + " Actual: " + DoubleToString(actual, 2) + " vs Est: " + DoubleToString(benchmark, 2);
      UpdateHUD(clrRed, "🔴 SELL GOLD (STRONG USD)", g_lastNews);
      if(InpEnableSound) Alert("🔴 SELL GOLD (XAUUSD) - Strong USD News: " + name);
   }
   else if(usdImpact < 0)
   {
      g_lastSignal = "BUY GOLD (Weak USD)";
      g_lastNews = name + " Actual: " + DoubleToString(actual, 2) + " vs Est: " + DoubleToString(benchmark, 2);
      UpdateHUD(clrGreen, "🟢 BUY GOLD (WEAK USD)", g_lastNews);
      if(InpEnableSound) Alert("🟢 BUY GOLD (XAUUSD) - Weak USD News: " + name);
   }
}

//+------------------------------------------------------------------+
//| UI HUD Drawing on chart                                          |
//+------------------------------------------------------------------+
void CreateHUD()
{
   if(!InpShowDashboard) return;

   ObjectCreate(0, "NewsSniper_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "NewsSniper_BG", OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, "NewsSniper_BG", OBJPROP_YDISTANCE, 40);
   ObjectSetInteger(0, "NewsSniper_BG", OBJPROP_XSIZE, 320);
   ObjectSetInteger(0, "NewsSniper_BG", OBJPROP_YSIZE, 80);
   ObjectSetInteger(0, "NewsSniper_BG", OBJPROP_BGCOLOR, C'20,24,30');
   ObjectSetInteger(0, "NewsSniper_BG", OBJPROP_BORDER_COLOR, clrDarkGray);

   ObjectCreate(0, "NewsSniper_Title", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "NewsSniper_Title", OBJPROP_XDISTANCE, 30);
   ObjectSetInteger(0, "NewsSniper_Title", OBJPROP_YDISTANCE, 48);
   ObjectSetString(0, "NewsSniper_Title", OBJPROP_TEXT, "⚡ NEWS SNIPER | XAUUSD");
   ObjectSetInteger(0, "NewsSniper_Title", OBJPROP_COLOR, clrGold);
   ObjectSetString(0, "NewsSniper_Title", OBJPROP_FONT, "Segoe UI Bold");
   ObjectSetInteger(0, "NewsSniper_Title", OBJPROP_FONTSIZE, 9);

   ObjectCreate(0, "NewsSniper_Signal", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "NewsSniper_Signal", OBJPROP_XDISTANCE, 30);
   ObjectSetInteger(0, "NewsSniper_Signal", OBJPROP_YDISTANCE, 70);
   ObjectSetString(0, "NewsSniper_Signal", OBJPROP_TEXT, "STANDBY - WAITING FOR NEWS");
   ObjectSetInteger(0, "NewsSniper_Signal", OBJPROP_COLOR, clrLightGray);
   ObjectSetString(0, "NewsSniper_Signal", OBJPROP_FONT, "Segoe UI Bold");
   ObjectSetInteger(0, "NewsSniper_Signal", OBJPROP_FONTSIZE, 12);

   ObjectCreate(0, "NewsSniper_Info", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "NewsSniper_Info", OBJPROP_XDISTANCE, 30);
   ObjectSetInteger(0, "NewsSniper_Info", OBJPROP_YDISTANCE, 96);
   ObjectSetString(0, "NewsSniper_Info", OBJPROP_TEXT, "Monitoring high-impact US calendar...");
   ObjectSetInteger(0, "NewsSniper_Info", OBJPROP_COLOR, clrSilver);
   ObjectSetString(0, "NewsSniper_Info", OBJPROP_FONT, "Segoe UI");
   ObjectSetInteger(0, "NewsSniper_Info", OBJPROP_FONTSIZE, 8);
}

void UpdateHUD(color col, string signalTxt, string infoTxt)
{
   ObjectSetString(0, "NewsSniper_Signal", OBJPROP_TEXT, signalTxt);
   ObjectSetInteger(0, "NewsSniper_Signal", OBJPROP_COLOR, col);
   ObjectSetString(0, "NewsSniper_Info", OBJPROP_TEXT, infoTxt);
   ChartRedraw();
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
