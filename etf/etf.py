#!/usr/bin/env python3
"""Claude ETF tools. Claude runs the portfolio; these are its calculators.
Nothing here decides anything or places orders. Every trade is Claude's call, placed through Robinhood.

    python etf/etf.py status                         holdings vs targets, flags, and what the written rules suggest
    python etf/etf.py check buy VT 25                sanity-check a trade before placing it (amount in dollars, or "all")
    python etf/etf.py screen TICKER...               junk filter for a stock or fund idea
    python etf/etf.py backtest [--start YYYY-MM-DD]  how strategy.json would have done historically

status and check read etf/holdings.json, which Claude writes at each check-in from Robinhood's positions:
    {"cash": 123.45, "positions": {"VT": 250.00, "SGOV": 300.00}}      (dollar values)
That file is gitignored. Never commit it: this repo is public.

The suggestion rules live in plan(); status and backtest both use it.
Standing rules: CLAUDE.md. Routine: .claude/skills/etf-manager/SKILL.md.
"""
import argparse
import json
import time
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd
import yfinance as yf

HERE = Path(__file__).parent
STRATEGY, HOLDINGS = HERE / "strategy.json", HERE / "holdings.json"
PROXIES = {"SGOV": "BIL", "GLDM": "GLD"}  # longer-history stand-ins, used by the backtest only


def load_strategy():
    s = json.loads(STRATEGY.read_text())
    r, sats = s["rules"], s["satellites"]
    themes = {}
    for t, v in sats.items():
        assert 0 < v["weight"] <= r["max_satellite"], f"{t}: weight {v['weight']} is above max_satellite"
        themes[v["theme"]] = themes.get(v["theme"], 0) + v["weight"]
    for th, tw in themes.items():
        assert tw <= r["max_theme"] + 1e-9, f"theme {th} adds up to {tw:.1%}, above max_theme {r['max_theme']:.0%}"
    sat_total = sum(v["weight"] for v in sats.values())
    assert sat_total <= r["max_satellite_total"] + 1e-9, "satellites add up to more than max_satellite_total"
    targets = {**s["defensive"], s["broad_stock"]: s["stock_budget"] - sat_total,
               **{t: v["weight"] for t, v in sats.items()}}
    assert abs(sum(targets.values()) - 1) < 1e-6, f"targets add up to {sum(targets.values()):.4f}, not 1"
    return s, targets


def plan(w, targets, s, new_year):
    """What the written rules would do, as (new weights, reasons). A suggestion for Claude, never an order.

    Satellites are bought once and never topped up, so a loser can only shrink. Price drops never
    suggest a sale; satellites leave only when removed from strategy.json or trimmed after big gains.
    """
    r, broad, sats = s["rules"], s["broad_stock"], s["satellites"]
    w = {t: w.get(t, 0.0) for t in set(w) | set(targets)}
    new, reasons = dict(w), []
    for t in w:
        if t not in targets and w[t] > 0:
            new[broad] += new[t]
            new[t] = 0.0
            reasons.append(f"sell {t}: not in strategy")
    for t, v in sats.items():
        if w[t] == 0:
            new[broad] -= v["weight"]
            new[t] = v["weight"]
            reasons.append(f"buy {t}: new satellite at {v['weight']:.1%}")
        elif w[t] > r["trim_above"]:
            new[broad] += w[t] - r["trim_to"]
            new[t] = r["trim_to"]
            reasons.append(f"trim {t}: {w[t]:.1%} is above {r['trim_above']:.0%}, back to {r['trim_to']:.0%}")
    for theme in sorted({v["theme"] for v in sats.values()}):
        names = [t for t, v in sats.items() if v["theme"] == theme]
        tw = sum(new[t] for t in names)
        if tw > r["theme_trim_above"]:
            k = r["max_theme"] / tw
            for t in names:
                new[broad] += new[t] * (1 - k)
                new[t] *= k
            reasons.append(f"trim theme {theme}: {tw:.1%} is above {r['theme_trim_above']:.1%}, back to {r['max_theme']:.0%}")
    # Core: defensive base plus VT, where VT fills whatever part of the stock budget satellites don't use.
    core = {t: targets[t] for t in s["defensive"]}
    core[broad] = s["stock_budget"] - sum(new[t] for t in sats)
    drift = {t: new[t] - core[t] for t in core}
    worst = max(drift, key=lambda t: abs(drift[t]))
    if new_year or abs(drift[worst]) > r["band"]:
        new.update(core)
        reasons.append("annual rebalance" if new_year else f"rebalance: {worst} is {drift[worst]:+.1%} off target")
    return new, reasons


def screen(ticker, rules):
    """Junk filter. Returns (failures, notes): failures mean "don't buy"; notes (like a fund's fee) are for judgment."""
    def complete(i):
        need = ["totalAssets"] if i.get("quoteType") == "ETF" else ["marketCap", "exchange", "averageVolume"]
        return i.get("quoteType") and all(i.get(k) is not None for k in need)
    for attempt in range(3):  # Yahoo sometimes rate-limits this endpoint and sends partial data; prices are unaffected
        i = yf.Ticker(ticker).info
        if complete(i) or attempt == 2:
            break
        time.sleep(20)
    if not complete(i):
        raise SystemExit(f"Yahoo returned incomplete data for {ticker} (often temporary); try again later.")
    if i.get("quoteType") == "ETF":
        fee, assets = i.get("netExpenseRatio"), i.get("totalAssets") or 0
        failures = [] if assets >= rules["min_fund_assets"] else [f"fund size ${assets / 1e9:.1f}B"]
        return failures, [f"fee {fee}% a year"]
    price = i.get("currentPrice") or i.get("regularMarketPrice") or 0
    first = i.get("firstTradeDateMilliseconds")
    years = (time.time() - first / 1000) / 31_557_600 if first else 0
    checks = [
        (i.get("exchange") in rules["exchanges"], f"exchange {i.get('exchange')} not in {rules['exchanges']}"),
        ((i.get("marketCap") or 0) >= rules["min_market_cap"], f"market cap ${(i.get('marketCap') or 0) / 1e9:.1f}B"),
        (price >= rules["min_price"], f"price ${price}"),
        (price * (i.get("averageVolume") or 0) >= rules["min_dollar_volume"],
         f"trades ${price * (i.get('averageVolume') or 0) / 1e6:.0f}M a day"),
        (years >= rules["min_years_listed"], f"listed {years:.1f} years"),
        (i.get("country") not in rules["excluded_countries"], f"based in {i.get('country')}"),
        (i.get("quoteType") == "EQUITY", f"type {i.get('quoteType')} is not a stock or ETF"),
    ]
    return [msg for ok, msg in checks if not ok], []


# ---------------------------------------------------------------- holdings (from Robinhood)

def latest_prices(tickers):
    df = yf.download(sorted(tickers), period="5d", progress=False, auto_adjust=True)["Close"]
    df = df.to_frame(sorted(tickers)[0]) if isinstance(df, pd.Series) else df.ffill()
    missing = [t for t in tickers if pd.isna(df[t].iloc[-1])]
    if missing:
        raise SystemExit(f"No price from Yahoo for {missing}; try again later.")
    return df.iloc[-1], df.iloc[-1] / df.iloc[-2] - 1


def portfolio():
    s, targets = load_strategy()
    if not HOLDINGS.exists():
        raise SystemExit("No etf/holdings.json. Write it from Robinhood's positions first: "
                         '{"cash": dollars, "positions": {"TICKER": dollars}}')
    h = json.loads(HOLDINGS.read_text())
    pos = {t.upper(): float(v) for t, v in h["positions"].items() if float(v) > 0}
    cash = float(h["cash"]) + 0.0
    tickers = set(pos) | set(targets)
    _, day = latest_prices(tickers)
    nav = sum(pos.values()) + cash
    if nav <= 0:
        raise SystemExit("Holdings add up to $0; nothing to analyse yet.")
    return s, targets, pos, cash, day, nav, {t: pos.get(t, 0.0) / nav for t in tickers}


def cmd_status(args):
    s, targets, pos, cash, day, nav, w = portfolio()
    r = s["rules"]
    print(f"Total ${nav:,.2f}  cash ${cash:,.2f} ({cash / nav:.1%})\n")
    print(f"{'ticker':7}{'target':>8}{'now':>8}{'1 day':>8}  flag")
    for t in sorted(w, key=lambda t: (-targets.get(t, 0), t)):
        flag = []
        if abs(day[t]) >= r["news_move"]:
            flag.append("big move: check news (do not sell on price)")
        if t in s["satellites"] and w[t] >= r["trim_above"] - 0.005:
            flag.append("close to trim level")
        if t not in targets:
            flag.append("not in strategy")
        print(f"{t:7}{targets.get(t, 0):8.1%}{w[t]:8.1%}{day[t]:+8.1%}  {'; '.join(flag)}")
    themes = {}
    for t, v in s["satellites"].items():
        themes[v["theme"]] = themes.get(v["theme"], 0) + w.get(t, 0)
    print("\nThemes: " + ", ".join(f"{th} {tw:.1%}" for th, tw in themes.items()))
    new_year = s.get("last_annual_rebalance", 0) < datetime.now(timezone.utc).year
    w_cash = {**w, "_cash": cash / nav}
    new_w, reasons = plan({t: v for t, v in w_cash.items() if t != "_cash"}, targets, s, new_year)
    sug = {t: (new_w.get(t, 0) - w.get(t, 0)) * nav for t in set(new_w) | set(w)}
    sug = {t: d for t, d in sug.items() if abs(d) >= r["min_trade"]}
    if not reasons or not sug:
        print("\nThe written rules suggest: nothing.")
        return
    print("\nThe written rules suggest (your call; check the numbers before acting):")
    for x in reasons:
        print(f"  why: {x}")
    for t, d in sorted(sug.items(), key=lambda x: x[1]):
        print(f"  {'buy ' if d > 0 else 'sell'} {t:6} ${abs(d):,.2f}")
    if new_year:
        print('  (after doing the annual rebalance, set "last_annual_rebalance" in strategy.json to this year)')


def cmd_check(args):
    """Sanity-check one trade against the limits. It can only say no; it never trades."""
    s, targets, pos, cash, day, nav, w = portfolio()
    t, side = args.ticker.upper(), args.side
    held = pos.get(t, 0.0)
    dollars = held if args.amount == "all" else float(args.amount)
    core = set(s["defensive"]) | {s["broad_stock"]}
    problems = []
    if dollars <= 0:
        problems.append("amount must be positive")
    if side == "buy" and dollars > cash + 0.005:
        problems.append(f"only ${cash:,.2f} cash; sell first (never use margin)")
    if side == "sell" and dollars > held + 0.005:
        problems.append(f"only ${held:,.2f} of {t} held")
    if dollars < s["rules"]["min_trade"] and not (side == "sell" and abs(dollars - held) < 0.01):
        problems.append(f"below Robinhood's ${s['rules']['min_trade']:.0f} minimum order")
    if dollars > 0.05 * nav and not args.rebalance:
        problems.append(f"${dollars:,.2f} is {dollars / nav:.1%} of the portfolio; above 5%, re-check (add --rebalance if this is the yearly rebalance or the first build)")
    if side == "buy" and t not in core:
        if t not in s["satellites"]:
            problems.append(f"{t} isn't in strategy.json; add it with a theme and thesis first")
        elif (held + dollars) / nav > s["rules"]["max_satellite"] + 1e-9:
            problems.append(f"{t} would be {(held + dollars) / nav:.1%} of the portfolio; the cap is {s['rules']['max_satellite']:.0%}")
    if problems:
        raise SystemExit(f"Don't place it ({side} {t} ${dollars:,.2f}): " + "; ".join(problems))
    after = held + (dollars if side == "buy" else -dollars)
    print(f"OK: {side} {t} ${dollars:,.2f} fits the limits ({after / nav:.1%} of the portfolio after).")


def cmd_screen(args):
    s, _ = load_strategy()
    for t in args.tickers:
        failed, notes = screen(t, s["screen"])
        print(f"{t:6} {'PASS' if not failed else 'FAIL: ' + '; '.join(failed)}{'  (' + '; '.join(notes) + ')' if notes else ''}")


# ---------------------------------------------------------------- backtest

def simulate(rets, targets, s):
    hold, year, navs, trims = pd.Series(targets, dtype=float), rets.index[0].year, [], 0
    for dt, r in rets.iterrows():
        hold = hold * (1 + r[hold.index])
        nav = hold.sum()
        new_w, reasons = plan((hold / nav).to_dict(), targets, s, dt.year != year)
        if reasons:
            hold = pd.Series(new_w).reindex(hold.index).fillna(0.0) * nav
            trims += sum(x.startswith("trim") for x in reasons)
        year = dt.year
        navs.append(nav)
    return pd.Series(navs, index=rets.index), trims


def stats(v):
    yrs = (v.index[-1] - v.index[0]).days / 365.25
    yearly = pd.concat([v.iloc[:1], v.resample("YE").last()]).pct_change().dropna()
    yearly.index = yearly.index.year
    full = yearly[yearly.index < v.index[-1].year] if v.index[-1].month < 12 else yearly
    return {"per year": (v.iloc[-1] / v.iloc[0]) ** (1 / yrs) - 1,
            "volatility": v.pct_change().std() * np.sqrt(252),
            "worst drop": (v / v.cummax() - 1).min(),
            "worst year": full.min(),
            "$10k became": 10000 * v.iloc[-1] / v.iloc[0]}, yearly


def cmd_backtest(args):
    s, targets = load_strategy()
    broad = s["broad_stock"]
    tickers = sorted(set(targets) | {PROXIES[t] for t in targets if t in PROXIES})
    px = yf.download(tickers, start="2000-01-01", progress=False, auto_adjust=True)["Close"]
    rets = px.pct_change(fill_method=None)
    for t, proxy in PROXIES.items():
        if t in rets:
            rets[t] = rets[t].fillna(rets[proxy])
    rets = rets[list(targets)]
    start = max(rets[t].first_valid_index() for t in targets)
    if args.start:
        start = max(start, pd.Timestamp(args.start))
    rets = rets[start:].fillna(0.0)
    print(f"Backtest {rets.index[0].date()} to {rets.index[-1].date()}  "
          f"(starts when every holding has data; SGOV/GLDM use BIL/GLD before they existed)\n")

    no_sats = {**s, "satellites": {}}
    all_vt = {**s, "satellites": {}, "defensive": {}, "stock_budget": 1.0}
    runs = {"strategy": simulate(rets, targets, s),
            "no satellites (VT instead)": simulate(rets, {**s["defensive"], broad: s["stock_budget"]}, no_sats),
            "100% VT": simulate(rets, {broad: 1.0}, all_vt)}
    table, years = {}, {}
    for name, (v, trims) in runs.items():
        table[name], years[name] = stats(v)
        table[name]["trims"] = trims
    t = pd.DataFrame(table).T
    for c in ["per year", "volatility", "worst drop", "worst year"]:
        t[c] = t[c].map("{:.1%}".format)
    t["$10k became"] = t["$10k became"].map("${:,.0f}".format)
    print(t.to_string(), "\n")
    print("Calendar years (last one is year to date):")
    print((pd.DataFrame(years) * 100).round(1).to_string(), "\n")
    print("Caution: satellites are today's picks, so their past looks better than it would have in real time.\n"
          "Judge a change by worst drop and worst year against 'no satellites', not by total return.")


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status")
    chk = sub.add_parser("check")
    chk.add_argument("side", choices=["buy", "sell"])
    chk.add_argument("ticker")
    chk.add_argument("amount", help='dollars, or "all" for the whole position')
    chk.add_argument("--rebalance", action="store_true", help="allow a trade above 5%% (yearly rebalance or first build)")
    sub.add_parser("screen").add_argument("tickers", nargs="+")
    sub.add_parser("backtest").add_argument("--start")
    a = p.parse_args()
    {"status": cmd_status, "check": cmd_check, "screen": cmd_screen, "backtest": cmd_backtest}[a.cmd](a)
