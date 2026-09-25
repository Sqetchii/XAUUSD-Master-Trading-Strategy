//+------------------------------------------------------------------+
//| SMCCore.mqh                                                      |
//| Shared, stateless Smart Money Concepts detection primitives used |
//| by both SMC_XAUUSD_EA.mq5 and SMC_Visualizer.mq5, so the EA's    |
//| signals and the chart drawing can never drift apart.             |
//|                                                                    |
//| Indexing convention used throughout this file: "rates[]" is       |
//| series-ordered exactly like CopyRates() after                     |
//| ArraySetAsSeries(rates, true): rates[0] is the newest bar, and    |
//| increasing index means further back in time. Callers must only    |
//| evaluate signals on CLOSED bars (index >= 1) to avoid repainting  |
//| off the still-forming bar.                                        |
//+------------------------------------------------------------------+
#ifndef __SMC_CORE_MQH__
#define __SMC_CORE_MQH__

//--- A swing point is confirmed only once "lookback" newer AND older
//--- bars both exist and are strictly lower/higher, so it never repaints
//--- once printed.
bool SMC_IsSwingHigh(const MqlRates &rates[], int i, int lookback, int total)
{
   if(i - lookback < 0 || i + lookback >= total) return false;
   double h = rates[i].high;
   for(int k = 1; k <= lookback; k++)
   {
      if(rates[i-k].high >= h || rates[i+k].high >= h) return false;
   }
   return true;
}

bool SMC_IsSwingLow(const MqlRates &rates[], int i, int lookback, int total)
{
   if(i - lookback < 0 || i + lookback >= total) return false;
   double l = rates[i].low;
   for(int k = 1; k <= lookback; k++)
   {
      if(rates[i-k].low <= l || rates[i+k].low <= l) return false;
   }
   return true;
}

//--- Scans from "from" (inclusive) towards older bars for the nearest
//--- confirmed swing high/low. Returns its index, or -1 if none found
//--- within maxScan bars.
int SMC_FindSwingHigh(const MqlRates &rates[], int from, int lookback, int total, int maxScan)
{
   int scanned = 0;
   for(int i = from; i + lookback < total && scanned < maxScan; i++, scanned++)
      if(SMC_IsSwingHigh(rates, i, lookback, total)) return i;
   return -1;
}

int SMC_FindSwingLow(const MqlRates &rates[], int from, int lookback, int total, int maxScan)
{
   int scanned = 0;
   for(int i = from; i + lookback < total && scanned < maxScan; i++, scanned++)
      if(SMC_IsSwingLow(rates, i, lookback, total)) return i;
   return -1;
}

//--- Liquidity sweep ("stop hunt"): price wicks through a prior swing
//--- level by at least mult*ATR, then closes back on the other side of
//--- it within the same bar. This is the ICT "sweep, reaction,
//--- displacement" opening move.
bool SMC_IsBullishSweep(const MqlRates &rates[], int i, double swingLow, double atr, double mult)
{
   if(atr <= 0) return false;
   return (rates[i].low < swingLow - mult*atr) && (rates[i].close > swingLow);
}

bool SMC_IsBearishSweep(const MqlRates &rates[], int i, double swingHigh, double atr, double mult)
{
   if(atr <= 0) return false;
   return (rates[i].high > swingHigh + mult*atr) && (rates[i].close < swingHigh);
}

//--- Order block = the body of the sweep bar itself (the last "smart
//--- money" footprint before the reversal fires).
void SMC_OrderBlockFromBar(const MqlRates &rates[], int i, double &obTop, double &obBottom)
{
   obTop    = MathMax(rates[i].open, rates[i].close);
   obBottom = MathMin(rates[i].open, rates[i].close);
}

//--- Confirmation: within confirmBars after the sweep, a candle must
//--- close back through the order block with enough range (momentum)
//--- to rule out a low-conviction, noise-driven poke.
int SMC_FindBullishConfirmation(const MqlRates &rates[], int sweepIdx, double obTop,
                                 int confirmBars, double atr, double confirmATRMult)
{
   int floorIdx = sweepIdx - confirmBars;
   if(floorIdx < 0) floorIdx = 0;
   for(int j = sweepIdx - 1; j >= floorIdx; j--)
   {
      double range = rates[j].high - rates[j].low;
      if(rates[j].close > obTop && range >= confirmATRMult * atr) return j;
   }
   return -1;
}

int SMC_FindBearishConfirmation(const MqlRates &rates[], int sweepIdx, double obBottom,
                                 int confirmBars, double atr, double confirmATRMult)
{
   int floorIdx = sweepIdx - confirmBars;
   if(floorIdx < 0) floorIdx = 0;
   for(int j = sweepIdx - 1; j >= floorIdx; j--)
   {
      double range = rates[j].high - rates[j].low;
      if(rates[j].close < obBottom && range >= confirmATRMult * atr) return j;
   }
   return -1;
}

//--- Fair Value Gap / imbalance across three consecutive bars. In
//--- series order the newest of the three is "i" and the oldest is
//--- "i+2". A bullish FVG leaves an untraded gap between the oldest
//--- bar's high and the newest bar's low.
bool SMC_HasBullishFVG(const MqlRates &rates[], int i, int total, double &gapLow, double &gapHigh)
{
   if(i + 2 >= total) return false;
   if(rates[i+2].high < rates[i].low)
   {
      gapLow  = rates[i+2].high;
      gapHigh = rates[i].low;
      return true;
   }
   return false;
}

bool SMC_HasBearishFVG(const MqlRates &rates[], int i, int total, double &gapLow, double &gapHigh)
{
   if(i + 2 >= total) return false;
   if(rates[i+2].low > rates[i].high)
   {
      gapLow  = rates[i].high;
      gapHigh = rates[i+2].low;
      return true;
   }
   return false;
}

//--- Scans the window between the confirmation bar and the sweep bar
//--- (inclusive) for any 3-bar FVG, used as an optional confluence
//--- filter (InpRequireFVG).
bool SMC_HasFVGInRange(const MqlRates &rates[], int fromIdx, int toIdx, int total, bool bullish)
{
   int lo = MathMin(fromIdx, toIdx);
   int hi = MathMax(fromIdx, toIdx);
   double gl, gh;
   for(int i = lo; i <= hi; i++)
   {
      if(bullish)
      {
         if(SMC_HasBullishFVG(rates, i, total, gl, gh)) return true;
      }
      else
      {
         if(SMC_HasBearishFVG(rates, i, total, gl, gh)) return true;
      }
   }
   return false;
}

//--- Premium/Discount equilibrium of the active swing leg. Buys are
//--- only "smart" in the lower (discount) half of the range, sells only
//--- in the upper (premium) half.
double SMC_Equilibrium(double swingHigh, double swingLow)
{
   return (swingHigh + swingLow) / 2.0;
}

bool SMC_IsDiscount(double price, double swingHigh, double swingLow)
{
   return price <= SMC_Equilibrium(swingHigh, swingLow);
}

bool SMC_IsPremium(double price, double swingHigh, double swingLow)
{
   return price >= SMC_Equilibrium(swingHigh, swingLow);
}

#endif // __SMC_CORE_MQH__
