# Risk warning — please read before using this EA

This software is provided as-is, for educational purposes, with **no warranty of any kind**.

## What this EA is not

- **Not a money-printing machine.** No EA is. The marketing post that inspired this project ("ให้ AI ทำเงินให้แทน" / "let the AI make money for you") is misleading. Algorithmic trading is a discipline of risk management, statistical edge, and operational reliability — not push-button income.
- **Not backtested by us on your broker.** The strategy is reasonable but the only person who can validate it for *your* account is you, on *your* broker, with *your* data.
- **Not regulated financial advice.** The author is not your broker, fiduciary, or financial advisor.

## What can go wrong

- **Slippage and spread.** Live fills are worse than backtest fills, especially on news and at session opens. A backtested profit factor of 1.5 routinely lands at 1.0-1.2 live.
- **Broker differences.** Tick size, tick value, commission, swap, stop level, execution model (instant vs market), and even what "XAUUSD" refers to differ between brokers. Re-tune.
- **News-driven gaps.** Gold gaps over the weekend and on geopolitical headlines. Stop losses become market orders at the gap-open price, which can be far worse than the SL level. The daily-loss circuit breaker mitigates but does not prevent this.
- **VPS / connection failures.** If MT5 is offline when SL hits, the position stays open. Brokers' server-side SL helps but does not cover trailing stops managed by the EA.
- **Bugs.** This code has been written and reviewed but not battle-tested across hundreds of broker setups. Watch the Experts log carefully in the first weeks.
- **Over-leverage.** The default 0.5% risk per trade is conservative. If you raise it and take a string of losses (which will happen), drawdowns compound fast.

## Sane starting points

If you decide to run this live, please:

1. **Start with the smallest account size you can.** Many brokers allow $100-200 accounts with cent or micro lot sizing. Lose this if you must — and you very well might.
2. **Risk no more than 0.5% per trade** for the first three months.
3. **Cap daily loss at 3%** (the EA's default) and **monthly loss at 10%** (manual — disable the EA if hit).
4. **Withdraw profits** every month above a chosen threshold so a string of losses doesn't claw back a year of gains. Equity compounding is what kills retail algo traders; profit compounding is what builds wealth.
5. **Keep a journal.** Daily P&L, trades count, any anomalies. Patterns reveal themselves only when written down.

## When to stop

- Three consecutive months of negative P&L: stop, do not "optimise harder", investigate whether the regime has changed.
- A single day loss exceeding the daily-loss circuit breaker: the breaker did its job. Take the rest of the day off, even if positions are now closed.
- Any unexpected behaviour (unexplained trades, missing stops, wrong lot sizes): disable AutoTrading immediately and read the Experts journal before re-enabling.

## Capital you can afford to lose

Trade only with money you can lose 100% of without affecting your life, debts, family, or mental health. Forex and CFD trading lose money for the majority of retail accounts. Regulated brokers in the EU/UK are required to publish their loss percentages — typical disclosures read **"70-85% of retail investor accounts lose money when trading CFDs"**. Gold CFDs are squarely in this category.

If this paragraph annoys you, you are not ready to deploy this EA with real capital. That is a useful signal, not a put-down.
