---
name: etf-manager
description: Run the "Claude ETF", a small risk-averse paper portfolio in etf/. Use for the hourly check-in, for adding or removing satellite stocks (such as photonics names), and for backtesting changes to etf/strategy.json.
---

# Claude ETF

A managed portfolio that behaves like a cautious ETF: a fixed defensive base, a broad stock fund, and many small themed positions. The code in `etf/etf.py` makes every trade. Your job is judgment about which satellites belong, and most of the time the right answer is to do nothing.

## The strategy

- **70% defensive base, which is the hedge:** 30% T-bills (SGOV), 20% intermediate Treasuries (VGIT), 10% short-term TIPS (VTIP), 10% gold (GLDM).
- **30% stocks:** satellites (individual themed stocks) come out of this 30%, and VT fills the rest.
- **Satellites:** each one is at most 2% when bought, and all of them together are at most 15%. If one grows past 3%, it is trimmed back to 2% and the profit goes into VT.
- **Rebalance:** everything goes back to target once a year, or sooner if any holding drifts more than 5 points from its target.

All numbers live in `etf/strategy.json`. The rules live in `plan()` in `etf/etf.py`, which both the backtest and the live portfolio use.

## Hard rules

1. **Never sell because a price fell.** A drop alone, even a big one, is not a reason.
2. **Sell a satellite only when its thesis is broken by news.** Examples: fraud or an accounting restatement, bankruptcy or going-concern risk, an announced acquisition of the company, or the business no longer doing what its thesis says.
3. **Don't trade on price patterns.** No "local highs", momentum or day trading. Profit-taking happens only through the 3% trim rule.
4. **No leverage, margin, options, shorts, or leveraged or inverse ETFs.**
5. **Add at most 2 new satellites per week.** Each needs a one-line thesis and a theme.
6. **Only `python etf/etf.py rebalance` moves money.** Never hand-edit `state.json` or `trades.csv`.
7. **Paper only.** Nothing here places real orders. Real money needs the user to set it up explicitly.

## Hourly check-in

1. Run `pip install -q -r etf/requirements.txt` if needed, then `python etf/etf.py status`.
2. For each ticker flagged "check news", search the news (WebSearch) for that company over the last few days. On the first check-in of each trading day, also skim the news for every satellite. Compare what you find with each satellite's `thesis` in `strategy.json`.
3. Decide. Usually nothing changes.
   - **Thesis broken:** remove the ticker from `satellites` in `strategy.json`.
   - **New idea:** add it to `satellites` with `weight` of 2% or less, plus a `theme` and a `thesis`. Run `python etf/etf.py backtest` first and check that the worst drop and worst year barely move.
   - Write one line in `etf/journal.md` for every judgment call: date, what you did, and why.
4. If `status` listed planned actions or you changed `strategy.json`, run `python etf/etf.py rebalance`.
5. If any file changed, commit and push. If nothing changed, don't commit.
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
| `etf/strategy.json` | You: targets, satellites and rules |
| `etf/journal.md` | You: one line per judgment call |
| `etf/state.json` | `etf.py`: the paper holdings |
| `etf/trades.csv` | `etf.py`: every trade and its reason |

Network access needed: `query1.finance.yahoo.com`, `query2.finance.yahoo.com`, `fc.yahoo.com`.
