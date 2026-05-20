//+------------------------------------------------------------------+
//|                                               MuaynyGoldEA.mq5   |
//|                                                                  |
//|  Adaptive Donchian-breakout Expert Advisor tuned for XAUUSD       |
//|  (Gold) on a high-volatility regime.                              |
//|                                                                  |
//|  v3.10 — balance-scaled position slots, ADX entry timing, and a   |
//|  Thai-time session window:                                        |
//|    - Max simultaneous positions scales with account balance.      |
//|      Extra slots are PYRAMID adds, not a grid: a new position     |
//|      opens only when every existing one is already protected at   |
//|      break-even, so total open risk stays ~1R regardless of how   |
//|      many positions are open.                                     |
//|    - ADX(M15) filter: entries require a minimum trend strength,   |
//|      skipping weak / false breakouts in non-trending conditions.  |
//|    - Trading-hours window can be entered directly in Thai time    |
//|      (ICT, UTC+7); the EA converts it to broker server time.      |
//|                                                                  |
//|  v3.00 — integrates the non-martingale "good parts" harvested     |
//|  from Safe_Gold_Pro V3.1, without its grid/recovery core:         |
//|    - Stochastic (M30) confirmation filter.                        |
//|    - Weekend / holiday exit before the Friday gap.                |
//|    - On-chart dashboard for VPS monitoring.                        |
//|                                                                  |
//|  DYNAMIC SIZING                                                   |
//|    Lot size is derived from a % of live equity, so it scales      |
//|    up automatically as the account grows and down as it shrinks.  |
//|    The risk % itself is adaptive: reduced while the account is    |
//|    in drawdown from its equity peak, restored as it recovers.     |
//|                                                                   |
//|  SELF-CORRECTION (cut wrong trades early)                         |
//|    Failed-breakout exit, trend-flip exit, time-in-loss exit.      |
//|                                                                   |
//|  PROFIT LOCKING                                                   |
//|    Partial take-profit, break-even move, ATR trailing.            |
//|                                                                   |
//|  SAFETY NETS                                                      |
//|    Daily-loss circuit breaker, dynamic spread filter, broker      |
//|    stop-level enforcement, session/weekend filters. Never a       |
//|    martingale: risk is reduced after losses, never increased.     |
//|                                                                   |
//|  NOT INVESTMENT ADVICE. Past performance does not predict         |
//|  future results. Backtest with realistic spreads, forward-test    |
//|  on demo, and size positions you can afford to lose entirely.     |
//+------------------------------------------------------------------+
#property copyright "Muayny"
#property link      ""
#property version   "3.10"
#property strict
#property description "Adaptive XAUUSD Donchian-breakout EA: balance-scaled sizing & slots, ADX/Stoch filters, self-correcting exits, profit locking, weekend exit, daily-loss breaker."

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

//--- inputs --------------------------------------------------------
input group "=== Trend Filter ==="
input ENUM_TIMEFRAMES InpTrendTF        = PERIOD_H1;    // Trend timeframe
input int             InpTrendEMA       = 50;           // Trend EMA period

input group "=== Entry (Donchian Breakout) ==="
input ENUM_TIMEFRAMES InpEntryTF        = PERIOD_M15;   // Entry timeframe
input int             InpDonchianLen    = 20;           // Donchian lookback (bars)
input bool            InpRequireMomentum= true;         // Require breakout candle body in trade direction

input group "=== Stochastic Confirmation Filter ==="
input bool            InpUseStochFilter = true;         // Block entries that fire into an exhausted move
input ENUM_TIMEFRAMES InpStochTF        = PERIOD_M30;   // Stochastic timeframe
input int             InpStochK         = 5;            // %K period
input int             InpStochD         = 3;            // %D period
input int             InpStochSlowing   = 3;            // Slowing
input int             InpStochOB        = 80;           // Overbought — no longs at/above this
input int             InpStochOS        = 20;           // Oversold — no shorts at/below this

input group "=== ADX Entry-Timing Filter ==="
input bool            InpUseAdxFilter   = true;         // Require a minimum trend strength to enter
input int             InpAdxPeriod      = 14;           // ADX period
input double          InpMinAdx         = 22.0;         // Minimum ADX (trend strength) for an entry

input group "=== Adaptive Volatility Gate ==="
input int             InpAtrPeriod      = 14;           // ATR period
input int             InpAtrAvgPeriod   = 100;          // Long-run ATR average window (bars)
input double          InpAtrLoFactor    = 0.70;         // Min ATR as fraction of its average
input double          InpAtrHiFactor    = 3.00;         // Max ATR as fraction of its average

input group "=== Dynamic Risk Sizing ==="
input double          InpBaseRiskPct    = 0.50;         // Base risk per trade (% of equity)
input double          InpAtrSlMult      = 1.5;          // SL = ATR * this
input double          InpAtrTpMult      = 3.0;          // Final TP = ATR * this
input double          InpMaxLot         = 5.0;          // Hard cap on lot size
input double          InpMinLot         = 0.01;         // Hard floor on lot size

input group "=== Adaptive Drawdown Scaling ==="
input bool            InpAdaptiveRisk   = true;         // Scale risk down while in equity drawdown
input double          InpDDStartPct     = 4.0;          // Start cutting risk when DD from peak exceeds this %
input double          InpDDFullPct      = 12.0;         // Risk reaches its floor at this DD %
input double          InpRiskFloorFrac  = 0.35;         // Risk floor = BaseRisk * this fraction

input group "=== Daily-Loss Circuit Breaker ==="
input bool            InpUseDailyStop   = true;         // Halt new entries after daily loss threshold
input double          InpDailyLossPct   = 4.0;          // Halt if daily loss exceeds % of start-of-day equity

input group "=== Profit Locking ==="
input bool            InpUsePartialTP   = true;         // Take partial profit at a milestone
input double          InpPartialAtr     = 1.2;          // Partial-TP trigger (ATR of favorable move)
input double          InpPartialPct     = 50.0;         // Percent of initial volume to close at partial
input bool            InpUseBreakEven   = true;         // Move SL to break-even
input double          InpBreakEvenAtr   = 0.7;          // Move to BE after this many ATR of profit
input bool            InpUseTrailing    = true;         // Enable ATR trailing stop
input double          InpTrailStartAtr  = 1.0;          // Start trailing after N x ATR profit
input double          InpTrailAtrMult   = 1.2;          // Trailing distance in ATR

input group "=== Self-Correction (cut losers early) ==="
input bool            InpFailBreakoutExit= true;        // Exit if price closes back through the breakout level
input bool            InpTrendFlipExit  = true;         // Exit if H1 trend flips against the position
input int             InpMaxBarsInLoss  = 10;           // Exit a still-losing position after N entry-TF bars (0=off)

input group "=== Spread Filter ==="
input double          InpMaxSpreadAtrFrac= 0.25;        // Max spread as fraction of ATR
input int             InpMaxSpreadHardPts= 80;          // Absolute max spread (points) — hard cap

input group "=== Session (Trading Hours) ==="
input bool            InpHoursInThaiTime= true;         // Start/End hours are Thai time (ICT, UTC+7); off = server time
input int             InpBrokerGMTOffset= 3;            // Broker server GMT offset, hours (summer=3, winter=2)
input int             InpStartHour      = 7;            // Session start hour
input int             InpEndHour        = 3;            // Session end hour (next day if < start)
input bool            InpAvoidFriday    = true;         // Stop new entries 2h before session end on Friday

input group "=== Dynamic Position Slots ==="
input bool            InpDynamicSlots   = true;         // Scale max simultaneous positions with balance
input double          InpBalancePerSlot = 5000.0;       // Account balance per additional position slot
input int             InpMaxSlotsCap    = 3;            // Hard ceiling on simultaneous positions
input bool            InpPyramidRiskFree= true;         // Add a position only when existing ones are at break-even+
input int             InpMaxPositions   = 1;            // Max positions used only when dynamic slots are OFF

input group "=== Weekend / Holiday Exit ==="
input bool            InpUseWeekendExit = true;         // Close positions before the weekend / holiday gap
input int             InpBlockNewMins   = 120;          // Block new entries N minutes before Fri/pre-holiday close
input int             InpCloseAllMins   = 15;           // Close all own positions N minutes before that close

input group "=== Dashboard ==="
input bool            InpShowDashboard  = true;         // Draw the on-chart status panel

input group "=== Identification ==="
input long            InpMagic          = 20260520;     // Magic number
input string          InpComment        = "MuaynyGold"; // Order comment

//--- per-position state -------------------------------------------
struct PosState
  {
   ulong    ticket;
   double   initVolume;
   bool     partialDone;
   datetime entryBarTime;
   double   triggerLevel;   // Donchian level the breakout cleared
   int      dir;            // +1 long, -1 short
  };
PosState g_states[];

//--- globals -------------------------------------------------------
int      hTrendEMA      = INVALID_HANDLE;
int      hAtr           = INVALID_HANDLE;
int      hStoch         = INVALID_HANDLE;
int      hAdx           = INVALID_HANDLE;
datetime g_lastBarTime  = 0;
datetime g_dayStart     = 0;
double   g_dayStartEquity = 0.0;
bool     g_dayHalted    = false;
double   g_equityPeak   = 0.0;
CTrade   g_trade;

//--- dashboard cache (filled in OnTick, read in OnTimer) -----------
int      g_uiTrend      = 0;
double   g_uiAtrNow     = 0.0;
double   g_uiAtrAvg     = 0.0;
bool     g_uiAtrOk      = false;
string   g_uiState      = "init";

#define UI_PREFIX "MGE_"

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
int OnInit()
  {
   hTrendEMA = iMA(_Symbol, InpTrendTF, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   hAtr      = iATR(_Symbol, InpEntryTF, InpAtrPeriod);
   hStoch    = iStochastic(_Symbol, InpStochTF, InpStochK, InpStochD, InpStochSlowing, MODE_SMA, STO_LOWHIGH);
   hAdx      = iADX(_Symbol, InpEntryTF, InpAdxPeriod);

   if(hTrendEMA == INVALID_HANDLE || hAtr == INVALID_HANDLE
      || hStoch == INVALID_HANDLE || hAdx == INVALID_HANDLE)
     {
      Print("MuaynyGoldEA: failed to create indicator handles.");
      return INIT_FAILED;
     }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(20);
   g_trade.SetTypeFillingBySymbol(_Symbol); // auto filling mode — covers BOTH open and close
   g_trade.LogLevel(LOG_LEVEL_ERRORS);

   if(InpBaseRiskPct <= 0.0 || InpBaseRiskPct > 5.0)
     {
      Print("MuaynyGoldEA: InpBaseRiskPct must be in (0, 5].");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpAtrSlMult <= 0.0 || InpAtrTpMult <= 0.0 || InpDonchianLen < 5)
      return INIT_PARAMETERS_INCORRECT;
   if(InpAtrAvgPeriod < 20)
      return INIT_PARAMETERS_INCORRECT;
   if(InpRiskFloorFrac <= 0.0 || InpRiskFloorFrac > 1.0)
      return INIT_PARAMETERS_INCORRECT;
   if(InpDDFullPct <= InpDDStartPct)
      return INIT_PARAMETERS_INCORRECT;
   if(InpPartialPct <= 0.0 || InpPartialPct >= 100.0)
      return INIT_PARAMETERS_INCORRECT;
   if(InpBalancePerSlot <= 0.0 || InpMaxSlotsCap < 1 || InpMaxPositions < 1)
      return INIT_PARAMETERS_INCORRECT;
   if(InpBrokerGMTOffset < -12 || InpBrokerGMTOffset > 14)
      return INIT_PARAMETERS_INCORRECT;

   string sym = _Symbol;
   StringToUpper(sym);
   if(StringFind(sym, "XAU") < 0 && StringFind(sym, "GOLD") < 0)
      PrintFormat("MuaynyGoldEA: warning — symbol %s does not look like Gold. Defaults are tuned for XAUUSD.", _Symbol);

   g_equityPeak = AccountInfoDouble(ACCOUNT_EQUITY);
   ResetDailyBaseline();
   AdoptExistingPositions();
   ReportSessionWindow();

   if(InpShowDashboard)
     {
      EventSetTimer(2);
      DrawDashboard();
     }
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Deinit                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(hTrendEMA != INVALID_HANDLE) IndicatorRelease(hTrendEMA);
   if(hAtr      != INVALID_HANDLE) IndicatorRelease(hAtr);
   if(hStoch    != INVALID_HANDLE) IndicatorRelease(hStoch);
   if(hAdx      != INVALID_HANDLE) IndicatorRelease(hAdx);
   ObjectsDeleteAll(0, UI_PREFIX);
   Comment("");
  }

//+------------------------------------------------------------------+
//| Timer — dashboard refresh only                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
   if(InpShowDashboard)
      DrawDashboard();
  }

//+------------------------------------------------------------------+
//| Tick                                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > g_equityPeak) g_equityPeak = equity;

   RollDailyBaseline();
   PruneStates();

   double atrNow = 0.0, atrAvg = 0.0;
   bool atrOk = GetAtrStats(atrNow, atrAvg);
   g_uiAtrNow = atrNow;
   g_uiAtrAvg = atrAvg;
   g_uiAtrOk  = atrOk;

   if(atrOk)
      ManagePositionsTick(atrNow);

   // Weekend/holiday exit runs every tick so positions close promptly.
   bool weekendBlock = ManageWeekendExit();

   datetime barT = (datetime)iTime(_Symbol, InpEntryTF, 0);
   if(barT == 0 || barT == g_lastBarTime)
      return;
   g_lastBarTime = barT;

   if(!atrOk) { g_uiState = "warming up"; return; }

   int trend = GetTrendDirection();
   g_uiTrend = trend;

   // --- self-correction runs before any new entry ---
   bool closedAny = ManagePositionsBar(trend);
   if(closedAny)
     {
      PruneStates();
      g_uiState = "self-correct exit";
      return;
     }

   // --- entry gating ---
   if(weekendBlock)                           { g_uiState = "weekend block";  return; }
   if(g_dayHalted)                            { g_uiState = "daily halt";     return; }
   if(trend == 0)                             { g_uiState = "no trend";       return; }
   if(!IsTradingTime())                       { g_uiState = "out of session"; return; }
   if(!IsSpreadOk(atrNow))                    { g_uiState = "spread too high";return; }

   int openCount = CountOwnPositions();
   int slots     = MaxSlots();
   if(openCount >= slots)                     { g_uiState = "slots full";     return; }

   if(atrNow < InpAtrLoFactor * atrAvg)        { g_uiState = "ATR too quiet";  return; }
   if(atrNow > InpAtrHiFactor * atrAvg)        { g_uiState = "ATR shock";      return; }

   double triggerLevel = 0.0;
   int signal = GetBreakoutSignal(trend, triggerLevel);
   if(signal == 0)                            { g_uiState = "waiting breakout"; return; }

   if(!AdxConfirms())                          { g_uiState = "ADX too weak";   return; }
   if(!StochConfirms(signal))                  { g_uiState = "stoch blocked";  return; }
   if(openCount > 0 && !PyramidAddAllowed(signal))
     { g_uiState = "pyramid: wait BE"; return; }

   PlaceEntry(signal, atrNow, triggerLevel);
   g_uiState = (openCount > 0) ? "pyramid add sent" : "entry sent";
  }

//+------------------------------------------------------------------+
//| Trend direction from H1 EMA                                      |
//+------------------------------------------------------------------+
int GetTrendDirection()
  {
   double ema[];
   ArraySetAsSeries(ema, true);
   if(CopyBuffer(hTrendEMA, 0, 0, 2, ema) <= 0) return 0;
   double price = iClose(_Symbol, InpTrendTF, 1);
   if(price > ema[1]) return 1;
   if(price < ema[1]) return -1;
   return 0;
  }

//+------------------------------------------------------------------+
//| Donchian-breakout signal; outputs the level that was cleared      |
//+------------------------------------------------------------------+
int GetBreakoutSignal(int trendDir, double &triggerLevel)
  {
   int    need = InpDonchianLen + 2;
   double high[], low[], open[], close[];
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);
   ArraySetAsSeries(open,  true);
   ArraySetAsSeries(close, true);

   if(CopyHigh (_Symbol, InpEntryTF, 0, need, high)  < need) return 0;
   if(CopyLow  (_Symbol, InpEntryTF, 0, need, low)   < need) return 0;
   if(CopyOpen (_Symbol, InpEntryTF, 0, need, open)  < need) return 0;
   if(CopyClose(_Symbol, InpEntryTF, 0, need, close) < need) return 0;

   double hi = -DBL_MAX, lo = DBL_MAX;
   for(int i = 2; i <= InpDonchianLen + 1; i++)
     {
      if(high[i] > hi) hi = high[i];
      if(low[i]  < lo) lo = low[i];
     }

   double c = close[1];
   double o = open[1];
   bool bullBody = (c > o);
   bool bearBody = (c < o);

   if(trendDir > 0 && c > hi)
     {
      if(InpRequireMomentum && !bullBody) return 0;
      triggerLevel = hi;
      return 1;
     }
   if(trendDir < 0 && c < lo)
     {
      if(InpRequireMomentum && !bearBody) return 0;
      triggerLevel = lo;
      return -1;
     }
   return 0;
  }

//+------------------------------------------------------------------+
//| Stochastic confirmation: block entries into an exhausted move     |
//| Fails open (returns true) if data is unavailable.                 |
//+------------------------------------------------------------------+
bool StochConfirms(int dir)
  {
   if(!InpUseStochFilter) return true;

   double k[], d[];
   ArraySetAsSeries(k, true);
   ArraySetAsSeries(d, true);
   if(CopyBuffer(hStoch, MAIN_LINE,   0, 2, k) < 2) return true;
   if(CopyBuffer(hStoch, SIGNAL_LINE, 0, 2, d) < 2) return true;

   double kk = k[1]; // last closed Stoch bar
   double dd = d[1];

   if(dir > 0)
      return (kk < (double)InpStochOB && kk >= dd); // not overbought + %K above %D
   return (kk > (double)InpStochOS && kk <= dd);    // not oversold   + %K below %D
  }

//+------------------------------------------------------------------+
//| ADX trend-strength entry filter (fails open if data missing)      |
//+------------------------------------------------------------------+
bool AdxConfirms()
  {
   if(!InpUseAdxFilter) return true;
   double adx[];
   ArraySetAsSeries(adx, true);
   if(CopyBuffer(hAdx, MAIN_LINE, 0, 2, adx) < 2) return true;
   return (adx[1] >= InpMinAdx);
  }

//+------------------------------------------------------------------+
//| Current ATR and its long-run average                             |
//+------------------------------------------------------------------+
bool GetAtrStats(double &atrNow, double &atrAvg)
  {
   int n = InpAtrAvgPeriod + 2;
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(hAtr, 0, 0, n, atr) < n) return false;

   atrNow = atr[1];
   double sum = 0.0;
   for(int i = 1; i <= InpAtrAvgPeriod; i++)
      sum += atr[i];
   atrAvg = sum / InpAtrAvgPeriod;
   return (atrNow > 0.0 && atrAvg > 0.0);
  }

//+------------------------------------------------------------------+
//| Adaptive risk percent based on drawdown from equity peak          |
//+------------------------------------------------------------------+
double CurrentRiskPct()
  {
   if(!InpAdaptiveRisk || g_equityPeak <= 0.0)
      return InpBaseRiskPct;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd = (g_equityPeak - equity) / g_equityPeak * 100.0;
   if(dd <= InpDDStartPct) return InpBaseRiskPct;
   if(dd >= InpDDFullPct)  return InpBaseRiskPct * InpRiskFloorFrac;

   double t    = (dd - InpDDStartPct) / (InpDDFullPct - InpDDStartPct);
   double mult = 1.0 - t * (1.0 - InpRiskFloorFrac);
   return InpBaseRiskPct * mult;
  }

//+------------------------------------------------------------------+
//| Max simultaneous positions — scales with account balance          |
//+------------------------------------------------------------------+
int MaxSlots()
  {
   if(!InpDynamicSlots)
      return InpMaxPositions;
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   int slots = (int)MathFloor(bal / InpBalancePerSlot);
   if(slots < 1)              slots = 1;
   if(slots > InpMaxSlotsCap) slots = InpMaxSlotsCap;
   return slots;
  }

//+------------------------------------------------------------------+
//| Pyramid-add gate: a position beyond the first may open only when  |
//| every existing position is same-direction AND already protected   |
//| at break-even or better, so total open risk stays ~1R.            |
//+------------------------------------------------------------------+
bool PyramidAddAllowed(int dir)
  {
   if(!InpPyramidRiskFree) return true;

   CPositionInfo pos;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Symbol() != _Symbol || pos.Magic() != InpMagic) continue;

      int pdir = (pos.PositionType() == POSITION_TYPE_BUY) ? 1 : -1;
      if(pdir != dir) return false;            // never pyramid against the existing side

      double sl   = pos.StopLoss();
      double open = pos.PriceOpen();
      if(sl == 0.0) return false;              // unprotected position still carries open risk
      if(dir > 0 && sl < open - _Point) return false;
      if(dir < 0 && sl > open + _Point) return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Place an entry and register its state                            |
//+------------------------------------------------------------------+
void PlaceEntry(int dir, double atrVal, double triggerLevel)
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry = (dir > 0) ? ask : bid;
   double sl    = (dir > 0) ? entry - atrVal * InpAtrSlMult : entry + atrVal * InpAtrSlMult;
   double tp    = (dir > 0) ? entry + atrVal * InpAtrTpMult : entry - atrVal * InpAtrTpMult;

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   EnforceStopDistance(dir, entry, sl, tp);

   double lots = CalcLotByRisk(entry, sl);
   if(lots <= 0.0)
     {
      Print("MuaynyGoldEA: lot size <= 0, skipping.");
      return;
     }

   bool ok = (dir > 0)
             ? g_trade.Buy (lots, _Symbol, entry, sl, tp, InpComment)
             : g_trade.Sell(lots, _Symbol, entry, sl, tp, InpComment);

   if(!ok)
     {
      PrintFormat("MuaynyGoldEA: order send failed. retcode=%d, %s",
                  g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      return;
     }

   RegisterNewPosition(triggerLevel, dir);
   PrintFormat("MuaynyGoldEA: %s %.2f lots @ %.*f, SL %.*f, TP %.*f, risk %.2f%%",
               (dir > 0 ? "BUY" : "SELL"), lots, _Digits, entry,
               _Digits, sl, _Digits, tp, CurrentRiskPct());
  }

//+------------------------------------------------------------------+
//| Per-tick management: partial TP, break-even, trailing             |
//+------------------------------------------------------------------+
void ManagePositionsTick(double atrVal)
  {
   if(atrVal <= 0.0) return;

   CPositionInfo pos;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Symbol() != _Symbol || pos.Magic() != InpMagic) continue;

      ulong  ticket   = pos.Ticket();
      int    si       = FindState(ticket);
      double openPrice= pos.PriceOpen();
      double curPrice = pos.PriceCurrent();
      double curSL    = pos.StopLoss();
      double curTP    = pos.TakeProfit();
      ENUM_POSITION_TYPE type = pos.PositionType();
      int    dir      = (type == POSITION_TYPE_BUY) ? 1 : -1;

      double profit   = (dir > 0) ? (curPrice - openPrice) : (openPrice - curPrice);
      if(profit <= 0.0) continue;
      double profitAtr= profit / atrVal;

      // --- 1) partial take-profit, then lock SL to break-even ---
      if(InpUsePartialTP && si >= 0 && !g_states[si].partialDone
         && profitAtr >= InpPartialAtr)
        {
         DoPartialClose(si, pos.Volume());
        }

      // --- 2) break-even ---
      if(InpUseBreakEven && profitAtr >= InpBreakEvenAtr)
        {
         double beSL = NormalizeDouble(openPrice + dir * _Point, _Digits);
         if(IsStopImprovement(dir, curSL, beSL))
           {
            g_trade.PositionModify(ticket, beSL, curTP);
            curSL = beSL;
           }
        }

      // --- 3) ATR trailing ---
      if(InpUseTrailing && profitAtr >= InpTrailStartAtr)
        {
         double newSL = NormalizeDouble(curPrice - dir * atrVal * InpTrailAtrMult, _Digits);
         if(IsStopImprovement(dir, curSL, newSL))
            g_trade.PositionModify(ticket, newSL, curTP);
        }
     }
  }

//+------------------------------------------------------------------+
//| Per-bar management: self-correcting exits. Returns true if any    |
//| position was closed.                                              |
//+------------------------------------------------------------------+
bool ManagePositionsBar(int trend)
  {
   double closeArr[];
   ArraySetAsSeries(closeArr, true);
   if(CopyClose(_Symbol, InpEntryTF, 0, 3, closeArr) < 3) return false;
   double lastClose = closeArr[1];

   bool closedAny = false;
   CPositionInfo pos;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Symbol() != _Symbol || pos.Magic() != InpMagic) continue;

      ulong ticket = pos.Ticket();
      int   si     = FindState(ticket);
      int   dir    = (pos.PositionType() == POSITION_TYPE_BUY) ? 1 : -1;

      // --- failed-breakout: price closed back through the trigger ---
      if(InpFailBreakoutExit && si >= 0 && g_states[si].triggerLevel > 0.0)
        {
         double trg = g_states[si].triggerLevel;
         if((dir > 0 && lastClose < trg) || (dir < 0 && lastClose > trg))
           {
            if(CloseOwnPosition(ticket, "failed-breakout"))
               closedAny = true;
            continue;
           }
        }

      // --- trend-flip: H1 trend now opposes the position ---
      if(InpTrendFlipExit && trend != 0 && trend != dir)
        {
         if(CloseOwnPosition(ticket, "trend-flip"))
            closedAny = true;
         continue;
        }

      // --- time-in-loss: still underwater after N bars ---
      if(InpMaxBarsInLoss > 0 && si >= 0)
        {
         int bars = iBarShift(_Symbol, InpEntryTF, g_states[si].entryBarTime, false);
         if(bars >= InpMaxBarsInLoss)
           {
            double pl = pos.Profit() + pos.Swap();
            if(pl < 0.0)
              {
               if(CloseOwnPosition(ticket, "time-in-loss"))
                  closedAny = true;
               continue;
              }
           }
        }
     }
   return closedAny;
  }

//+------------------------------------------------------------------+
//| Close a fraction of a position, then move SL to break-even        |
//+------------------------------------------------------------------+
void DoPartialClose(int si, double currentVolume)
  {
   ulong  ticket   = g_states[si].ticket;
   double lotStep  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double closeVol = g_states[si].initVolume * (InpPartialPct / 100.0);
   if(lotStep > 0.0)
      closeVol = MathFloor(closeVol / lotStep) * lotStep;
   closeVol = NormalizeDouble(closeVol, 2);

   if(closeVol < minLot || (currentVolume - closeVol) < minLot)
     {
      g_states[si].partialDone = true;
      return;
     }

   if(g_trade.PositionClosePartial(ticket, closeVol))
     {
      g_states[si].partialDone = true;
      PrintFormat("MuaynyGoldEA: partial close #%I64u %.2f lots locked.", ticket, closeVol);

      if(PositionSelectByTicket(ticket))
        {
         int    dir       = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double curSL     = PositionGetDouble(POSITION_SL);
         double curTP     = PositionGetDouble(POSITION_TP);
         double beSL      = NormalizeDouble(openPrice + dir * _Point, _Digits);
         if(IsStopImprovement(dir, curSL, beSL))
            g_trade.PositionModify(ticket, beSL, curTP);
        }
     }
   else
      PrintFormat("MuaynyGoldEA: partial close #%I64u failed retcode=%d.",
                  ticket, g_trade.ResultRetcode());
  }

//+------------------------------------------------------------------+
//| True if newSL is a strict improvement over curSL for direction    |
//+------------------------------------------------------------------+
bool IsStopImprovement(int dir, double curSL, double newSL)
  {
   if(dir > 0)
      return (newSL > curSL + _Point);
   return (curSL == 0.0 || newSL < curSL - _Point);
  }

//+------------------------------------------------------------------+
//| Close a position fully by ticket                                 |
//+------------------------------------------------------------------+
bool CloseOwnPosition(ulong ticket, string reason)
  {
   if(g_trade.PositionClose(ticket))
     {
      PrintFormat("MuaynyGoldEA: closed #%I64u (%s).", ticket, reason);
      return true;
     }
   PrintFormat("MuaynyGoldEA: close #%I64u failed (%s) retcode=%d.",
               ticket, reason, g_trade.ResultRetcode());
   return false;
  }

//+------------------------------------------------------------------+
//| Close every position owned by this EA                            |
//+------------------------------------------------------------------+
bool CloseAllOwnPositions(string reason)
  {
   bool closedAny = false;
   CPositionInfo pos;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Symbol() != _Symbol || pos.Magic() != InpMagic) continue;
      if(CloseOwnPosition(pos.Ticket(), reason))
         closedAny = true;
     }
   return closedAny;
  }

//+------------------------------------------------------------------+
//| Risk-based lot sizing using the adaptive risk percent             |
//+------------------------------------------------------------------+
double CalcLotByRisk(double entry, double sl)
  {
   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * (CurrentRiskPct() / 100.0);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0) return 0.0;

   double slDistance = MathAbs(entry - sl);
   if(slDistance <= 0.0) return 0.0;

   double lossPerLot = (slDistance / tickSize) * tickValue;
   if(lossPerLot <= 0.0) return 0.0;

   double lots = riskMoney / lossPerLot;

   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot  = MathMax(InpMinLot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
   double maxLot  = MathMin(InpMaxLot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));

   if(lotStep > 0.0)
      lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   lots = NormalizeDouble(lots, 2);
   return lots;
  }

//+------------------------------------------------------------------+
//| Respect broker minimum stop distance                             |
//+------------------------------------------------------------------+
void EnforceStopDistance(int dir, double entry, double &sl, double &tp)
  {
   long   stopLevelPts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist      = stopLevelPts * _Point;
   if(minDist <= 0.0) return;

   if(dir > 0)
     {
      if(entry - sl < minDist) sl = NormalizeDouble(entry - minDist, _Digits);
      if(tp - entry < minDist) tp = NormalizeDouble(entry + minDist, _Digits);
     }
   else
     {
      if(sl - entry < minDist) sl = NormalizeDouble(entry + minDist, _Digits);
      if(entry - tp < minDist) tp = NormalizeDouble(entry - minDist, _Digits);
     }
  }

//+------------------------------------------------------------------+
//| Position-state registry                                          |
//+------------------------------------------------------------------+
int FindState(ulong ticket)
  {
   for(int i = 0; i < ArraySize(g_states); i++)
      if(g_states[i].ticket == ticket)
         return i;
   return -1;
  }

void RegisterNewPosition(double triggerLevel, int dir)
  {
   CPositionInfo pos;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Symbol() != _Symbol || pos.Magic() != InpMagic) continue;
      if(FindState(pos.Ticket()) >= 0) continue;

      int n = ArraySize(g_states);
      ArrayResize(g_states, n + 1);
      g_states[n].ticket       = pos.Ticket();
      g_states[n].initVolume   = pos.Volume();
      g_states[n].partialDone  = false;
      g_states[n].entryBarTime = g_lastBarTime;
      g_states[n].triggerLevel = triggerLevel;
      g_states[n].dir          = dir;
     }
  }

void PruneStates()
  {
   for(int i = ArraySize(g_states) - 1; i >= 0; i--)
     {
      if(PositionSelectByTicket(g_states[i].ticket)) continue;
      for(int j = i; j < ArraySize(g_states) - 1; j++)
         g_states[j] = g_states[j + 1];
      ArrayResize(g_states, ArraySize(g_states) - 1);
     }
  }

//+------------------------------------------------------------------+
//| Adopt positions already open at attach/restart time              |
//+------------------------------------------------------------------+
void AdoptExistingPositions()
  {
   CPositionInfo pos;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Symbol() != _Symbol || pos.Magic() != InpMagic) continue;
      if(FindState(pos.Ticket()) >= 0) continue;

      int n = ArraySize(g_states);
      ArrayResize(g_states, n + 1);
      g_states[n].ticket       = pos.Ticket();
      g_states[n].initVolume   = pos.Volume();
      g_states[n].partialDone  = true;  // unknown history — don't re-trigger partial
      g_states[n].entryBarTime = (datetime)pos.Time();
      g_states[n].triggerLevel = 0.0;   // unknown — failed-breakout exit disabled for it
      g_states[n].dir          = (pos.PositionType() == POSITION_TYPE_BUY) ? 1 : -1;
     }
  }

//+------------------------------------------------------------------+
//| Count own positions on this symbol                               |
//+------------------------------------------------------------------+
int CountOwnPositions()
  {
   int n = 0;
   CPositionInfo pos;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Symbol() == _Symbol && pos.Magic() == InpMagic) n++;
     }
   return n;
  }

//+------------------------------------------------------------------+
//| Dynamic spread filter                                            |
//+------------------------------------------------------------------+
bool IsSpreadOk(double atrVal)
  {
   long   spreadPts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spreadPts > InpMaxSpreadHardPts) return false;
   double atrPts    = atrVal / _Point;
   double dynCap    = atrPts * InpMaxSpreadAtrFrac;
   return (spreadPts <= dynCap);
  }

//+------------------------------------------------------------------+
//| Session window — resolve to broker server hours                  |
//+------------------------------------------------------------------+
void ResolveSessionHours(int &serverStart, int &serverEnd)
  {
   if(InpHoursInThaiTime)
     {
      // Thai (ICT) = UTC+7. Broker server = UTC + InpBrokerGMTOffset.
      // serverHour = thaiHour - 7 + brokerOffset  (mod 24)
      int shift = InpBrokerGMTOffset - 7;
      serverStart = ((InpStartHour + shift) % 24 + 24) % 24;
      serverEnd   = ((InpEndHour   + shift) % 24 + 24) % 24;
     }
   else
     {
      serverStart = ((InpStartHour % 24) + 24) % 24;
      serverEnd   = ((InpEndHour   % 24) + 24) % 24;
     }
  }

//+------------------------------------------------------------------+
//| True if hour h is inside [start, end); supports midnight wrap     |
//+------------------------------------------------------------------+
bool HourInWindow(int h, int start, int end)
  {
   if(start == end) return true;            // degenerate -> treat as 24h
   if(start <  end) return (h >= start && h < end);
   return (h >= start || h < end);          // window wraps past midnight
  }

//+------------------------------------------------------------------+
//| Log the resolved trading window once at init                     |
//+------------------------------------------------------------------+
void ReportSessionWindow()
  {
   int s, e;
   ResolveSessionHours(s, e);
   int detected = (int)MathRound((double)(TimeTradeServer() - TimeGMT()) / 3600.0);

   PrintFormat("MuaynyGoldEA: session = %02d:00-%02d:00 server time.", s, e);
   if(InpHoursInThaiTime)
     {
      PrintFormat("MuaynyGoldEA: input %02d:00-%02d:00 Thai time, broker GMT offset configured +%d (terminal detects +%d).",
                  InpStartHour, InpEndHour, InpBrokerGMTOffset, detected);
      if(detected != InpBrokerGMTOffset)
         PrintFormat("MuaynyGoldEA: WARNING — InpBrokerGMTOffset=%d but terminal detects +%d. If trades open at the wrong time, set InpBrokerGMTOffset=%d.",
                     InpBrokerGMTOffset, detected, detected);
     }
  }

//+------------------------------------------------------------------+
//| Trading-hours filter                                             |
//+------------------------------------------------------------------+
bool IsTradingTime()
  {
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.day_of_week == 0 || dt.day_of_week == 6) return false; // weekend safety

   int sStart, sEnd;
   ResolveSessionHours(sStart, sEnd);
   if(!HourInWindow(dt.hour, sStart, sEnd)) return false;

   if(InpAvoidFriday && dt.day_of_week == 5)
     {
      int blockFrom = ((sEnd - 2) % 24 + 24) % 24;
      if(HourInWindow(dt.hour, blockFrom, sEnd)) return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Weekend / holiday exit. Closes own positions before the          |
//| Friday (or pre-holiday) session close and returns true while     |
//| new entries should be blocked.                                    |
//+------------------------------------------------------------------+
bool ManageWeekendExit()
  {
   if(!InpUseWeekendExit) return false;

   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);

   datetime from, to;
   if(!SymbolInfoSessionQuote(_Symbol, (ENUM_DAY_OF_WEEK)dt.day_of_week, 0, from, to))
      return false; // no session info today

   datetime dayStart   = now - (now % 86400);
   datetime sessionEnd = dayStart + to;
   long     secsToClose= (long)(sessionEnd - now);

   // Is tomorrow a holiday (no quote session at all)?
   MqlDateTime tdt;
   TimeToStruct(now + 86400, tdt);
   datetime tf, tt;
   bool tomorrowHoliday = !SymbolInfoSessionQuote(_Symbol, (ENUM_DAY_OF_WEEK)tdt.day_of_week, 0, tf, tt);

   bool preWeekend = (dt.day_of_week == FRIDAY || tomorrowHoliday);
   if(!preWeekend) return false;
   if(secsToClose <= 0) return true;

   if(secsToClose <= InpCloseAllMins * 60)
     {
      if(CountOwnPositions() > 0)
        {
         CloseAllOwnPositions("weekend-exit");
         PruneStates();
        }
      return true;
     }

   return (secsToClose <= InpBlockNewMins * 60);
  }

//+------------------------------------------------------------------+
//| Daily-loss circuit breaker                                        |
//+------------------------------------------------------------------+
void ResetDailyBaseline()
  {
   MqlDateTime dt;
   TimeCurrent(dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   g_dayStart       = StructToTime(dt);
   g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dayHalted      = false;
  }

void RollDailyBaseline()
  {
   MqlDateTime dt;
   TimeCurrent(dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime today = StructToTime(dt);
   if(today != g_dayStart)
      ResetDailyBaseline();

   if(!InpUseDailyStop || g_dayStartEquity <= 0.0) return;
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double lossPct = (g_dayStartEquity - equity) / g_dayStartEquity * 100.0;
   if(lossPct >= InpDailyLossPct && !g_dayHalted)
     {
      g_dayHalted = true;
      PrintFormat("MuaynyGoldEA: daily-loss circuit breaker tripped. Loss=%.2f%% >= %.2f%%. No new entries today.",
                  lossPct, InpDailyLossPct);
     }
  }

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
void UiLabel(string key, int x, int y, string text, color clr, int fontSize)
  {
   string name = UI_PREFIX + key;
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString (0, name, OBJPROP_FONT, "Consolas");
  }

void DrawDashboard()
  {
   int x = 12, y = 22, lh = 16;
   string bg = UI_PREFIX + "BG";
   if(ObjectFind(0, bg) < 0)
     {
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C'18,18,26');
      ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg, OBJPROP_COLOR, clrGoldenrod);
     }
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, 6);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, 14);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, 270);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, 212);

   bool algoOn = (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)
                 && (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);
   UiLabel("title", x, y, "MuaynyGoldEA v3.1", clrGold, 10);
   UiLabel("algo", x + 170, y, algoOn ? "ALGO ON" : "ALGO OFF",
           algoOn ? clrLime : clrRed, 8);
   y += lh + 4;

   string trendTxt = (g_uiTrend > 0) ? "UP" : (g_uiTrend < 0 ? "DOWN" : "FLAT");
   color  trendClr = (g_uiTrend > 0) ? clrLime : (g_uiTrend < 0 ? clrTomato : clrSilver);
   UiLabel("trend", x, y, "Trend (H1):  " + trendTxt, trendClr, 9);
   y += lh;

   int sStart, sEnd;
   ResolveSessionHours(sStart, sEnd);
   UiLabel("sess", x, y,
           StringFormat("Session:     %02d:00-%02d:00 srv", sStart, sEnd), clrSilver, 9);
   y += lh;

   string atrTxt = "ATR regime:  ";
   color  atrClr = clrSilver;
   if(!g_uiAtrOk)                                  { atrTxt += "warming up"; }
   else if(g_uiAtrNow < InpAtrLoFactor*g_uiAtrAvg) { atrTxt += "TOO QUIET"; atrClr = clrKhaki; }
   else if(g_uiAtrNow > InpAtrHiFactor*g_uiAtrAvg) { atrTxt += "SHOCK";     atrClr = clrTomato; }
   else                                            { atrTxt += "OK";        atrClr = clrLime; }
   UiLabel("atr", x, y, atrTxt, atrClr, 9);
   y += lh;

   UiLabel("risk", x, y,
           StringFormat("Risk now:    %.2f%%  (base %.2f%%)", CurrentRiskPct(), InpBaseRiskPct),
           clrAqua, 9);
   y += lh;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double ddPct  = (g_equityPeak > 0.0) ? (g_equityPeak-equity)/g_equityPeak*100.0 : 0.0;
   UiLabel("equity", x, y,
           StringFormat("Equity: %.2f  DD %.2f%%", equity, ddPct),
           (ddPct >= InpDDStartPct ? clrKhaki : clrSilver), 9);
   y += lh;

   double dayPL = equity - g_dayStartEquity;
   UiLabel("daypl", x, y,
           StringFormat("Day P/L: %.2f   limit -%.1f%%", dayPL, InpDailyLossPct),
           (dayPL >= 0.0 ? clrLime : clrTomato), 9);
   y += lh;

   int    posN   = 0;
   double posPL  = 0.0, posVol = 0.0;
   int    posDir = 0;
   CPositionInfo pos;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Symbol() != _Symbol || pos.Magic() != InpMagic) continue;
      posN++;
      posPL  += pos.Profit() + pos.Swap();
      posVol += pos.Volume();
      posDir  = (pos.PositionType() == POSITION_TYPE_BUY) ? 1 : -1;
     }
   string posTxt = (posN == 0)
                   ? StringFormat("Position:    flat  (0/%d slots)", MaxSlots())
                   : StringFormat("Position: %s %d/%d  %.2flot PL %.2f",
                                  (posDir > 0 ? "BUY" : "SELL"), posN, MaxSlots(),
                                  posVol, posPL);
   UiLabel("pos", x, y, posTxt,
           (posN == 0 ? clrSilver : (posPL >= 0.0 ? clrLime : clrTomato)), 9);
   y += lh;

   string stateTxt = g_dayHalted ? "DAILY HALT" : g_uiState;
   UiLabel("state", x, y, "Status:      " + stateTxt,
           (g_dayHalted ? clrTomato : clrGold), 9);

   ChartRedraw(0);
  }
//+------------------------------------------------------------------+
