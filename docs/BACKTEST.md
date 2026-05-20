# Backtesting MuaynyGoldEA honestly

A backtest that looks good but uses bad data or unrealistic costs will lose you real money. This doc is about not fooling yourself.

## In MT5 Strategy Tester

1. **View → Strategy Tester** (or Ctrl+R).
2. Expert: `MuaynyGoldEA`.
3. Symbol: `XAUUSD` (or whatever your broker calls gold — `XAUUSD.s`, `GOLD`, `GOLD.cash`).
4. Period: M15.
5. Date range: at least 3 years. 5+ is better. Skip the first 6 months — gold's character changes over time, you want the recent regime to be in-sample.
6. Modelling: **Every tick based on real ticks**. Anything coarser will overstate fills on breakouts.
7. Deposit: realistic starting balance (e.g. 1000 USD or whatever you'll actually trade).
8. Leverage: match your live account.
9. Inputs: click **Load** and pick `MuaynyGoldEA_XAUUSD_default.set`.
10. Run.

## Make spread realistic

The Tester defaults to "Current" spread which uses the spread shown right now (often 0-5 points). For gold this lies to you.

- In the Tester, change **Spread** from `Current` to a fixed value matching your broker's typical XAUUSD spread (e.g. `30` for 30 points).
- Re-run. Compare results to the `Current` run. If the equity curve crumbles, the strategy is over-fit to zero-cost fills.

## Add commission

If your broker charges commission per lot (common on ECN-style accounts):

- Strategy Tester has no commission field directly. Either:
  - Approximate by increasing the spread (e.g. +20 points to cover $7 round-trip commission per lot on XAUUSD ≈ another 0.7 USD per 0.01 lot).
  - Or run the test "as-is" and mentally subtract `commission_per_lot * total_lots` from the net profit. The total trades and lots are in the report.

## What to look at in the report

In order of importance:

1. **Max drawdown (absolute and % of initial deposit).** If max DD > 30% on the backtest, expect 1.5-2x that live. Reduce `InpBaseRiskPct`, and consider lowering `InpDDStartPct` so the adaptive scaler cuts size sooner.
2. **Number of trades.** < 50 over 3 years = statistically meaningless. > 5000 = probably noise.
3. **Profit factor.** Above 1.3 with 200+ trades is decent. Above 2.0 without overfit is suspicious — check the inputs you tuned.
4. **Recovery factor** and **Sharpe**. Both included in the report.
5. **Equity curve shape.** Steady upward is healthy; jagged with one giant winner carrying it is fragile. Look at the curve, not just the final number.

## Optimisation — handle with care

The Tester can optimise inputs. **This is the single fastest way to fool yourself.**

- Optimise on, say, the first 70% of the date range (in-sample).
- Test the winning parameters on the last 30% (out-of-sample, untouched).
- If the out-of-sample equity curve looks nothing like the in-sample one, the in-sample result was curve-fit. Discard.

Reasonable parameters to optimise:
- `InpDonchianLen` over [10, 15, 20, 25, 30]
- `InpAtrSlMult` over [1.0, 1.5, 2.0, 2.5]
- `InpAtrTpMult` over [2.5, 3.0, 3.5, 4.0]
- `InpAtrLoFactor` over [0.5, 0.7, 0.9, 1.1]
- `InpPartialAtr` over [1.0, 1.2, 1.5, 1.8]
- `InpMaxBarsInLoss` over [6, 8, 10, 14, 0] (0 = disabled)

Avoid optimising the risk-management inputs — `InpBaseRiskPct`, `InpDDStartPct`, `InpDDFullPct`, `InpRiskFloorFrac`, `InpDailyLossPct`. Those exist to cap losses, not to chase an edge; optimising them just curve-fits the EA into taking more risk on the in-sample period.

## Walk-forward (more rigorous)

For a stronger test:

1. Split the date range into 6 windows of equal length.
2. Optimise on windows 1-3, test on 4. Record performance.
3. Optimise on 2-4, test on 5. Record.
4. Optimise on 3-5, test on 6. Record.
5. The "real" expected performance is the average of the test-window results, not the optimisation-window results.

MT5 does not do walk-forward natively — third-party tools (StrategyQuant, EA Studio) do, or script it manually.

## Forward-test before live

Even a great backtest must be confirmed on demo for 2-4 weeks before you fund a live account. Reasons:

- Real-time tick stream is different from historical tick data. Slippage on entries that looked instant in backtest appears live.
- Your broker's gold contract specs may differ from what the Tester assumed.
- Your timezone / sleep schedule reveals operational issues (what happens when MT5 disconnects at 3am? You'll find out on demo cheaply).

The demo account should mirror the live account: same broker, same account type, same leverage, same VPS.
