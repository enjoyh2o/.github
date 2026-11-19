---
name: etf-manager
description: Run the "Claude ETF", a small risk-averse paper portfolio in etf/. Use for the scheduled check-in, for adding or removing satellites (such as photonics names), and for backtesting changes to etf/strategy.json.
---

# Claude ETF manager

The rules are in `CLAUDE.md` at the repo root. Re-read it at the start of every check-in, since it may have changed.

You run the portfolio and make every trade yourself. The code in `etf/etf.py` gives you numbers, suggestions and checks, and that's all. Most check-ins end with no trades.

## Check-in

1. Pull the latest files with `git pull --ff-only`. Run `pip install -q -r etf/requirements.txt` if needed, then `python etf/etf.py status`.
2. **News.** For each ticker flagged "check news", search the news (WebSearch) over the last few days. On the first check-in of each trading day, also skim the news for every satellite. Compare what you find with each satellite's `thesis` in `etf/strategy.json`. Before acting on news, confirm it in a primary source: an SEC filing or a company press release.
3. **Decide.** `status` ends with what the written rules suggest. Treat that as a suggestion: check that the reasons and dollar amounts make sense against the holdings table. Then decide, and usually the answer is to do nothing.
   - **Thesis broken:** remove the ticker from `satellites` and sell it.
   - **New idea:** pick a theme for it (anything AI-dependent is `ai`) and run `python etf/etf.py screen TICKER`. If it passes, add it with `weight` of 1% (2% at most) and a one-line `thesis`. Optionally run `python etf/etf.py backtest` to see the effect on the worst drop and worst year.
4. **Trade (paper).** Record each trade you decided on, sells first, for example:
   - `python etf/etf.py record sell LITE all --reason "Marvell acquisition announced"`
   - `python etf/etf.py record buy VT 100 --reason "proceeds from LITE"`

   Add `--check` to test a trade without writing it. Use "annual rebalance" as the reason for the yearly rebalance, so `status` knows it's done.
5. Write one line in `etf/journal.md` for every judgment call: date, what you did, and why.
6. If any file changed, commit and push. If nothing changed, don't commit.
7. Reply in 1–3 lines: the NAV, any trades, and anything flagged.

## Backtesting

`python etf/etf.py backtest [--start YYYY-MM-DD]` compares three versions:

- the strategy
- the same portfolio with VT in place of the satellites
- 100% VT

It applies the written rules mechanically, as a rough guide to risk. Before SGOV and GLDM existed, BIL and GLD stand in for them.

Caveats:

- **Hindsight bias.** The satellites are today's picks, so their past looks better than it would have in real time. Judge a change by worst drop and worst year against the no-satellites version, not by total return.
- **Not modelled:** taxes, commissions, slippage and bid/ask spreads.

## Files

| File | Who writes it |
|---|---|
| `etf/strategy.json` | You: targets, satellites, rules and screen thresholds |
| `etf/journal.md` | You: one line per judgment call |
| `etf/state.json` | `etf.py record`: the paper holdings |
| `etf/trades.csv` | `etf.py record`: every trade and its reason |

Network access needed: `query1.finance.yahoo.com`, `query2.finance.yahoo.com`, `fc.yahoo.com`.
