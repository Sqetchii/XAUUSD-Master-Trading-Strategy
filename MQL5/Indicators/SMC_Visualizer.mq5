//+------------------------------------------------------------------+
//| SMC_Visualizer.mq5                                                |
//|                                                                    |
//| Draws the same swing points, liquidity sweeps, order blocks, FVGs |
//| and confirmation signals that SMC_XAUUSD_EA.mq5 trades, using the |
//| identical SMCCore.mqh functions. Use this on the chart to         |
//| visually audit every signal the EA would have taken before you    |
//| trust the backtest numbers.                                       |
//+------------------------------------------------------------------+
#property copyright "Research/visual-audit tool"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

#include <SMC\SMCCore.mqh>

input int    InpSwingLookback   = 5;
input int    InpMaxSwingScan    = 300;
input int    InpATR_Period      = 14;
input double InpSweepATR_Mult   = 0.15;
input int    InpConfirmBars     = 3;
input double InpConfirmATR_Mult = 0.30;
input int    InpMaxBarsToDraw   = 1000;   // How much history to scan/draw (performance guard)
input bool   InpShowFVG         = true;
input bool   InpShowOrderBlocks = true;
input bool   InpShowSwings      = true;

int atrHandle = INVALID_HANDLE;
string prefix = "SMCviz_";

int OnInit()
{
   atrHandle = iATR(_Symbol, _Period, InpATR_Period);
   if(atrHandle == INVALID_HANDLE) return INIT_FAILED;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
   ObjectsDeleteAll(0, prefix);
}

void DrawSwing(int idx, datetime t, double price, bool isHigh)
{
   string name = prefix + "swing_" + (string)t + (isHigh ? "H" : "L");
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_ARROW, 0, t, price);
      ObjectSetInteger(0, name, OBJPROP_ARROWCODE, isHigh ? 217 : 218);
      ObjectSetInteger(0, name, OBJPROP_COLOR, isHigh ? clrRed : clrLime);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   }
}

void DrawOrderBlock(int sweepIdx, datetime tStart, datetime tEnd, double obTop, double obBottom, bool bullish)
{
   string name = prefix + "ob_" + (string)tStart;
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, tStart, obTop, tEnd, obBottom);
      ObjectSetInteger(0, name, OBJPROP_COLOR, bullish ? clrLime : clrRed);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   }
}

void DrawFVG(datetime tStart, datetime tEnd, double gapLow, double gapHigh, bool bullish)
{
   string name = prefix + "fvg_" + (string)tStart + (bullish ? "B" : "S");
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, tStart, gapHigh, tEnd, gapLow);
      ObjectSetInteger(0, name, OBJPROP_COLOR, bullish ? clrDodgerBlue : clrOrange);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
   }
}

void DrawConfirmation(datetime t, double price, bool bullish)
{
   string name = prefix + "sig_" + (string)t + (bullish ? "B" : "S");
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_ARROW, 0, t, price);
      ObjectSetInteger(0, name, OBJPROP_ARROWCODE, bullish ? 233 : 234);
      ObjectSetInteger(0, name, OBJPROP_COLOR, bullish ? clrLime : clrRed);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 3);
   }
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
   int barsToScan = MathMin(rates_total, InpMaxBarsToDraw);
   if(barsToScan < InpMaxSwingScan + InpSwingLookback + InpConfirmBars + 10) return rates_total;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, _Period, 0, barsToScan, rates);
   if(copied <= 0) return rates_total;
   int total = copied;

   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(atrHandle, 0, 0, total, atrBuf) < total) return rates_total;

   for(int i = InpMaxSwingScan + InpSwingLookback + InpConfirmBars; i < total - InpSwingLookback - 1; i++)
   {
      if(InpShowSwings)
      {
         if(SMC_IsSwingHigh(rates, i, InpSwingLookback, total)) DrawSwing(i, rates[i].time, rates[i].high, true);
         if(SMC_IsSwingLow(rates, i, InpSwingLookback, total))  DrawSwing(i, rates[i].time, rates[i].low, false);
      }

      double atr = atrBuf[i];

      // Bullish sweep -> OB -> confirmation
      int swingLowIdx = SMC_FindSwingLow(rates, i + 1, InpSwingLookback, total, InpMaxSwingScan);
      if(swingLowIdx >= 0)
      {
         double swingLow = rates[swingLowIdx].low;
         if(SMC_IsBullishSweep(rates, i, swingLow, atr, InpSweepATR_Mult))
         {
            double obTop, obBottom;
            SMC_OrderBlockFromBar(rates, i, obTop, obBottom);
            if(InpShowOrderBlocks)
               DrawOrderBlock(i, rates[i].time, rates[MathMax(i - InpConfirmBars - 2, 0)].time, obTop, obBottom, true);

            int confirmIdx = SMC_FindBullishConfirmation(rates, i, obTop, InpConfirmBars, atr, InpConfirmATR_Mult);
            if(confirmIdx >= 0)
            {
               DrawConfirmation(rates[confirmIdx].time, rates[confirmIdx].low, true);
               if(InpShowFVG)
               {
                  double gl, gh;
                  for(int k = confirmIdx; k <= i; k++)
                     if(SMC_HasBullishFVG(rates, k, total, gl, gh))
                        DrawFVG(rates[k+2].time, rates[k].time, gl, gh, true);
               }
            }
         }
      }

      // Bearish sweep -> OB -> confirmation
      int swingHighIdx = SMC_FindSwingHigh(rates, i + 1, InpSwingLookback, total, InpMaxSwingScan);
      if(swingHighIdx >= 0)
      {
         double swingHigh = rates[swingHighIdx].high;
         if(SMC_IsBearishSweep(rates, i, swingHigh, atr, InpSweepATR_Mult))
         {
            double obTop, obBottom;
            SMC_OrderBlockFromBar(rates, i, obTop, obBottom);
            if(InpShowOrderBlocks)
               DrawOrderBlock(i, rates[i].time, rates[MathMax(i - InpConfirmBars - 2, 0)].time, obTop, obBottom, false);

            int confirmIdx = SMC_FindBearishConfirmation(rates, i, obBottom, InpConfirmBars, atr, InpConfirmATR_Mult);
            if(confirmIdx >= 0)
            {
               DrawConfirmation(rates[confirmIdx].time, rates[confirmIdx].high, false);
               if(InpShowFVG)
               {
                  double gl, gh;
                  for(int k = confirmIdx; k <= i; k++)
                     if(SMC_HasBearishFVG(rates, k, total, gl, gh))
                        DrawFVG(rates[k+2].time, rates[k].time, gl, gh, false);
               }
            }
         }
      }
   }

   return rates_total;
}
//+------------------------------------------------------------------+
