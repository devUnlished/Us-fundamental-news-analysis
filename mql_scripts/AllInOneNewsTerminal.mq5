//+------------------------------------------------------------------+
//|                                     AllInOneNewsTerminal.mq5     |
//|            High-Impact News Execution & Liquidation Engine       |
//|    Combines: Barcode Spammer, Spike Limits, and Emergency Close  |
//|              RUNS ON A SINGLE GOLD (XAUUSD) CHART!               |
//+------------------------------------------------------------------+
#property copyright "News Sniper Terminal"
#property link      "https://github.com/devUnlished/Us-fundamental-news-analysis"
#property version   "2.00"

#include <Trade\Trade.mqh>

input group "=== 1. BARCODE SPAMMER SETTINGS ===";
input int      InpNumberOfStripes   = 8;       // Number of barcode stripes per key press
input double   InpLotPerStripe      = 0.01;    // Lot size per stripe (e.g. 8 x 0.01 = 0.08 lots)
input int      InpBarcodeTP         = 25;      // Barcode Take Profit in pips
input int      InpBarcodeSL         = 30;      // Barcode Stop Loss in pips

input group "=== 2. SPIKE LIMIT SNIPER SETTINGS ===";
input double   InpMarginPercent     = 80.0;    // Margin to use for Limit Orders (% of Free Margin)
input int      InpSpikePips         = 18;      // Spike distance in pips above/below market
input int      InpLimitTP           = 60;      // Limit Take Profit in pips
input int      InpLimitSL           = 35;      // Limit Stop Loss in pips
input int      InpLimitExpiryMins   = 5;       // Auto-cancel unfilled limits after N minutes

input group "=== 3. EMERGENCY CLOSE SETTINGS ===";
input int      InpMaxRetries        = 50;      // Retry attempts on broker requote
input int      InpSlippagePoints    = 300;     // Slippage allowance in points (30 pips)

input group "=== 4. KEYBOARD CONTROLS (NO F-KEYS) ===";
input string   KeySellBarcode       = "S";     // [S] = Fire SELL Barcode (Rapid stripes)
input string   KeyBuyBarcode        = "B";     // [B] = Fire BUY Barcode (Rapid stripes)
input string   KeySellLimit         = "L";     // [L] = Arm 80% Margin SELL LIMITS (At spike wick)
input string   KeyBuyLimit          = "K";     // [K] = Arm 80% Margin BUY LIMITS (At dip wick)
input string   KeyPanicClose        = "X";     // [X] = PANIC CLOSE ALL POSITIONS (Instant liquidation)

CTrade trade;
int code_S = 83, code_B = 66, code_L = 76, code_K = 75, code_X = 88;

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(999111);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   string s = KeySellBarcode; StringToUpper(s); if(StringLen(s)>0) code_S = (int)StringGetCharacter(s,0);
   string b = KeyBuyBarcode;  StringToUpper(b); if(StringLen(b)>0) code_B = (int)StringGetCharacter(b,0);
   string l = KeySellLimit;   StringToUpper(l); if(StringLen(l)>0) code_L = (int)StringGetCharacter(l,0);
   string k = KeyBuyLimit;    StringToUpper(k); if(StringLen(k)>0) code_K = (int)StringGetCharacter(k,0);
   string x = KeyPanicClose;  StringToUpper(x); if(StringLen(x)>0) code_X = (int)StringGetCharacter(x,0);

   Print("===============================================================");
   Print("  NEWS SNIPER ALL-IN-ONE TERMINAL LOADED ON ", _Symbol);
   PrintFormat("  [ %s ] = SELL BARCODE  |  [ %s ] = BUY BARCODE", s, b);
   PrintFormat("  [ %s ] = SELL LIMITS   |  [ %s ] = BUY LIMITS", l, k);
   PrintFormat("  [ %s ] = PANIC CLOSE ALL POSITIONS", x);
   Print("===============================================================");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
//| Chart Event: Single-Key Listeners                                |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_KEYDOWN)
   {
      if(lparam == code_S) // S -> Sell Barcode
      {
         Print("🔥 ACTION: Firing SELL Barcode...");
         ExecuteBarcode(ORDER_TYPE_SELL);
      }
      else if(lparam == code_B) // B -> Buy Barcode
      {
         Print("🔥 ACTION: Firing BUY Barcode...");
         ExecuteBarcode(ORDER_TYPE_BUY);
      }
      else if(lparam == code_L) // L -> Sell Limits
      {
         Print("🎯 ACTION: Arming 80% Margin SELL LIMITS...");
         ArmSpikeLimits(ORDER_TYPE_SELL_LIMIT);
      }
      else if(lparam == code_K) // K -> Buy Limits
      {
         Print("🎯 ACTION: Arming 80% Margin BUY LIMITS...");
         ArmSpikeLimits(ORDER_TYPE_BUY_LIMIT);
      }
      else if(lparam == code_X) // X -> Panic Close
      {
         Print("🚨 PANIC CLOSE TRIGGERED: Liquidating all open trades...");
         ExecuteEmergencyClose();
      }
   }
}

//+------------------------------------------------------------------+
//| 1. Barcode Spammer Execution                                     |
//+------------------------------------------------------------------+
void ExecuteBarcode(ENUM_ORDER_TYPE orderType)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double pipMult = (digits == 3 || digits == 5) ? 10.0 : 1.0;
   double pipSize = point * pipMult;

   int filled = 0;
   for(int i = 0; i < InpNumberOfStripes; i++)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if(orderType == ORDER_TYPE_SELL)
      {
         double sl = (InpBarcodeSL > 0) ? NormalizeDouble(bid + (InpBarcodeSL * pipSize), digits) : 0;
         double tp = (InpBarcodeTP > 0) ? NormalizeDouble(bid - (InpBarcodeTP * pipSize), digits) : 0;
         if(trade.Sell(InpLotPerStripe, _Symbol, bid, sl, tp, "Barcode Stripe")) filled++;
      }
      else
      {
         double sl = (InpBarcodeSL > 0) ? NormalizeDouble(ask - (InpBarcodeSL * pipSize), digits) : 0;
         double tp = (InpBarcodeTP > 0) ? NormalizeDouble(ask + (InpBarcodeTP * pipSize), digits) : 0;
         if(trade.Buy(InpLotPerStripe, _Symbol, ask, sl, tp, "Barcode Stripe")) filled++;
      }
      Sleep(20); // 20ms micro-stagger
   }
   PrintFormat("✅ BARCODE COMPLETED: %d/%d stripes filled on %s", filled, InpNumberOfStripes, _Symbol);
}

//+------------------------------------------------------------------+
//| 2. Spike Limit Placement (80% Margin)                            |
//+------------------------------------------------------------------+
void ArmSpikeLimits(ENUM_ORDER_TYPE orderType)
{
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double leverage = (double)AccountInfoInteger(ACCOUNT_LEVERAGE);
   if(leverage <= 0) leverage = 100.0;

   double targetMargin = freeMargin * (MathMin(InpMarginPercent, 95.0) / 100.0);
   double marginForOneLot = 0.0;
   if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, 1.0, SymbolInfoDouble(_Symbol, SYMBOL_ASK), marginForOneLot) || marginForOneLot <= 0)
   {
      marginForOneLot = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) * 100.0) / leverage;
   }

   double totalLots = targetMargin / marginForOneLot;
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotStep <= 0) lotStep = 0.01;
   totalLots = MathFloor(totalLots / lotStep) * lotStep;
   totalLots = MathMax(totalLots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));

   double halfLot = NormalizeDouble(totalLots / 2.0, 2);
   if(halfLot < 0.01) halfLot = totalLots;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double pipMult = (digits == 3 || digits == 5) ? 10.0 : 1.0;
   double pipSize = point * pipMult;
   datetime expiry = TimeCurrent() + (InpLimitExpiryMins * 60);

   for(int i = 0; i < 2; i++)
   {
      double offset = InpSpikePips + (i * 5);
      if(orderType == ORDER_TYPE_SELL_LIMIT)
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double p = NormalizeDouble(ask + (offset * pipSize), digits);
         double sl = NormalizeDouble(p + (InpLimitSL * pipSize), digits);
         double tp = NormalizeDouble(p - (InpLimitTP * pipSize), digits);
         trade.SellLimit(halfLot, p, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiry, "Spike Sell Limit");
      }
      else
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double p = NormalizeDouble(bid - (offset * pipSize), digits);
         double sl = NormalizeDouble(p - (InpLimitSL * pipSize), digits);
         double tp = NormalizeDouble(p + (InpLimitTP * pipSize), digits);
         trade.BuyLimit(halfLot, p, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiry, "Spike Buy Limit");
      }
   }
   PrintFormat("✅ 80%% MARGIN LIMITS ARMED on %s (~%.2f lots total)", _Symbol, totalLots);
}

//+------------------------------------------------------------------+
//| 3. Panic Emergency Close Execution (Relentless Retry Loop)       |
//+------------------------------------------------------------------+
void ExecuteEmergencyClose()
{
   int closed = 0;
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         int attempts = 0;
         while(attempts < InpMaxRetries)
         {
            attempts++;
            if(trade.PositionClose(ticket, InpSlippagePoints))
            {
               closed++;
               break;
            }
            Sleep(80); // Quick retry
         }
      }
   }

   // Also delete any pending limit orders
   int orders = OrdersTotal();
   for(int i = orders - 1; i >= 0; i--)
   {
      ulong oticket = OrderGetTicket(i);
      if(oticket > 0) trade.OrderDelete(oticket);
   }

   Alert(StringFormat("🚨 EMERGENCY CLOSE: Liquidated %d positions on %s!", closed, _Symbol));
}
