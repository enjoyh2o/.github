#!/usr/bin/env python3
"""Claude ETF: a small, risk-averse, paper-traded portfolio.

    python etf/etf.py init 10000        start a paper portfolio with $10,000
    python etf/etf.py status            holdings vs targets, flags, planned actions (no trades)
    python etf/etf.py rebalance         carry out the planned actions (paper trades)
    python etf/etf.py backtest          test strategy.json on history

The rules live in plan(); the backtest and the live portfolio both use it.
See .claude/skills/etf-manager/SKILL.md for how this is run.
"""
import argparse
import csv
import json
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd
import yfinance as yf

HERE = Path(__file__).parent
STRATEGY, STATE, TRADES = HERE / "strategy.json", HERE / "state.json", HERE / "trades.csv"
PROXIES = {"SGOV": "BIL", "GLDM": "GLD"}  # longer-history stand-ins, used by the backtest only


def load_strategy():
    s = json.loads(STRATEGY.read_text())
    r = s["rules"]
    sats = {t: v["weight"] for t, v in s["satellites"].items()}
    for t, w in sats.items():
        assert 0 < w <= r["max_satellite"], f"{t}: weight {w} is above max_satellite {r['max_satellite']}"
    assert sum(sats.values()) <= r["max_satellite_total"] + 1e-9, "satellites add up to more than max_satellite_total"
    targets = {**s["defensive"], s["broad_stock"]: s["stock_budget"] - sum(sats.values()), **sats}
    assert abs(sum(targets.values()) - 1) < 1e-6, f"targets add up to {sum(targets.values()):.4f}, not 1"
    return s, targets, sats


def plan(w, targets, sats, rules, broad, new_year):
    """The whole rulebook. Takes current weights, returns (new weights, reasons). No reasons = do nothing.

    Price drops never trigger a sale here. Satellites only leave when removed from strategy.json.
    """
    w = {t: w.get(t, 0.0) for t in set(w) | set(targets)}
    drift = {t: w[t] - targets.get(t, 0.0) for t in w}
    worst = max(drift, key=lambda t: abs(drift[t]))
    if new_year or abs(drift[worst]) > rules["band"]:
        why = "annual rebalance" if new_year else f"full rebalance: {worst} is {drift[worst]:+.1%} off target"
        return dict(targets), [why]
    new, reasons = dict(w), []
    for t in w:
        if t not in targets and w[t] > 0:
            new[broad] += new[t]
            new[t] = 0.0
            reasons.append(f"sell {t}: removed from strategy")
    for t, tw in sats.items():
        if w[t] == 0:
            new[broad] -= tw
            new[t] = tw
            reasons.append(f"buy {t}: new satellite at {tw:.1%}")
        elif w[t] > rules["trim_above"]:
            new[broad] += w[t] - rules["trim_to"]
            new[t] = rules["trim_to"]
            reasons.append(f"trim {t}: {w[t]:.1%} is above {rules['trim_above']:.0%}, back to {rules['trim_to']:.0%}")
    return new, reasons


# ---------------------------------------------------------------- live (paper) portfolio

def latest_prices(tickers):
    df = yf.download(sorted(tickers), period="5d", progress=False, auto_adjust=True)["Close"].ffill()
    missing = [t for t in tickers if pd.isna(df[t].iloc[-1])]
    assert not missing, f"no price for {missing}"
    return df.iloc[-1], df.iloc[-1] / df.iloc[-2] - 1


def snapshot():
    s, targets, sats = load_strategy()
    st = json.loads(STATE.read_text())
    tickers = set(st["positions"]) | set(targets)
    px, day = latest_prices(tickers)
    vals = {t: st["positions"].get(t, 0.0) * px[t] for t in tickers}
    nav = sum(vals.values()) + st["cash"]
    w = {t: v / nav for t, v in vals.items()}
    new_year = st["last_full_rebalance"] < datetime.now(timezone.utc).year
    new_w, reasons = plan(w, targets, sats, s["rules"], s["broad_stock"], new_year)
    return s, targets, st, px, day, nav, w, new_w, reasons


def cmd_init(args):
    assert not STATE.exists(), "state.json already exists; delete it to start over"
    STATE.write_text(json.dumps({"mode": "paper", "cash": args.amount, "positions": {},
                                 "last_full_rebalance": 0, "created": now()}, indent=2) + "\n")
    cmd_rebalance(args)


def cmd_status(args):
    s, targets, st, px, day, nav, w, new_w, reasons = snapshot()
    r = s["rules"]
    print(f"NAV ${nav:,.2f}  (started ${st.get('start_value', nav):,.2f}, mode: {st['mode']})\n")
    print(f"{'ticker':7}{'target':>8}{'now':>8}{'1 day':>8}  flag")
    for t in sorted(w, key=lambda t: -targets.get(t, 0)):
        flag = []
        if abs(day[t]) >= r["news_move"]:
            flag.append("big move: check news (do not sell on price)")
        if t in s["satellites"] and w[t] >= r["trim_above"] - 0.005:
            flag.append("close to trim level")
        print(f"{t:7}{targets.get(t, 0):8.1%}{w[t]:8.1%}{day[t]:+8.1%}  {'; '.join(flag)}")
    print("\nPlanned actions:" if reasons else "\nPlanned actions: none")
    for x in reasons:
        print(f"  - {x}")


def cmd_rebalance(args):
    s, targets, st, px, day, nav, w, new_w, reasons = snapshot()
    if not reasons:
        print("Nothing to do.")
        return
    if st["last_full_rebalance"] == 0:
        reasons = ["initial purchase"]
    new_file = not TRADES.exists()
    with TRADES.open("a", newline="") as f:
        out = csv.writer(f)
        if new_file:
            out.writerow(["time", "ticker", "side", "shares", "price", "dollars", "reason"])
        for t in sorted(new_w, key=lambda t: new_w[t] - w.get(t, 0)):  # sells first
            dollars = (new_w[t] - w.get(t, 0)) * nav
            if abs(dollars) < 0.01:
                continue
            shares = dollars / px[t]
            st["positions"][t] = st["positions"].get(t, 0.0) + shares
            if abs(st["positions"][t]) < 1e-9:
                del st["positions"][t]
            st["cash"] -= dollars
            out.writerow([now(), t, "buy" if dollars > 0 else "sell", f"{abs(shares):.6f}",
                          f"{px[t]:.4f}", f"{abs(dollars):.2f}", " | ".join(reasons)])
            print(f"{'BUY ' if dollars > 0 else 'SELL'} {t:6} ${abs(dollars):>10,.2f}")
    if any(x.startswith(("annual", "full", "initial")) for x in reasons):
        st["last_full_rebalance"] = datetime.now(timezone.utc).year
    st["cash"] = round(st["cash"], 6)
    st.setdefault("start_value", round(nav, 2))
    STATE.write_text(json.dumps(st, indent=2) + "\n")
    print("Reasons: " + " | ".join(reasons))


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")


# ---------------------------------------------------------------- backtest

def simulate(rets, targets, sats, rules, broad):
    hold, year, navs, trims = pd.Series(targets, dtype=float), rets.index[0].year, [], 0
    for dt, r in rets.iterrows():
        hold = hold * (1 + r[hold.index])
        nav = hold.sum()
        new_w, reasons = plan((hold / nav).to_dict(), targets, sats, rules, broad, dt.year != year)
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
    s, targets, sats = load_strategy()
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

    core_targets = {**s["defensive"], broad: s["stock_budget"]}
    runs = {"strategy": simulate(rets, targets, sats, s["rules"], broad),
            "no satellites (VT instead)": simulate(rets, core_targets, {}, s["rules"], broad),
            "100% VT": simulate(rets, {broad: 1.0}, {}, s["rules"], broad)}
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
    sub.add_parser("init").add_argument("amount", type=float)
    sub.add_parser("status")
    sub.add_parser("rebalance")
    sub.add_parser("backtest").add_argument("--start")
    a = p.parse_args()
    {"init": cmd_init, "status": cmd_status, "rebalance": cmd_rebalance, "backtest": cmd_backtest}[a.cmd](a)
