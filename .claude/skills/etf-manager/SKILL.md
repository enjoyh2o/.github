---
name: etf-manager
description: Run the "Claude ETF", a small risk-averse paper portfolio in etf/. Use for the hourly check-in, for adding or removing satellite stocks (such as photonics names), and for backtesting changes to etf/strategy.json.
---

# Claude ETF manager

The rules are in `CLAUDE.md` at the repo root, which is always loaded. Follow them; this file is only the routine.

The code in `etf/etf.py` makes every trade. Your job is judgment about which satellites belong, and most of the time the right answer is to do nothing.

## Hourly check-in

1. Run `pip install -q -r etf/requirements.txt` if needed, then `python etf/etf.py status`.
2. For each ticker flagged "check news", search the news (WebSearch) for that company over the last few days. On the first check-in of each trading day, also skim the news for every satellite. Compare what you find with each satellite's `thesis` in `etf/strategy.json`.
3. Decide. Usually nothing changes.
   - **Thesis broken:** remove the ticker from `satellites`.
   - **New idea:** pick a theme for it (anything AI-dependent is `ai`) and run `python etf/etf.py screen TICKER`. If it passes, add it with `weight` of 1% (2% at most) and a one-line `thesis`. Then run `python etf/etf.py backtest` and check that the worst drop and worst year barely move.
   - **Changed the weight of a name you already hold:** run `python etf/etf.py rebalance --reset` once.
   - Write one line in `etf/journal.md` for every judgment call: date, what you did, and why.
4. If `status` listed planned actions or you changed `strategy.json`, run `python etf/etf.py rebalance`.
5. If any file changed, commit and push to the working branch. If nothing changed, don't commit.
6. Reply in 1–3 lines: the NAV, any trades, and anything flagged.

## Backtesting

`python etf/etf.py backtest [--start YYYY-MM-DD]` compares three versions:

- the strategy
- the same portfolio with VT in place of the satellites
- 100% VT

The backtest starts on the first date every holding has data. Before SGOV and GLDM existed, BIL and GLD stand in for them.

Caveats:

- **Hindsight bias.** The satellites are today's picks, so their past looks better than it would have in real time. Judge a change by worst drop and worst year against the no-satellites version, not by total return.
- **Not modelled:** taxes, commissions, slippage and bid/ask spreads.

## Files

| File | Who writes it |
|---|---|
| `etf/strategy.json` | You: targets, satellites, rules and screen thresholds |
| `etf/journal.md` | You: one line per judgment call |
| `etf/state.json` | `etf.py`: the paper holdings |
| `etf/trades.csv` | `etf.py`: every trade and its reason |

Network access needed: `query1.finance.yahoo.com`, `query2.finance.yahoo.com`, `fc.yahoo.com`.
