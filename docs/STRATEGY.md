# Strategy: Trend-aligned Donchian breakout on Gold

## Why XAUUSD-specific

Gold has a few quirks that retail forex EAs handle badly:

- **Wide spreads.** Retail XAUUSD spreads typically run 20-40 points and can blow out to 100+ during news or session rollovers. EAs tuned for EURUSD (5-point spread) over-trade gold and bleed on spread.
- **Bursty volatility.** Gold spends hours in tight ranges and then expands by 200-1000 points in minutes around FOMC, NFP, CPI, geopolitical headlines, or US session opens. Pullback / mean-reversion strategies get stopped repeatedly during these expansions.
- **Strong trend persistence within expansions.** Once gold breaks a recent range with momentum, it tends to keep going for the rest of the session before reverting.

This EA is built to **sit out the chop** and **participate in the expansions**.

## The three signals

### 1. Trend filter — H1 EMA(50)

We only take longs when price on the last closed H1 bar is above EMA(50), and only shorts when it is below. This single line filters out roughly half of the entries — specifically the half that fades the prevailing bias.

### 2. Entry — M15 Donchian-20 breakout

On each newly closed M15 bar we check whether its close is above the highest high of the previous 20 M15 bars (long) or below the lowest low (short). The current bar is excluded from the window so we are comparing the close to a fixed reference, not to itself.

If `InpRequireMomentum=true` (default), the breakout bar must also close in the direction of the trade — i.e. a bullish body for a long, a bearish body for a short. This filters out exhaustion wicks.

### 3. Volatility gate — ATR(M15, 14)

We require ATR to be between `InpMinAtrPoints` and `InpMaxAtrPoints` (default 100-1500 points).

- **Below the floor:** the market is too quiet, breakouts are unreliable and likely to revert.
- **Above the ceiling:** the move has already happened, we are likely to enter on a news spike and get stopped.

This is the single most important parameter to tune for your broker's quote precision.

## Risk model

### Position sizing
Lots are derived from a fixed equity-risk %, not a fixed lot. The math:

```
loss_per_lot = (|entry - SL| / tick_size) * tick_value
lots         = equity * risk% / loss_per_lot
```

Then clamped to `[max(InpMinLot, broker_min), min(InpMaxLot, broker_max)]` and rounded down to the broker's `lot_step`.

The defaults risk 0.5% per trade. **Do not raise this above 1% on gold** until you have at least a year of forward-tested results.

### Stops
- SL = entry ± 1.5 × ATR
- TP = entry ± 2.5 × ATR
- R:R ≈ 1 : 1.67

Both are normalised to the symbol's digits and pushed outside the broker's `SYMBOL_TRADE_STOPS_LEVEL`.

### Trailing
After the position is up by 0.6 × ATR, SL is moved to break-even (open price + 1 point). After 1.0 × ATR of profit, the SL trails at 1.2 × ATR behind current price.

### Daily-loss circuit breaker
If unrealised + realised P&L for the day exceeds `InpDailyLossPct` (default 3%) of the day's starting equity, no new entries open until the next day. Existing positions continue to manage their stops. This is your protection against revenge-trading and clustered losers during news days.

## Session and spread filters

- **Trading window:** 13:00-22:00 server time. For brokers on GMT+2/GMT+3 this covers London open (10:00 GMT) through NY close (21:00 GMT). Adjust if your broker uses a different server clock.
- **Friday cutoff:** 2 hours before `InpEndHour` no new entries on Fridays. This avoids holding through weekend gap risk.
- **Spread cap:** entries are blocked when current spread > `InpMaxSpreadPts`. Keep this conservative (50 default).

## What this strategy is NOT

- Not a scalper. It expects 0-3 trades per day on average.
- Not a martingale or grid. There is at most one open position per symbol; losers are not averaged into.
- Not news-aware. There is no calendar integration. The volatility gate is a crude proxy. If you want to avoid known news, use MT5's News tab or third-party calendars and disable AutoTrading manually around high-impact releases.
- Not a substitute for understanding your broker. Different brokers price gold differently (some use XAUUSD, some XAUUSD.s, some GOLD.cash). Tick size, tick value, commission, and swap vary widely. Always re-tune on the exact symbol your broker offers.
