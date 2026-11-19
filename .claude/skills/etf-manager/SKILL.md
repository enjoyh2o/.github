---
name: etf-manager
description: Run the "Claude ETF", a small risk-averse portfolio in a Robinhood agentic account, with rules and tools in etf/. Use for the scheduled check-in, for adding or removing satellites (such as photonics names), and for backtesting changes to etf/strategy.json.
---

# Claude ETF manager

The rules are in `CLAUDE.md` at the repo root. Re-read it at the start of every check-in, since it may have changed.

You run the portfolio and place every trade yourself through the Robinhood MCP. The code in `etf/etf.py` gives you numbers, suggestions and checks, and that's all. Most check-ins end with no trades.

## Check-in

1. Pull the latest files with `git pull --ff-only`. Run `pip install -q -r etf/requirements.txt` if needed.
2. **Holdings.** Read the agentic account's cash and positions from the Robinhood MCP, and write them to `etf/holdings.json` as dollar values:

   ```json
   {"cash": 12.34, "positions": {"VT": 250.0}}
   ```

   That file is gitignored, so never commit it. If the Robinhood MCP isn't connected in this session, skip to step 3, do the news review only, and say so in your reply. If the account has never been funded or built, follow "Going live" in `CLAUDE.md`.
3. **Status and news.** Run `python etf/etf.py status`. For each ticker flagged "check news", search the news (WebSearch) over the last few days. On the first check-in of each trading day, also skim the news for every satellite in `strategy.json`. Compare what you find with each satellite's `thesis`. Before acting on news, confirm it in a primary source: an SEC filing or a company press release.
4. **Decide.** `status` ends with what the written rules suggest. Treat that as a suggestion: check that the reasons and dollar amounts make sense against the holdings. Then decide, and usually the answer is to do nothing.
   - **Thesis broken:** remove the ticker from `satellites`, then sell it.
   - **New idea:** pick a theme for it (anything AI-dependent is `ai`) and run `python etf/etf.py screen TICKER`. If it passes, add it with `weight` of 1% (2% at most) and a one-line `thesis`. Optionally run `python etf/etf.py backtest` to see the effect on the worst drop and worst year.
5. **Trade.** For each trade you decided on, sells first:
   - Run `python etf/etf.py check buy|sell TICKER DOLLARS|all`. If it says no, don't place the trade.
   - Place a dollar-amount market order through the Robinhood MCP, during market hours only.
   - Confirm it filled before placing the next one.
   - After the yearly rebalance, set `last_annual_rebalance` in `strategy.json` to the current year.
6. Write one line in `etf/journal.md` for every judgment call: date, what you did, and why. Use percentages of the portfolio, never dollars.
7. If `strategy.json` or `journal.md` changed, commit and push. Never commit `holdings.json`.
8. Reply in 1–3 lines: the total, any trades, and anything flagged.

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

| File | Who writes it | Committed? |
|---|---|---|
| `etf/strategy.json` | You: targets, satellites, rules, screen thresholds, `last_annual_rebalance` | Yes |
| `etf/journal.md` | You: one line per judgment call, in percentages | Yes |
| `etf/holdings.json` | You, from Robinhood, at each check-in | **No** (gitignored) |

Network access needed: `query1.finance.yahoo.com`, `query2.finance.yahoo.com` and `fc.yahoo.com`, plus the Robinhood MCP connector.
