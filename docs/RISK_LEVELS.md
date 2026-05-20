# Risk levels for MuaynyGoldEA

This EA has no single "risk" knob. Risk is the combination of a few inputs.
This page maps an intuitive 0-10 scale onto concrete settings so you can pick
a level deliberately instead of guessing.

> NOT investment advice. Every level can still lose money. A higher level
> does not mean more profit — it means larger swings in both directions.

## The scale

| Level | Profile | `InpBaseRiskPct` | `InpDailyLossPct` | `InpDDStartPct`/`InpDDFullPct` | Slots (`InpBalancePerSlot`/`InpMaxSlotsCap`) |
|-------|---------|------------------|-------------------|--------------------------------|----------------------------------------------|
| 0     | Don't trade | — | — | — | — |
| 1-2   | Conservative | 0.25% | 2.5% | 3 / 10 | 1 slot only |
| 3-4   | **Default** preset | 0.50% | 4.0% | 4 / 12 | 5000 / cap 2 |
| 5-6   | **Moderate** preset | 1.00% | 5.0% | 5 / 15 | 3000 / cap 3 |
| 7-8   | **Aggressive** preset | 1.5-2.0% | 7-8% | 6 / 18 | 1500 / cap 5 |
| 9-10  | Reckless / martingale | — | — | — | — (unsupported) |

Three presets ship:

- `MuaynyGoldEA_XAUUSD_default.set`    → level ~3-4 (conservative)
- `MuaynyGoldEA_XAUUSD_moderate.set`   → level ~5-6 (moderate)
- `MuaynyGoldEA_XAUUSD_aggressive.set` → level ~8   (aggressive)

For levels 1-2, start from the default preset and edit the columns above.

## What each knob does

- **`InpBaseRiskPct`** — % of equity risked on each trade's stop loss. The
  master volume dial. Doubling it doubles your per-trade swing, your monthly
  return *and* your maximum drawdown.
- **`InpDailyLossPct`** — circuit breaker. Once the day's loss reaches this %,
  no new trades until tomorrow. Roughly 4-6x the per-trade risk.
- **`InpDDStartPct` / `InpDDFullPct`** — adaptive scaler band. Between these
  two drawdown levels (from the equity peak) the risk % scales down toward a
  floor. Wider band = ride normal drawdowns at full size; narrower = de-risk
  sooner.
- **`InpBalancePerSlot` / `InpMaxSlotsCap`** — dynamic position slots. Max
  simultaneous positions = `clamp(floor(balance / InpBalancePerSlot), 1, cap)`.
  Extra slots are **pyramid adds**, never a grid (see below).

## Dynamic slots and the news-gap rule

More positions on a single instrument is **not** diversification — every
gold position is the same bet. Extra slots only let the EA *pyramid* a trend:
a 2nd/3rd position opens **only when every existing position is already at
break-even** (`InpPyramidRiskFree=true`), so normal stop-based risk stays at
about one trade's worth no matter how many positions are open.

The one risk that does scale with slot count is a **sudden news gap** (FOMC,
CPI, NFP): price can jump 1-2 ATR in seconds and blow through every
break-even stop at once. The honest worst-case estimate:

```
worst-case single-event loss  ≈  open positions  ×  risk per trade
```

| Slots | At 0.5% risk | At 1.0% risk | At 2.0% risk |
|-------|--------------|--------------|--------------|
| 2     | ~-1%   | ~-2%  | ~-4%  |
| 3     | ~-1.5% | ~-3%  | ~-6%  |
| 5     | ~-2.5% | ~-5%  | ~-10% |
| 10    | ~-5%   | ~-10% | ~-20% |

The daily-loss circuit breaker stops *new* entries; it cannot undo a gap on
positions that are already open. This is why the slot cap is kept at 5 even
for the aggressive preset — beyond that, a single news spike can do more
damage than the strategy earns in a good month.

Note: reaching a high slot count requires several breakouts in the same
direction, each confirmed to break-even before the next. In practice a gold
trend yields maybe 2-4 pyramid adds; 10 is almost never reached, so a cap of
10 mostly just removes a guardrail without adding real upside.

## Why level 9-10 is intentionally left blank

Levels 9-10 are where martingale / grid / averaging-down live — the
architecture of the `Safe_Gold_Pro` EA that was analysed and rejected.
Those systems show a smooth equity curve right up until one sustained trend
wipes the account. There is no preset for that here on purpose. "More risk"
on this EA means a bigger `InpBaseRiskPct`, never a grid.

## The aggressive preset (level 8) — what you signed up for

`MuaynyGoldEA_XAUUSD_aggressive.set` changes these vs the default:

| Input | Default | Aggressive |
|-------|---------|------------|
| `InpBaseRiskPct`    | 0.50% | **2.00%** |
| `InpDailyLossPct`   | 4.0%  | **8.0%**  |
| `InpDDStartPct`     | 4.0%  | **6.0%**  |
| `InpDDFullPct`      | 12.0% | **18.0%** |
| `InpBalancePerSlot` | 5000  | **1500**  |
| `InpMaxSlotsCap`    | 2     | **5**     |

Slots at this preset: $5000 = 3, $7500 = 5, capped at 5.

### What to expect at 2% per trade with up to 5 slots

- Per-trade risk is 1R = 2% of equity. Monthly return and max drawdown both
  scale up roughly 4x vs the 0.5% default. A backtest showing 15% max DD at
  default should be expected to show ~50-60% at this preset.
- Worst-case news-gap loss with 5 open positions ≈ **-10% in one spike.**
- The adaptive scaler still runs: in a drawdown beyond 6% the risk % is cut
  toward its floor (2.0% × 0.35 ≈ 0.70%), and restored on recovery.

### Before running the aggressive preset live

1. Backtest it over 3-5 years (real ticks, realistic spread) and read the
   **max drawdown**. At 2% risk this number will be large. If you cannot
   calmly live through it, drop to the moderate preset.
2. Forward-test on demo for 2-4 weeks at this exact setting.
3. Start live at the broker's minimum lot for the first week.
4. Disable AutoTrading manually around scheduled high-impact news — the
   news-gap math above is the main thing that can hurt this preset.
5. Re-read `docs/RISK_WARNING.md`.
