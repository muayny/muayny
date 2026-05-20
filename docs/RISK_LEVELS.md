# Risk levels for MuaynyGoldEA

This EA has no single "risk" knob. Risk is the combination of a few inputs.
This page maps an intuitive 0-10 scale onto concrete settings so you can pick
a level deliberately instead of guessing.

> NOT investment advice. Every level can still lose money. A higher level
> does not mean more profit — it means larger swings in both directions.

## The scale

| Level | Profile | `InpBaseRiskPct` | `InpDailyLossPct` | `InpDDStartPct` / `InpDDFullPct` | `InpMaxPositions` |
|-------|---------|------------------|-------------------|----------------------------------|-------------------|
| 0     | Don't trade | — | — | — | — |
| 1-2   | Conservative | 0.25% | 2.5% | 3 / 10 | 1 |
| 3-4   | **Default** (shipped preset) | 0.50% | 4.0% | 4 / 12 | 1 |
| **5-6** | **Moderate** (this is you) | **1.00%** | **5.0%** | **5 / 15** | 1 |
| 7-8   | Aggressive | 1.50-2.00% | 7-8% | 6 / 18 | 1 |
| 9-10  | Reckless / martingale | — | — | — | — |

The two shipped presets cover levels 3-4 and 5-6:

- `MuaynyGoldEA_XAUUSD_default.set`  → level ~3-4 (conservative)
- `MuaynyGoldEA_XAUUSD_moderate.set` → level ~5-6 (moderate)

For levels 1-2 or 7-8, start from the nearest preset and edit the four
columns above by hand.

## What each knob actually does

- **`InpBaseRiskPct`** — the % of equity put at risk on each trade's stop
  loss. This is the master volume dial. Doubling it doubles your per-trade
  P&L swing, your monthly return *and* your maximum drawdown.
- **`InpDailyLossPct`** — the circuit breaker. Once the day's loss reaches
  this %, no new trades open until tomorrow. Set it to roughly 4-6× your
  per-trade risk so it triggers after a genuine bad streak, not after one
  or two normal losers.
- **`InpDDStartPct` / `InpDDFullPct`** — the adaptive scaler band. Between
  these two drawdown levels (measured from the equity peak) the risk % is
  scaled down linearly toward its floor. A wider band lets you ride normal
  drawdowns at full size; a narrower band de-risks sooner.
- **`InpMaxPositions`** — keep this at **1** at every level below 9. Going
  to 2+ stacks correlated exposure on a single instrument and is a much
  bigger jump in real risk than it looks. Multiple simultaneous gold
  positions is not "moderate", it is "aggressive-plus".

## Why level 9-10 is intentionally left blank

Levels 9-10 are where martingale / grid / averaging-down live — the
architecture of the `Safe_Gold_Pro` EA that was analysed and rejected.
Those systems show a smooth equity curve right up until one sustained
trend wipes the account. There is no preset for that here on purpose.
"More risk" on this EA means a bigger `InpBaseRiskPct`, never a grid.

## Level 5/10 — the moderate preset

Load `MuaynyGoldEA_XAUUSD_moderate.set`. It changes exactly four values
from the default:

| Input | Default (3-4/10) | Moderate (5/10) |
|-------|------------------|-----------------|
| `InpBaseRiskPct`  | 0.50% | **1.00%** |
| `InpDailyLossPct` | 4.0%  | **5.0%**  |
| `InpDDStartPct`   | 4.0%  | **5.0%**  |
| `InpDDFullPct`    | 12.0% | **15.0%** |

The strategy itself — entries, stops, exits, filters — is unchanged.
Only the size of each bet and the loss limits move.

### What to expect at 1% per trade

Per-trade risk is 1R = 1% of equity. Using the same illustrative win-rate
table from earlier (avg win +0.9R, avg loss -0.6R), the numbers from the
0.5% default simply double:

| Win rate | Expectancy / trade | ≈ Monthly (illustrative) | ≈ Max drawdown vs default |
|----------|--------------------|--------------------------|---------------------------|
| 55% | +0.22R | +3.4% | ~2× |
| 50% | +0.15R | +2.4% | ~2× |
| 45% | +0.03R | ~0% (break-even) | ~2× |
| 40% | 0R | negative | ~2× |

These are **illustrative, not predictions.** The real win rate is unknown
until you backtest. The point of the table: at 5/10 the upside roughly
doubles — and so does the drawdown. A backtest that showed, say, a 15%
max drawdown at the default 0.5% should be expected to show ~30% at 1%.

### Before running the moderate preset live

1. Backtest the moderate preset over 3-5 years (real ticks, realistic
   spread) and read the **max drawdown**. If you are not comfortable
   actually living through that number, drop back toward 3-4/10.
2. Forward-test on demo for 2-4 weeks at the moderate setting.
3. Start live at the broker's minimum lot for the first week regardless
   of what the risk calculator suggests.
4. Re-read `docs/RISK_WARNING.md`.
