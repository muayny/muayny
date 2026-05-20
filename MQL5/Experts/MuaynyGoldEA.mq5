//+------------------------------------------------------------------+
//|                                               MuaynyGoldEA.mq5   |
//|                                                                  |
//|  Donchian-breakout Expert Advisor tuned for XAUUSD (Gold)        |
//|  on a high-volatility regime.                                    |
//|                                                                  |
//|  Why a breakout (not a pullback) on Gold:                        |
//|    Gold tends to compress into ranges around news / session      |
//|    boundaries and then expand violently. Counter-trend           |
//|    pullback entries on RSI/Stoch get repeatedly stopped out      |
//|    during these expansions, while a breakout aligned with the    |
//|    higher-timeframe trend rides the move instead of fading it.   |
//|                                                                  |
//|  Strategy summary:                                               |
//|    Trend filter : H1 EMA(50). Price above = long-only bias,      |
//|                   below = short-only bias.                       |
//|    Entry        : M15 Donchian breakout of the prior N bars      |
//|                   (default 20). Confirmation on bar close.       |
//|    Volatility   : Require ATR(M15,14) >= InpMinAtrPoints to      |
//|                   skip dead markets where breakouts fail.        |
//|    Stops        : ATR-based. SL = entry +/- 1.5 * ATR,           |
//|                   TP = entry +/- 2.5 * ATR.                      |
//|    Sizing       : Risk a fixed % of equity on the SL distance.   |
//|    Trailing     : After 1 * ATR profit, trail SL at 1.2 * ATR.   |
//|    Safety nets  : Daily-loss circuit breaker, wide spread        |
//|                   filter for gold, broker stop-level enforcement,|
//|                   max-positions cap, magic-number isolation.     |
//|                                                                  |
//|  NOT INVESTMENT ADVICE. Past performance does not predict        |
//|  future results. Backtest with realistic spreads, forward-test   |
//|  on demo, and size positions you can afford to lose entirely.    |
//+------------------------------------------------------------------+
#property copyright "Muayny"
#property link      ""
#property version   "1.00"
#property strict
#property description "XAUUSD Donchian-breakout EA: H1 EMA trend filter, ATR stops, risk-based sizing, daily-loss circuit breaker."

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>

//--- inputs --------------------------------------------------------
input group "=== Trend Filter ==="
input ENUM_TIMEFRAMES InpTrendTF        = PERIOD_H1;    // Trend timeframe
input int             InpTrendEMA       = 50;           // Trend EMA period

input group "=== Entry (Donchian Breakout) ==="
input ENUM_TIMEFRAMES InpEntryTF        = PERIOD_M15;   // Entry timeframe
input int             InpDonchianLen    = 20;           // Donchian lookback (bars)
input bool            InpRequireMomentum= true;         // Require breakout candle body in trade direction

input group "=== Volatility Filter ==="
input int             InpAtrPeriod      = 14;           // ATR period
input double          InpMinAtrPoints   = 100;          // Minimum ATR (in symbol points) to allow entries
input double          InpMaxAtrPoints   = 1500;         // Max ATR (skip news shocks)

input group "=== Risk Management ==="
input double          InpRiskPercent    = 0.5;          // Risk per trade (% of equity) — keep small on gold
input double          InpAtrSlMult      = 1.5;          // SL = ATR * this
input double          InpAtrTpMult      = 2.5;          // TP = ATR * this
input double          InpMaxLot         = 2.0;          // Hard cap on lot size
input double          InpMinLot         = 0.01;         // Hard floor on lot size

input group "=== Daily-Loss Circuit Breaker ==="
input bool            InpUseDailyStop   = true;         // Halt trading after daily loss exceeds threshold
input double          InpDailyLossPct   = 3.0;          // Halt new entries if daily loss exceeds % of start-of-day equity

input group "=== Trailing Stop ==="
input bool            InpUseTrailing    = true;         // Enable ATR trailing stop
input double          InpTrailStartAtr  = 1.0;          // Start trailing after price moves N x ATR in favor
input double          InpTrailAtrMult   = 1.2;          // Trailing distance in ATR
input bool            InpBreakEvenFirst = true;         // Move SL to break-even before trailing kicks in
input double          InpBreakEvenAtr   = 0.6;          // Move to BE after this many ATR of profit

input group "=== Session & Spread Filter ==="
input int             InpMaxSpreadPts   = 50;           // Max allowed spread in points (gold typical 20-40)
input int             InpStartHour      = 13;           // Start hour (server time) — London open ~13 broker GMT+3
input int             InpEndHour        = 22;           // End hour (server time) — NY close ~22 broker GMT+3
input bool            InpAvoidFriday    = true;         // Stop new entries 2h before EndHour on Friday
input int             InpMaxPositions   = 1;            // Max simultaneous positions per symbol

input group "=== Identification ==="
input long            InpMagic          = 20260520;     // Magic number
input string          InpComment        = "MuaynyGold"; // Order comment

//--- globals -------------------------------------------------------
int      hTrendEMA     = INVALID_HANDLE;
int      hAtr          = INVALID_HANDLE;
datetime g_lastBarTime = 0;
datetime g_dayStart    = 0;
double   g_dayStartEquity = 0.0;
bool     g_dayHalted   = false;
CTrade   g_trade;

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
int OnInit()
  {
   hTrendEMA = iMA(_Symbol, InpTrendTF, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   hAtr      = iATR(_Symbol, InpEntryTF, InpAtrPeriod);

   if(hTrendEMA == INVALID_HANDLE || hAtr == INVALID_HANDLE)
     {
      Print("MuaynyGoldEA: failed to create indicator handles.");
      return INIT_FAILED;
     }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(20); // gold slippage tolerance
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.LogLevel(LOG_LEVEL_ERRORS);

   if(InpRiskPercent <= 0.0 || InpRiskPercent > 5.0)
     {
      Print("MuaynyGoldEA: InpRiskPercent must be in (0, 5]. Got ", InpRiskPercent);
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpAtrSlMult <= 0.0 || InpAtrTpMult <= 0.0)
      return INIT_PARAMETERS_INCORRECT;
   if(InpDonchianLen < 5)
      return INIT_PARAMETERS_INCORRECT;

   // Soft warning if symbol does not look like gold
   string sym = _Symbol;
   StringToUpper(sym);
   if(StringFind(sym, "XAU") < 0 && StringFind(sym, "GOLD") < 0)
      PrintFormat("MuaynyGoldEA: warning — symbol %s does not look like Gold. Defaults are tuned for XAUUSD.", _Symbol);

   ResetDailyBaseline();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Deinit                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(hTrendEMA != INVALID_HANDLE) IndicatorRelease(hTrendEMA);
   if(hAtr      != INVALID_HANDLE) IndicatorRelease(hAtr);
  }

//+------------------------------------------------------------------+
//| Tick                                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   RollDailyBaseline();

   if(InpUseTrailing || InpBreakEvenFirst)
      ManagePositions();

   datetime barT = (datetime)iTime(_Symbol, InpEntryTF, 0);
   if(barT == 0 || barT == g_lastBarTime)
      return;
   g_lastBarTime = barT;

   if(g_dayHalted)                        return;
   if(!IsTradingTime())                   return;
   if(!IsSpreadOk())                      return;
   if(CountOwnPositions() >= InpMaxPositions) return;

   int trend = GetTrendDirection();
   if(trend == 0) return;

   double atrVal = GetAtr();
   if(atrVal <= 0.0) return;
   double atrPts = atrVal / _Point;
   if(atrPts < InpMinAtrPoints || atrPts > InpMaxAtrPoints) return;

   int signal = GetBreakoutSignal(trend);
   if(signal == 0) return;

   PlaceEntry(signal, atrVal);
  }

//+------------------------------------------------------------------+
//| Trend direction from H1 EMA                                      |
//+------------------------------------------------------------------+
int GetTrendDirection()
  {
   double ema[];
   ArraySetAsSeries(ema, true);
   if(CopyBuffer(hTrendEMA, 0, 0, 2, ema) <= 0) return 0;
   double price = iClose(_Symbol, InpTrendTF, 1); // last closed H1 bar
   if(price > ema[1]) return 1;
   if(price < ema[1]) return -1;
   return 0;
  }

//+------------------------------------------------------------------+
//| Donchian-breakout signal on the just-closed M15 bar              |
//+------------------------------------------------------------------+
int GetBreakoutSignal(int trendDir)
  {
   int    need  = InpDonchianLen + 2;
   double high[], low[], open[], close[];
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);
   ArraySetAsSeries(open,  true);
   ArraySetAsSeries(close, true);

   if(CopyHigh (_Symbol, InpEntryTF, 0, need, high)  <= 0) return 0;
   if(CopyLow  (_Symbol, InpEntryTF, 0, need, low)   <= 0) return 0;
   if(CopyOpen (_Symbol, InpEntryTF, 0, need, open)  <= 0) return 0;
   if(CopyClose(_Symbol, InpEntryTF, 0, need, close) <= 0) return 0;

   // Donchian window: bars [2 .. InpDonchianLen+1], excluding the just-closed bar (index 1)
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
      return 1;
     }
   if(trendDir < 0 && c < lo)
     {
      if(InpRequireMomentum && !bearBody) return 0;
      return -1;
     }
   return 0;
  }

//+------------------------------------------------------------------+
//| ATR value on the last closed entry-TF bar                        |
//+------------------------------------------------------------------+
double GetAtr()
  {
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(hAtr, 0, 0, 2, atr) <= 0) return 0.0;
   return atr[1];
  }

//+------------------------------------------------------------------+
//| Place an entry in the given direction                            |
//+------------------------------------------------------------------+
void PlaceEntry(int dir, double atrVal)
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
      PrintFormat("MuaynyGoldEA: order send failed. retcode=%d, %s",
                  g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| Manage open positions: break-even, ATR trailing                  |
//+------------------------------------------------------------------+
void ManagePositions()
  {
   double atrVal = GetAtr();
   if(atrVal <= 0.0) return;

   CPositionInfo pos;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Symbol() != _Symbol) continue;
      if(pos.Magic()  != InpMagic) continue;

      double openPrice = pos.PriceOpen();
      double curPrice  = pos.PriceCurrent();
      double curSL     = pos.StopLoss();
      double curTP     = pos.TakeProfit();
      ENUM_POSITION_TYPE type = pos.PositionType();

      if(type == POSITION_TYPE_BUY)
        {
         double profitDist = curPrice - openPrice;

         if(InpBreakEvenFirst && profitDist >= atrVal * InpBreakEvenAtr
            && (curSL < openPrice - _Point || curSL == 0.0))
           {
            double beSL = NormalizeDouble(openPrice + _Point, _Digits);
            if(beSL > curSL + _Point)
              {
               g_trade.PositionModify(pos.Ticket(), beSL, curTP);
               curSL = beSL;
              }
           }

         if(InpUseTrailing && profitDist >= atrVal * InpTrailStartAtr)
           {
            double newSL = NormalizeDouble(curPrice - atrVal * InpTrailAtrMult, _Digits);
            if(newSL > curSL + _Point)
               g_trade.PositionModify(pos.Ticket(), newSL, curTP);
           }
        }
      else if(type == POSITION_TYPE_SELL)
        {
         double profitDist = openPrice - curPrice;

         if(InpBreakEvenFirst && profitDist >= atrVal * InpBreakEvenAtr
            && (curSL > openPrice + _Point || curSL == 0.0))
           {
            double beSL = NormalizeDouble(openPrice - _Point, _Digits);
            if(curSL == 0.0 || beSL < curSL - _Point)
              {
               g_trade.PositionModify(pos.Ticket(), beSL, curTP);
               curSL = beSL;
              }
           }

         if(InpUseTrailing && profitDist >= atrVal * InpTrailStartAtr)
           {
            double newSL = NormalizeDouble(curPrice + atrVal * InpTrailAtrMult, _Digits);
            if(curSL == 0.0 || newSL < curSL - _Point)
               g_trade.PositionModify(pos.Ticket(), newSL, curTP);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Risk-based lot sizing                                            |
//+------------------------------------------------------------------+
double CalcLotByRisk(double entry, double sl)
  {
   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * (InpRiskPercent / 100.0);
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
   long stopLevelPts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist    = stopLevelPts * _Point;
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
//| Spread filter                                                    |
//+------------------------------------------------------------------+
bool IsSpreadOk()
  {
   long spreadPts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return spreadPts <= InpMaxSpreadPts;
  }

//+------------------------------------------------------------------+
//| Trading-hours filter                                             |
//+------------------------------------------------------------------+
bool IsTradingTime()
  {
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.day_of_week == 0 || dt.day_of_week == 6) return false; // weekend safety
   if(dt.hour < InpStartHour || dt.hour >= InpEndHour) return false;
   if(InpAvoidFriday && dt.day_of_week == 5 && dt.hour >= InpEndHour - 2) return false;
   return true;
  }

//+------------------------------------------------------------------+
//| Day-boundary baseline for daily-loss circuit breaker             |
//+------------------------------------------------------------------+
void ResetDailyBaseline()
  {
   MqlDateTime dt;
   TimeCurrent(dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   g_dayStart        = StructToTime(dt);
   g_dayStartEquity  = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dayHalted       = false;
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
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double lossPct = (g_dayStartEquity - equity) / g_dayStartEquity * 100.0;
   if(lossPct >= InpDailyLossPct && !g_dayHalted)
     {
      g_dayHalted = true;
      PrintFormat("MuaynyGoldEA: daily-loss circuit breaker tripped. Loss=%.2f%% >= %.2f%%. No new entries today.",
                  lossPct, InpDailyLossPct);
     }
  }
//+------------------------------------------------------------------+
