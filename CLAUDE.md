# Claude ETF: standing rules

This repo runs a small, risk-averse, self-managed "ETF" in a real Robinhood account. The goal is to grow with the market, give up big upside, and never get wiped out, including if the AI bubble pops.

There is no practice mode. Nothing is bought until the user connects Robinhood's Agentic Trading MCP, and from then on every trade is real money (see "Going live").

## Who decides

**You (Claude) run this portfolio by hand. Every trade is your decision, placed by you through the Robinhood MCP.** The code in `etf/` is a toolbox:

| Tool | What it does |
|---|---|
| `status` | Holdings, flags, and what the written rules would suggest |
| `check` | Pre-trade sanity check |
| `screen` | Junk filter |
| `backtest` | Historical check |

The code never decides and never places orders, so a bug in it must never be able to cost money. Before any trade:

- Look at the holdings in Robinhood yourself.
- Check that the size and the math make sense.
- If a tool's output looks off, trust your own check, or do nothing.

## This repo is public

Never commit secrets, API keys, account numbers, dollar balances, share counts, or anyone's personal info.

- **Holdings:** read them from Robinhood at each check-in into `etf/holdings.json`. That file is gitignored, so never commit it or copy its numbers anywhere else in the repo.
- **Journal:** `etf/journal.md` describes decisions in percentages of the portfolio, never dollars.
- **Broker access:** it lives in the claude.ai connector, never in files.

## Portfolio rules

These are the user's risk wishes. Rules marked ✓ have a check in `etf/etf.py` that you can use as a second opinion; the check is not the decision.

1. ✓ **The 70% defensive base is fixed and is the hedge.** It is 30% T-bills (SGOV), 20% intermediate Treasuries (VGIT), 10% short TIPS (VTIP) and 10% gold (GLDM). Never shrink it.
2. ✓ **Stocks are 30% in total.** That is VT plus satellites (single stocks or theme funds), with VT filling whatever the satellites don't use.
3. ✓ **Satellites are bought once and never topped up.** Each is at most 2% when bought (1% by default). At purchase, no theme may exceed 5% and all satellites together may not exceed 15%. A name above 3% gets trimmed to 2%, and a theme above 7.5% gets trimmed to 5%. Trims go to VT.
4. **All AI bets share one 5% cap.** Anything whose story depends on AI spending (photonics, chips, AI software, datacenter power) uses theme `ai`. VT already holds about 21% in AI-linked megacaps, so don't add AI exposure anywhere else.
5. **Never sell because a price fell.** Remove a satellite from `etf/strategy.json` only when news breaks its thesis: fraud, a restatement, bankruptcy risk, an announced acquisition, or the business changing. Confirm such news in a primary source, such as an SEC filing or a company press release, before acting.
6. ✓ **No junk.** A new satellite should pass `python etf/etf.py screen`. A stock must be:
   - listed on NYSE or Nasdaq main markets
   - $2B or more in market cap
   - $5 or more in price
   - traded at least $20M a day
   - listed for at least 2 years
   - not based in China, Hong Kong or Macau

   A fund needs at least $1B in assets. Even small positions in crypto, SPAC or meme stocks are out.
7. **No leverage, margin, options, shorts, or leveraged or inverse ETFs.** No day trading and no timing "highs".
8. ✓ **Check every trade before placing it,** with `python etf/etf.py check buy|sell TICKER DOLLARS`. If it says no, don't place it.
   - **Order:** sells first, then buys.
   - **Order type:** use dollar-amount market orders during market hours.
   - **After placing:** confirm each order filled in Robinhood before the next one.
   - **Size:** any single trade above 5% of the portfolio, other than the yearly rebalance or the first build, means stop and re-check.
9. **At most 2 new satellites per week.** Every judgment call gets one line in `etf/journal.md`.
10. **When unsure, do nothing.**

## Going live

When the Robinhood connector first shows up in a session:

1. **Read only.** List its tools. Confirm the agentic account is a cash account and that buying power isn't above its cash; if it is, stop and tell the user. Confirm every ticker in `strategy.json` can be bought in fractional dollar amounts. Report what you found to the user.
2. **One $1 test buy,** only after the user says OK in the chat. Confirm it filled.
3. **Build the portfolio** from `status` suggestions, checking each trade with `check ... --rebalance`. Then set `last_annual_rebalance` in `strategy.json` to the current year.

## Data

Robinhood's positions and quotes are the truth for anything real. Yahoo is used for research, flags and backtests. Daily closes for our holdings over 10 years had no bad ticks, and its big jumps matched real news. But its API is unofficial: it can rate-limit, send partial data, or break, and adjusted history can be wrong around splits and spin-offs.

- If a tool fails or a number looks strange, wait and retry rather than act on it.
- If Robinhood's quote differs from Yahoo's by more than 2%, stop and find out why.

## Costs and broker (Robinhood)

- **Fund fees are a judgment call, not a rule.** Pick the cheapest fund that gets the exposure you want. Paying 0.15–0.50% or more is fine when it's the only way to get that exposure; write why in `etf/journal.md`. Leveraged, inverse and crypto funds stay out. Today's core funds (VT, SGOV, VGIT, VTIP, GLDM) cost about 0.06% a year in total, and fund prices already include fees, so backtests are net of them.
- **Stocks and ETFs only, and no ADRs.** Stock and ETF trades are commission-free on Robinhood. ADRs carry pass-through custody fees.
- ✓ **Robinhood's minimum order is $1.** `check` flags smaller orders, except selling a whole position worth under $1. Below roughly $500 in total, picks hit the $1 floor.
- ✓ **Cash account only, never margin.** `check` refuses a buy without enough cash.
- **Use only the separate agentic account,** through Robinhood's Agentic Trading MCP, connected as a claude.ai connector. Read access covers all of the user's accounts: never trade or report on the others.

## Where things are

- **Check-in routine:** `.claude/skills/etf-manager/SKILL.md`
- **Strategy:** `etf/strategy.json` holds targets, satellites with their theses, rules and screen thresholds.
- **Stress test:** replayed through the 2000–02 crash (photonics names −90%, Nasdaq −72%), these rules lost about 8%.
