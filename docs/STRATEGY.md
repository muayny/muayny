# Strategy: adaptive, self-correcting Donchian breakout on Gold

## Why XAUUSD-specific

Gold has a few quirks that retail forex EAs handle badly:

- **Wide spreads.** Retail XAUUSD spreads typically run 20-40 points and can blow out to 100+ during news or session rollovers. EAs tuned for EURUSD (5-point spread) over-trade gold and bleed on spread.
- **Bursty volatility.** Gold spends hours in tight ranges and then expands by 200-1000 points in minutes around FOMC, NFP, CPI, geopolitical headlines, or US session opens. Pullback / mean-reversion strategies get stopped repeatedly during these expansions.
- **Strong trend persistence within expansions.** Once gold breaks a recent range with momentum, it tends to keep going for the rest of the session before reverting.

This EA is built to **sit out the chop**, **participate in the expansions**, **cut wrong trades before they get dragged into a deep loss**, and **lock in profit on the trades that work**.

## Everything is dynamic

There are deliberately no hand-tuned, broker-specific point thresholds (except one absolute spread hard cap as a safety net). Each moving part adapts:

| Knob | Adapts to |
|------|-----------|
| Lot size | Live equity — grows as the account grows, shrinks as it shrinks |
| Risk %   | Drawdown from the equity peak — cut while losing, restored while recovering |
| Volatility gate | ATR relative to its own long-run average |
| Spread cap | A fraction of current ATR |
| SL / TP / trailing | ATR — wider stops in volatile regimes, tighter in calm ones |

## Entry — three aligned signals

### 1. Trend filter — H1 EMA(50)
Longs only when the last closed H1 bar closed above EMA(50); shorts only when below. Filters out the half of signals that fade the prevailing bias.

### 2. Entry — M15 Donchian-20 breakout
On each newly closed M15 bar, check whether its close cleared the highest high of the previous 20 bars (long) or the lowest low (short). The current bar is excluded from the window, so the close is compared to a fixed reference. With `InpRequireMomentum=true` the breakout bar must also close with a body in the trade direction, filtering exhaustion wicks.

### 3. Adaptive volatility gate
Instead of fixed point thresholds, the EA computes the average of ATR(M15,14) over the last `InpAtrAvgPeriod` bars (default 100) and only trades when current ATR sits inside the band:

```
InpAtrLoFactor * avgATR  <=  ATR  <=  InpAtrHiFactor * avgATR
```

- **Below the floor (0.70×):** market too quiet, breakouts unreliable.
- **Above the ceiling (3.00×):** the move likely already happened — entering here is buying a news spike.

Because the gate is relative, it works on any broker's quote precision without re-tuning.

## Dynamic position sizing

Lots are derived from an equity-risk %, never a fixed lot:

```
loss_per_lot   = (|entry - SL| / tick_size) * tick_value
risk_money     = equity * effective_risk%
lots           = risk_money / loss_per_lot
```

Then clamped to `[max(InpMinLot, broker_min), min(InpMaxLot, broker_max)]` and rounded down to `lot_step`.

Because `equity` is the live account equity, **a larger balance produces a larger lot automatically** — the EA compounds.

### Adaptive drawdown scaling
`effective_risk%` is **not** constant. The EA tracks the all-time equity peak and reduces risk while the account is in drawdown:

- Drawdown ≤ `InpDDStartPct` (4%): full `InpBaseRiskPct` (0.5%).
- Drawdown ≥ `InpDDFullPct` (12%): risk floored at `InpBaseRiskPct * InpRiskFloorFrac` (0.5% × 0.35 ≈ 0.175%).
- In between: linear interpolation.

The effect compounds in your favour: in a drawdown, both equity is lower **and** the risk % is lower, so position size shrinks fast — and grows back automatically as the account recovers. This is the opposite of a martingale.

## Stops and profit locking (เก็บกำไร)

### Stops
- SL = entry ± `InpAtrSlMult` × ATR (default 1.5)
- TP = entry ± `InpAtrTpMult` × ATR (default 3.0)

Both are normalised and pushed outside the broker's `SYMBOL_TRADE_STOPS_LEVEL`.

### Partial take-profit
When a trade is up by `InpPartialAtr` × ATR (default 1.2), the EA closes `InpPartialPct`% (default 50%) of the original volume — banking realised profit — and immediately moves the remaining position's SL to break-even. After this, the trade can no longer become a net loser (barring slippage/gaps).

If the position is too small to split without leaving a sub-minimum remainder, the partial is skipped cleanly and the whole position rides the trailing stop instead.

### Break-even and trailing
- After `InpBreakEvenAtr` × ATR (0.7) of profit, SL moves to break-even.
- After `InpTrailStartAtr` × ATR (1.0) of profit, SL trails `InpTrailAtrMult` × ATR (1.2) behind price.

Stops only ever move in the favourable direction — they never loosen.

## Self-correction — cutting wrong trades early (ไม่ปล่อยให้โดนลาก)

The hard ATR stop loss is the last line of defence, not the first. Three faster checks run on every closed entry-TF bar and cut a trade the moment its premise breaks — so a wrong trade is closed at a fraction of the full SL loss instead of being "dragged":

1. **Failed-breakout exit.** Each trade records the exact Donchian level it broke out from. If a later bar closes back through that level, the breakout has failed — close immediately.
2. **Trend-flip exit.** If the H1 EMA trend flips against an open position, the trade's core premise (trend alignment) is gone — close immediately. The next valid breakout will be in the new, correct direction and is taken normally.
3. **Time-in-loss exit.** A position still underwater after `InpMaxBarsInLoss` entry-TF bars (default 10 ≈ 2.5h) is a dead trade going nowhere — close it and free the slot.

When any of these fires, the EA does not re-enter on the same bar; it waits for a fresh, valid signal on a later bar. That fresh signal — now aligned with the corrected trend — is how the EA "enters the correct order."

## Safety nets

- **Daily-loss circuit breaker.** If the day's loss exceeds `InpDailyLossPct` (4%) of the day's starting equity, no new entries open until the next day. Open positions are still managed. Protects against revenge-trading and clustered news-day losers.
- **Dynamic spread filter.** Entries are blocked when spread exceeds `min(InpMaxSpreadAtrFrac × ATR, InpMaxSpreadHardPts)`.
- **Session window** 13:00-22:00 server time (London + NY for GMT+2/+3 brokers) with a Friday cutoff 2h before close to avoid weekend gap risk.
- **Max one position per symbol.** No grid, no averaging into losers.
- **Position adoption.** On attach/restart the EA adopts any pre-existing positions on its magic number so it keeps managing them (trend-flip and time-in-loss still apply; partial/failed-breakout are disabled for adopted trades since their history is unknown).

## What this strategy is NOT

- Not a scalper. It expects roughly 0-3 trades per day.
- Not a martingale or grid. At most one open position; losers are never averaged into; risk is *reduced*, not increased, after losses.
- Not news-aware. There is no economic-calendar integration — the volatility gate is only a crude proxy. Disable AutoTrading manually around high-impact releases (FOMC, NFP, CPI).
- Not a substitute for understanding your broker. Brokers price gold differently (`XAUUSD`, `XAUUSD.s`, `GOLD.cash`, …) with different tick size, tick value, commission, and swap. Always re-test on the exact symbol your broker offers.
