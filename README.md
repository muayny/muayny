# MuaynyGoldEA

MetaTrader 5 Expert Advisor for **XAUUSD (Gold)** in a high-volatility regime.

Strategy: **Donchian breakout aligned with a higher-timeframe trend filter, ATR-based stops, fixed-percent risk sizing, and a daily-loss circuit breaker.**

> NOT INVESTMENT ADVICE. Trading carries a substantial risk of loss. Past
> performance — including backtests — does not predict future results.
> Forward-test on a demo account before risking real money.

---

## Repository layout

```
MQL5/
  Experts/MuaynyGoldEA.mq5            # the EA source
  Presets/MuaynyGoldEA_XAUUSD_default.set
docs/
  STRATEGY.md                         # what the EA does and why
  VPS_SETUP.md                        # how to run it 24/5 on a VPS
  BACKTEST.md                         # how to backtest it honestly
  RISK_WARNING.md                     # please read
```

---

## Strategy at a glance

| Component        | Setting                                             |
|------------------|-----------------------------------------------------|
| Trend filter     | H1 EMA(50): trade only with the trend              |
| Entry            | M15 Donchian-20 breakout, close beyond level        |
| Volatility gate  | ATR(M15,14) between InpMinAtrPoints and InpMaxAtrPoints |
| Stop loss        | 1.5 x ATR(M15)                                      |
| Take profit      | 2.5 x ATR(M15) (R:R ~1:1.67)                        |
| Trailing         | Break-even after 0.6 ATR, then trail 1.2 ATR        |
| Risk per trade   | 0.5% of equity (lot size auto-derived)             |
| Daily-loss stop  | Halt new entries after -3% equity on the day       |
| Session          | 13:00-22:00 server time (London + NY)              |
| Spread filter    | Max 50 points                                       |

See `docs/STRATEGY.md` for the reasoning.

---

## Quick install

1. Open MT5 → **File → Open Data Folder**.
2. Drop `MQL5/Experts/MuaynyGoldEA.mq5` into the `MQL5/Experts` folder of that data folder.
3. Drop `MQL5/Presets/MuaynyGoldEA_XAUUSD_default.set` into `MQL5/Presets`.
4. In MT5 → **Navigator → Expert Advisors → right-click MuaynyGoldEA → Compile**. You should see `0 errors, 0 warnings`.
5. Open an `XAUUSD` chart on the M15 timeframe.
6. Drag the EA onto the chart. In the inputs dialog click **Load** and pick `MuaynyGoldEA_XAUUSD_default.set`.
7. Confirm **AutoTrading** is enabled (button in the toolbar is green).
8. Allow algorithmic trading: **Tools → Options → Expert Advisors → "Allow algorithmic trading"**.

The EA prints a warning to the Experts log if you attach it to a non-gold symbol.

---

## Before you go live

1. **Backtest** with realistic spread/commission on at least 3-5 years of M15 data. See `docs/BACKTEST.md`.
2. **Forward-test** on a demo account for at least 2-4 weeks with the same settings.
3. **Verify your broker's server time** (Tools → Options → Server shows broker time at top-right of MT5). Adjust `InpStartHour` and `InpEndHour` so the trading window covers the London + NY sessions for your broker. Most retail brokers run GMT+2 / GMT+3 and the defaults work.
4. **Test the daily-loss circuit breaker** by setting `InpDailyLossPct` to a tiny value (e.g. 0.05) on demo and confirming new entries are halted after a loss.
5. **Start small** with the minimum lot the broker allows, regardless of what the risk calculator suggests, for at least the first week live.

---

## VPS

The point of a VPS is to keep MT5 running 24/5 without your laptop being open and without internet drops costing you fills. See `docs/VPS_SETUP.md` for the step-by-step.

---

## Files in this repo are source only

This repository contains `.mq5` source. MT5 will compile it locally into `.ex5`.
Do not download pre-compiled `.ex5` binaries from third parties — they are an obvious vector for stealing credentials or running unauthorised trades on your account.
