//+------------------------------------------------------------------+
//|                                     NewsSniper_Gold.mq5          |
//|                Fundamental News Indicator for XAUUSD (Gold)      |
//+------------------------------------------------------------------+
#property copyright "News Sniper"
#property link      "https://github.com/devUnlished/Us-fundamental-news-analysis"
#property version   "1.10"
#property indicator_chart_window
#property indicator_plots 0

input bool InpEnableSound = true;    // Enable Audio Alert
input bool InpShowDashboard = true;  // Show On-Screen HUD

string g_lastSignal = "STANDBY";
string g_lastNews = "None";
datetime g_lastCheckTime = 0;
ulong g_lastEvaluatedValueId = 0;

int OnInit()
{
   EventSetTimer(1);
   CreateHUD();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, "NewsSniper_");
}

void OnTimer()
{
   datetime now = TimeCurrent();
   if(now - g_lastCheckTime < 1) return;
   g_lastCheckTime = now;

   MqlCalendarValue values[];
   datetime fromTime = now - 600;
   datetime toTime = now + 43200;

   int count = CalendarValueHistory(values, fromTime, toTime, "US");
   bool signalFired = false;

   if(count > 0)
   {
      for(int i = 0; i < count; i++)
      {
         bool hasActual = (values[i].actual_value != LONG_MIN && 
                           values[i].actual_value != WRONG_VALUE && 
                           values[i].actual_value > -9000000000000000000LL &&
                           values[i].time <= now &&
                           (now - values[i].time) <= 300);

         if(hasActual && values[i].id != g_lastEvaluatedValueId)
         {
            MqlCalendarEvent event;
            if(CalendarEventById(values[i].event_id, event))
            {
               g_lastEvaluatedValueId = values[i].id;
               double mult = MathPow(10.0, event.digits);
               if(mult <= 0) mult = 1.0;
               double act = (double)values[i].actual_value / mult;
               double fcast = (values[i].forecast_value != LONG_MIN && values[i].forecast_value != WRONG_VALUE && values[i].forecast_value > -9000000000000000000LL) ? (double)values[i].forecast_value / mult : WRONG_VALUE;
               double prev = (values[i].prev_value != LONG_MIN && values[i].prev_value != WRONG_VALUE && values[i].prev_value > -9000000000000000000LL) ? (double)values[i].prev_value / mult : WRONG_VALUE;

               EvaluateNews(event.name, act, fcast, prev);
               signalFired = true;
               break;
            }
         }
      }

      // If no actual value released yet, preview the upcoming headline
      if(!signalFired && g_lastSignal == "STANDBY")
      {
         for(int i = 0; i < count; i++)
         {
            MqlCalendarEvent event;
            if(CalendarEventById(values[i].event_id, event))
            {
               string low = event.name; StringToLower(low);
               if(StringFind(low, "interest rate") >= 0 || StringFind(low, "fomc") >= 0 ||
                  StringFind(low, "federal funds") >= 0 || StringFind(low, "fed funds") >= 0)
               {
                  double mult = MathPow(10.0, event.digits);
                  if(mult <= 0) mult = 1.0;
                  bool hasFcast = (values[i].forecast_value != LONG_MIN && values[i].forecast_value != WRONG_VALUE && values[i].forecast_value > -9000000000000000000LL);
                  double fcast = hasFcast ? (double)values[i].forecast_value / mult : 0.0;
                  string info = hasFcast ? StringFormat("Upcoming: FOMC Rate Decision (Exp: %.2f%%)", fcast) : "Upcoming: FOMC Rate Decision";
                  ObjectSetString(0, "NewsSniper_Info", OBJPROP_TEXT, info);
                  break;
               }
            }
         }
      }
   }
}

void EvaluateNews(string name, double actual, double forecast, double prev)
{
   double benchmark = (forecast != WRONG_VALUE) ? forecast : prev;
   if(benchmark == WRONG_VALUE) return;

   string lowerName = name;
   StringToLower(lowerName);

   int direction = 0;

   // Tier 1 & 2 US Market Shakers
   if(StringFind(lowerName, "nonfarm") >= 0 || StringFind(lowerName, "non farm") >= 0 ||
      StringFind(lowerName, "cpi") >= 0 || StringFind(lowerName, "pce") >= 0 ||
      StringFind(lowerName, "fed funds") >= 0 || StringFind(lowerName, "federal funds") >= 0 ||
      StringFind(lowerName, "interest rate") >= 0 || StringFind(lowerName, "fomc") >= 0 || 
      StringFind(lowerName, "retail sales") >= 0 || StringFind(lowerName, "gdp") >= 0 || 
      StringFind(lowerName, "pmi") >= 0 || StringFind(lowerName, "ppi") >= 0 || 
      StringFind(lowerName, "jolts") >= 0)
   {
      direction = 1; // Higher -> Strong USD -> Sell Gold
   }
   else if(StringFind(lowerName, "unemployment rate") >= 0 || StringFind(lowerName, "jobless claims") >= 0)
   {
      direction = -1; // Higher -> Weak USD -> Buy Gold
   }

   if(direction == 0) return;

   double diff = actual - benchmark;
   double usdImpact = diff * direction;

   if(usdImpact > 0)
   {
      g_lastSignal = "SELL GOLD (Strong USD)";
      g_lastNews = name + " Actual: " + DoubleToString(actual, 2) + " vs Est: " + DoubleToString(benchmark, 2);
      UpdateHUD(clrRed, "🔴 SELL GOLD (STRONG USD)", g_lastNews);
      if(InpEnableSound) Alert("🔴 SELL GOLD (XAUUSD) - Strong USD: " + name);
   }
   else if(usdImpact < 0)
   {
      g_lastSignal = "BUY GOLD (Weak USD)";
      g_lastNews = name + " Actual: " + DoubleToString(actual, 2) + " vs Est: " + DoubleToString(benchmark, 2);
      UpdateHUD(clrGreen, "🟢 BUY GOLD (WEAK USD)", g_lastNews);
      if(InpEnableSound) Alert("🟢 BUY GOLD (XAUUSD) - Weak USD: " + name);
   }
}

void CreateHUD()
{
   if(!InpShowDashboard) return;

   int startX = 20;
   int startY = 245; // Cleanly positioned below AllInOneNewsTerminal's status row
   int width = 286;  // Matches total width of AllInOneNewsTerminal buttons
   int height = 75;

   ObjectCreate(0, "NewsSniper_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "NewsSniper_BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "NewsSniper_BG", OBJPROP_XDISTANCE, startX);
   ObjectSetInteger(0, "NewsSniper_BG", OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, "NewsSniper_BG", OBJPROP_XSIZE, width);
   ObjectSetInteger(0, "NewsSniper_BG", OBJPROP_YSIZE, height);
   ObjectSetInteger(0, "NewsSniper_BG", OBJPROP_BGCOLOR, C'15,23,42');
   ObjectSetInteger(0, "NewsSniper_BG", OBJPROP_BORDER_COLOR, C'51,65,85');

   ObjectCreate(0, "NewsSniper_Title", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "NewsSniper_Title", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "NewsSniper_Title", OBJPROP_XDISTANCE, startX + 10);
   ObjectSetInteger(0, "NewsSniper_Title", OBJPROP_YDISTANCE, startY + 6);
   ObjectSetString(0, "NewsSniper_Title", OBJPROP_TEXT, "⚡ NEWS SNIPER | XAUUSD (NFP/CPI/FOMC)");
   ObjectSetInteger(0, "NewsSniper_Title", OBJPROP_COLOR, clrGold);
   ObjectSetString(0, "NewsSniper_Title", OBJPROP_FONT, "Segoe UI Bold");
   ObjectSetInteger(0, "NewsSniper_Title", OBJPROP_FONTSIZE, 8);

   ObjectCreate(0, "NewsSniper_Signal", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "NewsSniper_Signal", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "NewsSniper_Signal", OBJPROP_XDISTANCE, startX + 10);
   ObjectSetInteger(0, "NewsSniper_Signal", OBJPROP_YDISTANCE, startY + 24);
   ObjectSetString(0, "NewsSniper_Signal", OBJPROP_TEXT, "STANDBY - WAITING FOR NEWS");
   ObjectSetInteger(0, "NewsSniper_Signal", OBJPROP_COLOR, clrLightGray);
   ObjectSetString(0, "NewsSniper_Signal", OBJPROP_FONT, "Segoe UI Bold");
   ObjectSetInteger(0, "NewsSniper_Signal", OBJPROP_FONTSIZE, 11);

   ObjectCreate(0, "NewsSniper_Info", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "NewsSniper_Info", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "NewsSniper_Info", OBJPROP_XDISTANCE, startX + 10);
   ObjectSetInteger(0, "NewsSniper_Info", OBJPROP_YDISTANCE, startY + 50);
   ObjectSetString(0, "NewsSniper_Info", OBJPROP_TEXT, "Monitoring high-impact US calendar...");
   ObjectSetInteger(0, "NewsSniper_Info", OBJPROP_COLOR, C'148,163,184');
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
