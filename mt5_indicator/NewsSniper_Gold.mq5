//+------------------------------------------------------------------+
//|                                     NewsSniper_Gold.mq5          |
//|           Fundamental News Sniper Indicator for XAUUSD (Gold)    |
//|               Precision Calibrated for FOMC / NFP / CPI          |
//|                         Timezone: GMT+2                          |
//+------------------------------------------------------------------+
#property copyright "News Sniper"
#property link      "https://github.com/devUnlished/Us-fundamental-news-analysis"
#property version   "2.00"
#property indicator_chart_window
#property indicator_plots 0

input group "=== DISPLAY & TIMEZONE ===";
input int    InpGMTOffsetHours   = 2;     // Target Display Timezone (GMT+2)
input bool   InpShowDashboard    = true;  // Show On-Screen HUD

input group "=== ALERTS ===";
input bool   InpPlayChime        = true;  // Play Audio Chime on Release (Once)
input bool   InpShowModalAlert   = false; // Show MT5 Popup Dialog (Default: False)

// State Tracking
string   g_lastSignal         = "STANDBY";
string   g_lastNewsHeadline   = "Monitoring US Economic Calendar";
string   g_lastNewsDetail     = "Standby for upcoming market releases";
ulong    g_lastAlertedEventId = 0;
datetime g_lastCheckTime      = 0;

int OnInit()
{
   EventSetTimer(1);
   CreateHUD();
   UpdateHUD(clrLightSlateGray, "STANDBY — WAITING FOR RELEASE", "Scanning high-impact US calendar...", "Timezone: GMT+2");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, "NewsSniper_");
   ChartRedraw(0);
}

void OnTimer()
{
   datetime nowGMT = TimeGMT();
   if(nowGMT - g_lastCheckTime < 1) return;
   g_lastCheckTime = nowGMT;

   datetime fromTime = nowGMT - 900;    // Scan last 15 minutes for fresh releases
   datetime toTime   = nowGMT + 86400;  // Scan next 24 hours for upcoming events

   MqlCalendarValue values[];
   int count = CalendarValueHistory(values, fromTime, toTime, "US");

   bool activeReleaseFound = false;

   if(count > 0)
   {
      // 1. Check for newly PUBLISHED live release in the last 15 minutes
      for(int i = 0; i < count; i++)
      {
         bool hasActual = (values[i].actual_value != LONG_MIN && 
                           values[i].actual_value != WRONG_VALUE && 
                           values[i].actual_value > -9000000000000000000LL &&
                           values[i].time <= nowGMT &&
                           (nowGMT - values[i].time) <= 900);

         if(hasActual)
         {
            MqlCalendarEvent ev;
            if(CalendarEventById(values[i].event_id, ev))
            {
               string low = ev.name; StringToLower(low);
               if(IsMarketShaker(low))
               {
                  ProcessLiveRelease(ev, values[i]);
                  activeReleaseFound = true;
                  break;
               }
            }
         }
      }

      // 2. If no fresh release is active, preview the NEXT upcoming high-impact event (GMT+2)
      if(!activeReleaseFound)
      {
         datetime nearestTime = 0;
         int nearestIdx = -1;
         MqlCalendarEvent nearestEv;

         for(int i = 0; i < count; i++)
         {
            if(values[i].time > nowGMT)
            {
               MqlCalendarEvent ev;
               if(CalendarEventById(values[i].event_id, ev))
               {
                  string low = ev.name; StringToLower(low);
                  if(IsMarketShaker(low))
                  {
                     if(nearestTime == 0 || values[i].time < nearestTime)
                     {
                        nearestTime = values[i].time;
                        nearestIdx = i;
                        nearestEv = ev;
                     }
                  }
               }
            }
         }

         if(nearestIdx >= 0)
         {
            datetime gmt2Release = nearestTime + (InpGMTOffsetHours * 3600);
            int minutesLeft = (int)((nearestTime - nowGMT) / 60);
            string timeStr = TimeToString(gmt2Release, TIME_MINUTES);

            double mult = MathPow(10.0, nearestEv.digits);
            if(mult <= 0) mult = 1.0;

            bool hasFcast = (values[nearestIdx].forecast_value != LONG_MIN && 
                             values[nearestIdx].forecast_value != WRONG_VALUE && 
                             values[nearestIdx].forecast_value > -9000000000000000000LL);

            bool hasPrev = (values[nearestIdx].prev_value != LONG_MIN && 
                            values[nearestIdx].prev_value != WRONG_VALUE && 
                            values[nearestIdx].prev_value > -9000000000000000000LL);

            double fcast = hasFcast ? ((double)values[nearestIdx].forecast_value / mult) : 0.0;
            double prev  = hasPrev  ? ((double)values[nearestIdx].prev_value / mult) : 0.0;

            string headline = StringFormat("Next: %s @ %s (GMT+2)", nearestEv.name, timeStr);
            string detail = "";

            if(hasFcast && hasPrev)
               detail = StringFormat("Exp: %.2f%% | Prior: %.2f%% | Countdown: in %d mins", fcast, prev, minutesLeft);
            else if(hasFcast)
               detail = StringFormat("Exp: %.2f%% | Countdown: in %d mins", fcast, minutesLeft);
            else
               detail = StringFormat("Release in %d minutes", minutesLeft);

            UpdateHUD(C'148,163,184', "STANDBY — WAITING FOR RELEASE", headline, detail);
         }
      }
   }
}

bool IsMarketShaker(string lowerName)
{
   return (StringFind(lowerName, "interest rate") >= 0 ||
           StringFind(lowerName, "federal funds") >= 0 ||
           StringFind(lowerName, "fed funds") >= 0 ||
           StringFind(lowerName, "fomc") >= 0 ||
           StringFind(lowerName, "nonfarm") >= 0 ||
           StringFind(lowerName, "non farm") >= 0 ||
           StringFind(lowerName, "cpi") >= 0 ||
           StringFind(lowerName, "consumer price") >= 0 ||
           StringFind(lowerName, "pce") >= 0 ||
           StringFind(lowerName, "retail sales") >= 0 ||
           StringFind(lowerName, "gdp") >= 0 ||
           StringFind(lowerName, "unemployment rate") >= 0 ||
           StringFind(lowerName, "jobless claims") >= 0);
}

void ProcessLiveRelease(const MqlCalendarEvent &ev, const MqlCalendarValue &val)
{
   double mult = MathPow(10.0, ev.digits);
   if(mult <= 0) mult = 1.0;

   double actual = (double)val.actual_value / mult;

   bool hasForecast = (val.forecast_value != LONG_MIN && val.forecast_value != WRONG_VALUE && val.forecast_value > -9000000000000000000LL);
   bool hasPrev     = (val.prev_value != LONG_MIN && val.prev_value != WRONG_VALUE && val.prev_value > -9000000000000000000LL);

   double forecast = hasForecast ? ((double)val.forecast_value / mult) : WRONG_VALUE;
   double prev     = hasPrev     ? ((double)val.prev_value / mult) : WRONG_VALUE;
   double bench    = (forecast != WRONG_VALUE) ? forecast : prev;

   if(bench == WRONG_VALUE) return;

   string low = ev.name; StringToLower(low);
   int direction = 1; // Default: Higher number -> Strong USD -> SELL GOLD

   if(StringFind(low, "unemployment rate") >= 0 || StringFind(low, "jobless claims") >= 0)
   {
      direction = -1; // Higher unemployment -> Weak USD -> BUY GOLD
   }

   double diff = actual - bench;
   double usdImpact = diff * (double)direction;

   datetime gmt2Time = val.time + (InpGMTOffsetHours * 3600);
   string timeStr = TimeToString(gmt2Time, TIME_MINUTES) + " GMT+2";

   string headline = StringFormat("%s (%s)", ev.name, timeStr);
   string detail   = StringFormat("Actual: %.2f | Exp: %.2f (Diff: %+.2f)", actual, bench, diff);

   if(usdImpact > 0.0001)
   {
      // Strong USD -> Bearish Gold
      UpdateHUD(C'239,68,68', "🔴 SELL GOLD (STRONG USD)", headline, detail);

      // Trigger Alert ONCE per event release
      if(val.id != g_lastAlertedEventId)
      {
         g_lastAlertedEventId = val.id;
         if(InpPlayChime) PlaySound("alert.wav");
         if(InpShowModalAlert) Alert(StringFormat("🔴 SELL GOLD (STRONG USD): %s | Actual: %.2f vs Exp: %.2f", ev.name, actual, bench));
         PrintFormat("🔴 [NEWS SNIPER GMT+2]: %s -> SELL GOLD! Actual: %.2f vs Exp: %.2f", ev.name, actual, bench);
      }
   }
   else if(usdImpact < -0.0001)
   {
      // Weak USD -> Bullish Gold
      UpdateHUD(C'34,197,94', "🟢 BUY GOLD (WEAK USD)", headline, detail);

      // Trigger Alert ONCE per event release
      if(val.id != g_lastAlertedEventId)
      {
         g_lastAlertedEventId = val.id;
         if(InpPlayChime) PlaySound("alert.wav");
         if(InpShowModalAlert) Alert(StringFormat("🟢 BUY GOLD (WEAK USD): %s | Actual: %.2f vs Exp: %.2f", ev.name, actual, bench));
         PrintFormat("🟢 [NEWS SNIPER GMT+2]: %s -> BUY GOLD! Actual: %.2f vs Exp: %.2f", ev.name, actual, bench);
      }
   }
}

void CreateHUD()
{
   if(!InpShowDashboard) return;

   int startX = 20;
   int startY = 245; // Stacks flush beneath AllInOneNewsTerminal
   int width  = 286; // Exact matching width of AllInOneNewsTerminal buttons
   int height = 80;

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
   ObjectSetString(0, "NewsSniper_Title", OBJPROP_TEXT, "⚡ NEWS SNIPER | XAUUSD (GMT+2)");
   ObjectSetInteger(0, "NewsSniper_Title", OBJPROP_COLOR, clrGold);
   ObjectSetString(0, "NewsSniper_Title", OBJPROP_FONT, "Segoe UI Bold");
   ObjectSetInteger(0, "NewsSniper_Title", OBJPROP_FONTSIZE, 8);

   ObjectCreate(0, "NewsSniper_Signal", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "NewsSniper_Signal", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "NewsSniper_Signal", OBJPROP_XDISTANCE, startX + 10);
   ObjectSetInteger(0, "NewsSniper_Signal", OBJPROP_YDISTANCE, startY + 23);
   ObjectSetString(0, "NewsSniper_Signal", OBJPROP_TEXT, "STANDBY — WAITING FOR RELEASE");
   ObjectSetInteger(0, "NewsSniper_Signal", OBJPROP_COLOR, clrLightSlateGray);
   ObjectSetString(0, "NewsSniper_Signal", OBJPROP_FONT, "Segoe UI Bold");
   ObjectSetInteger(0, "NewsSniper_Signal", OBJPROP_FONTSIZE, 10);

   ObjectCreate(0, "NewsSniper_Headline", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "NewsSniper_Headline", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "NewsSniper_Headline", OBJPROP_XDISTANCE, startX + 10);
   ObjectSetInteger(0, "NewsSniper_Headline", OBJPROP_YDISTANCE, startY + 45);
   ObjectSetString(0, "NewsSniper_Headline", OBJPROP_TEXT, "Scanning high-impact US calendar...");
   ObjectSetInteger(0, "NewsSniper_Headline", OBJPROP_COLOR, C'241,245,249');
   ObjectSetString(0, "NewsSniper_Headline", OBJPROP_FONT, "Segoe UI Semibold");
   ObjectSetInteger(0, "NewsSniper_Headline", OBJPROP_FONTSIZE, 8);

   ObjectCreate(0, "NewsSniper_Detail", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "NewsSniper_Detail", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "NewsSniper_Detail", OBJPROP_XDISTANCE, startX + 10);
   ObjectSetInteger(0, "NewsSniper_Detail", OBJPROP_YDISTANCE, startY + 61);
   ObjectSetString(0, "NewsSniper_Detail", OBJPROP_TEXT, "Timezone: GMT+2");
   ObjectSetInteger(0, "NewsSniper_Detail", OBJPROP_COLOR, C'148,163,184');
   ObjectSetString(0, "NewsSniper_Detail", OBJPROP_FONT, "Segoe UI");
   ObjectSetInteger(0, "NewsSniper_Detail", OBJPROP_FONTSIZE, 8);
}

void UpdateHUD(color sigColor, string sigText, string headline, string detail)
{
   ObjectSetString(0, "NewsSniper_Signal", OBJPROP_TEXT, sigText);
   ObjectSetInteger(0, "NewsSniper_Signal", OBJPROP_COLOR, sigColor);
   ObjectSetString(0, "NewsSniper_Headline", OBJPROP_TEXT, headline);
   ObjectSetString(0, "NewsSniper_Detail", OBJPROP_TEXT, detail);
   ChartRedraw(0);
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
