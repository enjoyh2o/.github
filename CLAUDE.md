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
6. ✓ **No junk.** A new satellite must pass `python etf/etf.py screen`:
   - listed on NYSE or Nasdaq main markets
   - market cap of $2B or more
   - price of $5 or more
   - at least $20M traded a day
   - listed for at least 2 years
   - not based in China, Hong Kong or Macau
   - a stock, not a fund

   Even small positions in crypto, SPAC or meme stocks are out.
7. **No leverage, margin, options, shorts, or leveraged or inverse ETFs.** No day trading and no timing "highs".
8. ✓ **Only `python etf/etf.py rebalance` moves money.** Never hand-edit `etf/state.json` or `etf/trades.csv`.
9. **At most 2 new satellites per week.** Every judgment call gets one line in `etf/journal.md`.
10. **When unsure, do nothing.**

## Where things are

- **Hourly routine and backtesting:** `.claude/skills/etf-manager/SKILL.md`
- **Strategy:** `etf/strategy.json` is the only file you edit by hand.
- **Stress test:** replayed through the 2000–02 crash (photonics names −90%, Nasdaq −72%), these rules lost about 8%.
