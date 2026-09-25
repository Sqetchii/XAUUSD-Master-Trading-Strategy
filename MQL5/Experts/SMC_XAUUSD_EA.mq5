//+------------------------------------------------------------------+
//| SMC_XAUUSD_EA.mq5                                                 |
//|                                                                    |
//| Rule-based Smart Money Concepts (SMC) Expert Advisor for XAUUSD.  |
//|                                                                    |
//| Logic: HTF trend filter -> liquidity sweep of a swing high/low -> |
//| order block forms from the sweep bar -> momentum confirmation     |
//| close through the order block -> optional FVG confluence and      |
//| premium/discount filter -> market entry with ATR-based stop and   |
//| a fixed R:R take-profit.                                          |
//|                                                                    |
//| This is a mechanical implementation for backtesting/research. See |
//| research/SMC_XAUUSD_Research.md for the evidence behind (and      |
//| against) each component before trading it live. No parameter set  |
//| here is "proven" -- validate it yourself in the Strategy Tester   |
//| with walk-forward and out-of-sample testing.                      |
//+------------------------------------------------------------------+
#property copyright "Research/backtesting tool - no performance is guaranteed"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <SMC\SMCCore.mqh>

CTrade trade;

//=================== INPUTS =========================================

input group "=== Entry Timeframe ==="
input ENUM_TIMEFRAMES InpTimeframe        = PERIOD_M15;   // Signal timeframe

input group "=== Market Structure / HTF Trend Filter ==="
input int              InpSwingLookback   = 5;            // Bars each side to confirm a swing point
input int              InpMaxSwingScan    = 300;           // Max bars back to search for the reference swing
input bool              InpUseHTFTrendFilter = true;
input ENUM_TIMEFRAMES  InpHTF             = PERIOD_H1;    // Higher timeframe for trend bias
input int               InpHTF_EMA_Period  = 50;

input group "=== Liquidity Sweep & Order Block ==="
input int               InpATR_Period      = 14;
input double            InpSweepATR_Mult   = 0.15;         // Min wick-through beyond swing, in ATR
input int               InpConfirmBars     = 3;            // Bars allowed for confirmation close after sweep
input double            InpConfirmATR_Mult = 0.30;         // Min confirmation candle range, in ATR
input int               InpMaxSweepAge     = 5;            // Sweep bar must be within this many bars of "now"

input group "=== Fair Value Gap Confluence (optional) ==="
input bool               InpRequireFVG      = false;        // Require a 3-bar imbalance between sweep and confirmation

input group "=== Premium / Discount Filter ==="
input bool               InpUsePremiumDiscount = true;      // Buys only in discount, sells only in premium of the swing leg

input group "=== Stop Loss / Take Profit ==="
input double             InpSL_ATR_Buffer   = 0.10;         // Extra buffer beyond the sweep wick, in ATR
input double             InpMinSL_ATR       = 0.50;         // Reject setup if resulting SL distance is below this (too tight/noisy)
input double             InpRR              = 2.0;          // Take-profit as a multiple of the SL distance
input bool               InpUseBreakeven    = true;
input double             InpBreakevenAtR    = 1.0;          // Move SL to breakeven once profit reaches this multiple of R

input group "=== Sessions (Broker/Server Time) ==="
input bool               InpUseSessionFilter = true;
input bool               InpSession1Enabled  = true;        // London open
input int                InpSession1StartHour = 9;
input int                InpSession1EndHour   = 12;
input bool               InpSession2Enabled  = true;        // London/NY overlap
input int                InpSession2StartHour = 14;
input int                InpSession2EndHour   = 17;
input bool               InpSession3Enabled  = false;       // NY close / Asia handover
input int                InpSession3StartHour = 21;
input int                InpSession3EndHour   = 22;

input group "=== Risk Management ==="
input double             InpRiskPercent      = 1.0;         // % of balance risked per trade
input double             InpDailyLossLimitPercent = 3.0;    // Stop new entries for the day after this equity loss
input int                InpMaxTradesPerDay  = 4;
input int                InpMaxConsecLosses  = 3;
input int                InpCooldownBars     = 20;          // Bars to pause after hitting InpMaxConsecLosses
input double              InpMaxSpreadPoints  = 600;         // Skip entries if current spread exceeds this (points)
input int                 InpMagicNumber      = 20260925;

//=================== STATE ==========================================

int    atrHandle       = INVALID_HANDLE;
int    htfEmaHandle    = INVALID_HANDLE;
datetime lastBarTime   = 0;

int    dayOfYearCache   = -1;
int    yearCache        = -1;
double dayStartEquity    = 0;
int    tradesToday       = 0;
int    consecLosses      = 0;
int    cooldownBarsLeft  = 0;
bool   hadOpenPosition   = false;

//=================== INIT / DEINIT ===================================

int OnInit()
{
   atrHandle = iATR(_Symbol, InpTimeframe, InpATR_Period);
   if(atrHandle == INVALID_HANDLE)
   {
      Print("Failed to create ATR handle");
      return INIT_FAILED;
   }

   if(InpUseHTFTrendFilter)
   {
      htfEmaHandle = iMA(_Symbol, InpHTF, InpHTF_EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
      if(htfEmaHandle == INVALID_HANDLE)
      {
         Print("Failed to create HTF EMA handle");
         return INIT_FAILED;
      }
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFillingBySymbol(_Symbol);

   ResetDailyState();

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(atrHandle != INVALID_HANDLE)    IndicatorRelease(atrHandle);
   if(htfEmaHandle != INVALID_HANDLE) IndicatorRelease(htfEmaHandle);
}

//=================== HELPERS ==========================================

void ResetDailyState()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dayOfYearCache  = dt.day_of_year;
   yearCache       = dt.year;
   dayStartEquity  = AccountInfoDouble(ACCOUNT_EQUITY);
   tradesToday     = 0;
}

void CheckNewDay()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_year != dayOfYearCache || dt.year != yearCache)
      ResetDailyState();
}

bool IsWithinDailyLossLimit()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double lossPercent = (dayStartEquity - equity) / dayStartEquity * 100.0;
   return lossPercent < InpDailyLossLimitPercent;
}

bool IsInSession()
{
   if(!InpUseSessionFilter) return true;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour;

   if(InpSession1Enabled && h >= InpSession1StartHour && h < InpSession1EndHour) return true;
   if(InpSession2Enabled && h >= InpSession2StartHour && h < InpSession2EndHour) return true;
   if(InpSession3Enabled && h >= InpSession3StartHour && h < InpSession3EndHour) return true;
   return false;
}

bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         return true;
   }
   return false;
}

// Detects that our own position closed since the last check, and
// updates the consecutive-loss / cooldown counters from the most
// recent matching deal in history.
void UpdateTradeOutcomeTracking()
{
   bool hasNow = HasOpenPosition();
   if(hadOpenPosition && !hasNow)
   {
      datetime from = TimeCurrent() - 3 * 24 * 3600;
      HistorySelect(from, TimeCurrent());
      double lastProfit = 0;
      datetime lastTime = 0;
      int total = HistoryDealsTotal();
      for(int i = total - 1; i >= 0; i--)
      {
         ulong dealTicket = HistoryDealGetTicket(i);
         if(dealTicket == 0) continue;
         if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol) continue;
         if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != InpMagicNumber) continue;
         if(HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
         datetime t = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
         if(t > lastTime)
         {
            lastTime = t;
            lastProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                       + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
                       + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
         }
      }

      if(lastProfit < 0)
      {
         consecLosses++;
         if(consecLosses >= InpMaxConsecLosses)
         {
            cooldownBarsLeft = InpCooldownBars;
            consecLosses = 0;
            Print("Max consecutive losses reached, cooling down for ", InpCooldownBars, " bars");
         }
      }
      else if(lastProfit > 0)
      {
         consecLosses = 0;
      }
   }
   hadOpenPosition = hasNow;
}

double CalcLotSize(double slDistance)
{
   if(slDistance <= 0) return 0;

   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0 || tickValue <= 0) return 0;

   double lossPerLot = (slDistance / tickSize) * tickValue;
   if(lossPerLot <= 0) return 0;

   double lots = riskMoney / lossPerLot;

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = minLot;

   lots = MathFloor(lots / step) * step;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return lots;
}

bool GetHTFBias(bool &bullishOK, bool &bearishOK)
{
   bullishOK = true;
   bearishOK = true;
   if(!InpUseHTFTrendFilter) return true;

   double emaBuf[];
   ArraySetAsSeries(emaBuf, true);
   if(CopyBuffer(htfEmaHandle, 0, 0, 2, emaBuf) < 2) return false;

   MqlRates htfRates[];
   ArraySetAsSeries(htfRates, true);
   if(CopyRates(_Symbol, InpHTF, 0, 2, htfRates) < 2) return false;

   double htfClose = htfRates[1].close; // last closed HTF bar
   double ema      = emaBuf[1];

   bullishOK = htfClose > ema;
   bearishOK = htfClose < ema;
   return true;
}

void ManageOpenPosition()
{
   if(!InpUseBreakeven) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double rDistance = MathAbs(entry - sl);
      if(rDistance <= 0) continue;

      double price = (type == POSITION_TYPE_BUY)
                      ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                      : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(type == POSITION_TYPE_BUY)
      {
         double profitR = (price - entry) / rDistance;
         if(profitR >= InpBreakevenAtR && sl < entry)
            trade.PositionModify(ticket, entry, tp);
      }
      else
      {
         double profitR = (entry - price) / rDistance;
         if(profitR >= InpBreakevenAtR && (sl > entry || sl == 0))
            trade.PositionModify(ticket, entry, tp);
      }
   }
}

//=================== SIGNAL EVALUATION ==========================================

struct SignalResult
{
   bool   valid;
   bool   isBuy;
   double sl;
};

bool EvaluateSignal(SignalResult &result)
{
   result.valid = false;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int barsNeeded = InpMaxSwingScan + InpSwingLookback + InpConfirmBars + 10;
   int copied = CopyRates(_Symbol, InpTimeframe, 0, barsNeeded, rates);
   if(copied < barsNeeded) return false;
   int total = copied;

   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(atrHandle, 0, 0, InpMaxSwingScan + 5, atrBuf) < InpMaxSwingScan + 5) return false;

   bool bullishBiasOK, bearishBiasOK;
   if(!GetHTFBias(bullishBiasOK, bearishBiasOK)) return false;

   // --- Try bullish setup: sweep of a swing low, confirmed back above the order block.
   if(bullishBiasOK)
   {
      for(int sweepIdx = 1; sweepIdx <= InpMaxSweepAge; sweepIdx++)
      {
         int swingLowIdx = SMC_FindSwingLow(rates, sweepIdx + 1, InpSwingLookback, total, InpMaxSwingScan);
         if(swingLowIdx < 0) continue;
         double swingLow = rates[swingLowIdx].low;
         double atr = atrBuf[sweepIdx];

         if(!SMC_IsBullishSweep(rates, sweepIdx, swingLow, atr, InpSweepATR_Mult)) continue;

         double obTop, obBottom;
         SMC_OrderBlockFromBar(rates, sweepIdx, obTop, obBottom);

         int confirmIdx = SMC_FindBullishConfirmation(rates, sweepIdx, obTop, InpConfirmBars, atr, InpConfirmATR_Mult);
         if(confirmIdx < 0) continue;
         if(confirmIdx != 1) continue; // only act on a confirmation that just closed on the last bar

         if(InpRequireFVG && !SMC_HasFVGInRange(rates, confirmIdx, sweepIdx, total, true)) continue;

         if(InpUsePremiumDiscount)
         {
            int swingHighIdx = SMC_FindSwingHigh(rates, sweepIdx + 1, InpSwingLookback, total, InpMaxSwingScan);
            if(swingHighIdx >= 0)
            {
               double swingHigh = rates[swingHighIdx].high;
               if(!SMC_IsDiscount(rates[confirmIdx].close, swingHigh, swingLow)) continue;
            }
         }

         double minSl  = InpMinSL_ATR * atr;
         double sl     = rates[sweepIdx].low - InpSL_ATR_Buffer * atr;
         double entryEstimate = rates[confirmIdx].close;
         double dist = entryEstimate - sl;
         if(dist < minSl) continue;

         result.valid = true;
         result.isBuy = true;
         result.sl    = sl;
         return true;
      }
   }

   // --- Try bearish setup: sweep of a swing high, confirmed back below the order block.
   if(bearishBiasOK)
   {
      for(int sweepIdx = 1; sweepIdx <= InpMaxSweepAge; sweepIdx++)
      {
         int swingHighIdx = SMC_FindSwingHigh(rates, sweepIdx + 1, InpSwingLookback, total, InpMaxSwingScan);
         if(swingHighIdx < 0) continue;
         double swingHigh = rates[swingHighIdx].high;
         double atr = atrBuf[sweepIdx];

         if(!SMC_IsBearishSweep(rates, sweepIdx, swingHigh, atr, InpSweepATR_Mult)) continue;

         double obTop, obBottom;
         SMC_OrderBlockFromBar(rates, sweepIdx, obTop, obBottom);

         int confirmIdx = SMC_FindBearishConfirmation(rates, sweepIdx, obBottom, InpConfirmBars, atr, InpConfirmATR_Mult);
         if(confirmIdx < 0) continue;
         if(confirmIdx != 1) continue;

         if(InpRequireFVG && !SMC_HasFVGInRange(rates, confirmIdx, sweepIdx, total, false)) continue;

         if(InpUsePremiumDiscount)
         {
            int swingLowIdx = SMC_FindSwingLow(rates, sweepIdx + 1, InpSwingLookback, total, InpMaxSwingScan);
            if(swingLowIdx >= 0)
            {
               double swingLow = rates[swingLowIdx].low;
               if(!SMC_IsPremium(rates[confirmIdx].close, swingHigh, swingLow)) continue;
            }
         }

         double minSl = InpMinSL_ATR * atr;
         double sl    = rates[sweepIdx].high + InpSL_ATR_Buffer * atr;
         double entryEstimate = rates[confirmIdx].close;
         double dist = sl - entryEstimate;
         if(dist < minSl) continue;

         result.valid = true;
         result.isBuy = false;
         result.sl    = sl;
         return true;
      }
   }

   return false;
}

void TryEnter()
{
   if(HasOpenPosition()) return;
   if(cooldownBarsLeft > 0) return;
   if(tradesToday >= InpMaxTradesPerDay) return;
   if(!IsWithinDailyLossLimit()) return;
   if(!IsInSession()) return;

   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
   if(spread > InpMaxSpreadPoints) return;

   SignalResult sig;
   if(!EvaluateSignal(sig)) return;

   double entryPrice = sig.isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slDist = sig.isBuy ? (entryPrice - sig.sl) : (sig.sl - entryPrice);
   if(slDist <= 0) return;

   double tp = sig.isBuy ? entryPrice + InpRR * slDist
                          : entryPrice - InpRR * slDist;

   double lots = CalcLotSize(slDist);
   if(lots <= 0) return;

   bool sent;
   if(sig.isBuy)
      sent = trade.Buy(lots, _Symbol, entryPrice, sig.sl, tp, "SMC bullish sweep+OB");
   else
      sent = trade.Sell(lots, _Symbol, entryPrice, sig.sl, tp, "SMC bearish sweep+OB");

   if(sent)
      tradesToday++;
   else
      Print("Order send failed: ", trade.ResultRetcodeDescription());
}

//=================== MAIN =========================================

void OnTick()
{
   CheckNewDay();
   UpdateTradeOutcomeTracking();
   ManageOpenPosition();

   datetime t = iTime(_Symbol, InpTimeframe, 0);
   if(t == lastBarTime) return; // only act once per closed bar
   lastBarTime = t;

   if(cooldownBarsLeft > 0) cooldownBarsLeft--;

   TryEnter();
}
//+------------------------------------------------------------------+
