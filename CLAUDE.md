# Claude ETF: standing rules

This repo runs a small, risk-averse, self-managed "ETF". The goal is to grow with the market, give up big upside, and never get wiped out, including if the AI bubble pops. It is paper trading only until the user explicitly connects a broker.

## This repo is public

Never commit secrets, API keys, account numbers, real-money balances, or anyone's personal info. Broker keys go in the cloud environment's secrets, never in files.

## Portfolio rules

`etf/etf.py` enforces the rules marked ✓.

1. ✓ **The 70% defensive base is fixed and is the hedge.** It is 30% T-bills (SGOV), 20% intermediate Treasuries (VGIT), 10% short TIPS (VTIP) and 10% gold (GLDM). Never shrink it.
2. ✓ **Stocks are 30% in total.** That is VT plus satellites (single stocks), with VT filling whatever the satellites don't use.
3. ✓ **Satellites are bought once and never topped up.** Each is at most 2% when bought (1% by default). At purchase, no theme may exceed 5% and all satellites together may not exceed 15%. A name above 3% is trimmed to 2%, and a theme above 7.5% is trimmed to 5%. Trims go to VT.
4. **All AI bets share one 5% cap.** Anything whose story depends on AI spending (photonics, chips, AI software, datacenter power) uses theme `ai`. VT already holds about 21% in AI-linked megacaps, so don't add AI exposure anywhere else.
5. **Never sell because a price fell.** Remove a satellite from `etf/strategy.json` only when news breaks its thesis: fraud, a restatement, bankruptcy risk, an announced acquisition, or the business changing.
6. ✓ **No junk.** A new satellite must pass `python etf/etf.py screen`. A stock must be:
   - listed on NYSE or Nasdaq main markets
   - $2B or more in market cap
   - $5 or more in price
   - traded at least $20M a day
   - listed for at least 2 years
   - not based in China, Hong Kong or Macau

   A fund needs at least $1B in assets. Even small positions in crypto, SPAC or meme stocks are out.
7. **No leverage, margin, options, shorts, or leveraged or inverse ETFs.** No day trading and no timing "highs".
8. ✓ **Only `python etf/etf.py rebalance` moves money.** Never hand-edit `etf/state.json` or `etf/trades.csv`.
9. **At most 2 new satellites per week.** Every judgment call gets one line in `etf/journal.md`.
10. **When unsure, do nothing.**

## Costs and broker (Robinhood)

- **Fund fees are a judgment call, not a rule.** Pick the cheapest fund that gets the exposure you want. Paying 0.15–0.50% or more is fine when it's the only way to get that exposure; write why in `etf/journal.md`. `screen` shows each fund's fee but doesn't block on it. Leveraged, inverse and crypto funds stay out. Today's core funds (VT, SGOV, VGIT, VTIP, GLDM) cost about 0.06% a year in total, and fund prices already include fees, so backtests are net of them.
- **Stocks and ETFs only, and no ADRs.** Stock and ETF trades are commission-free on Robinhood. ADRs carry pass-through custody fees.
- ✓ **Trades under $1 are skipped,** because Robinhood's fractional orders have a $1 minimum. Selling a whole position worth under $1 is allowed. Below roughly $500 in total, picks hit the $1 floor.
- **Cash account only, never margin.** Before any real order, confirm through the MCP that the agentic account is a cash account and that buying power isn't above its cash. If it is, stop and tell the user. ✓ `rebalance` already refuses to leave cash negative.
- **Never write anything from the user's Robinhood accounts into this repo:** no balances, holdings in dollars, or account details. Read access covers all their accounts.
- **Real money goes only through Robinhood's Agentic Trading MCP,** using its separate agentic account. It must be connected as a claude.ai connector, never with tokens in files. Before the first real order, add `etf/state.json` and `etf/trades.csv` to `.gitignore` (or make the repo private), so real balances never become public.

## Where things are

- **Hourly routine and backtesting:** `.claude/skills/etf-manager/SKILL.md`
- **Strategy:** `etf/strategy.json` is the only file you edit by hand.
- **Stress test:** replayed through the 2000–02 crash (photonics names −90%, Nasdaq −72%), these rules lost about 8%.
