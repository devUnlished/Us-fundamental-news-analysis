# TRADER MACHINE — master document

One doc to hold everything. Knowledge, rules, protocols, state. Update it when any of those change.

## 1. Mission

Trade XAUUSD on FBS-Real with a machine: fast, thesis-driven, risk-capped.
No gambling. Every trade has a written thesis, exact SL/TP, and fixed $ risk —
or it doesn't happen. Human approval is SKIPPED by owner instruction; the
machine gates below replace it. They are hard rules, not guidelines.

## 2. Architecture

```
MT5 terminal (live data)  →  mini-model (3-second brief)  →  Muse (decision)
        ↑                              ↓                              ↓
   EA command link ←────────── NotebookLM "Trader" (grounding) ──→ thesis + orders
```

- **Data layer**: MT5 native MCP (127.0.0.1:22346) — quotes, M1→D1 history,
  account, calendar, journals. Plus EA command link for execution.
- **Mini-model** (to build): pulls the data matrix (§4), computes features,
  emits a fixed-format brief. Latency budget TBD by research, not assumed.
- **Knowledge layer**: NotebookLM notebook "Trader" (below). Foundations only —
  math, vocabulary, mechanics. Never copied strategies.
- **Decision layer**: Muse. Takes brief + notebook grounding → thesis + exact
  plan → executes via EA link only if ALL gates (§3) pass.
- **Execution layer**: AllInOneNewsTerminal EA v5.10+ on XAUUSD M1, via the
  file command link. Direct MCP trade tools are BLOCKED server-side in this
  build ("trading is not permitted") — the EA is the only trading path.

## 3. Hard gates (autonomy failsafes — ALL must pass)

1. Max risk **$2/trade**. Computed from SL distance × $1 per $1 move per 0.01.
2. Max **2 shots/day**. Third idea waits for tomorrow.
3. Daily stop **-$4**: halt all trading, report, stand down until next day.
4. **SL+TP atomic**: no order without protection set at fire time. (Requires
   the EA protocol extension — autonomy starts only after it ships + tests green.)
5. **Margin fit**: order margin ≤ 50% of free margin.
6. **Spread veto**: spread > 2× recent median = no entry (news widening / thin book).
7. **Calendar blackout**: no technical entries within ±5 min of USD high-impact
   unless the thesis IS the news play (then use the EA's news tooling).
8. **Thesis complete**: trend, level, trigger, direction, entry, SL, TP, size,
   $ risk, R multiple, invalidation. Any field missing = no trade.
9. **One position at a time** until the win rate over 20 trades is known.
10. **SL-distance ceiling**: required SL wider than $2.00 at 0.01 lots = PASS.
    (Min-lot floor makes wider stops forced over-risk. No discretion.)
11. **TP ≥ 1.5R** or PASS. No even-money gambles.
12. **SL buffer**: SL distance must exceed 3× current spread (phantom-stop guard).

## 4. Data matrix (mini-model inputs)

| # | Feed | Depth | Use |
|---|------|-------|-----|
| 1 | Tick bid/ask/spread | live | cost gauge, spread veto |
| 2 | M1 | 120 bars | trigger, wick anatomy |
| 3 | M15 | 100 bars | structure, swings |
| 4 | H1 | 200 bars | trend, key levels |
| 5 | D1 | 100 bars | regime, ADR |
| 6 | Calendar | -2h/+24h | blackout or news play |
| 7 | Account | live | margin fit, exposure |
| 8 | Session | UTC+server | London/NY/overlap/Asia context |

Derived: ATR(14) per TF, spread/ATR %, N-bar ROC, range position %, swing H/L,
last-3-M1 body/wick ratios, ADR consumed %, distance to SL/TP in R.

## 5. Knowledge base — NotebookLM "Trader"

- Notebook ID: `6d49e86a-f47b-4be5-9d15-f1c49fd17e9a`
- URL: https://notebook.google.com/notebook/6d49e86a-f47b-4be5-9d15-f1c49fd17e9a
- CLI: `nlm` (`~/.local/share/uv/tools/notebooklm-mcp-cli/bin/nlm`)

### Sources (foundations, not strategies)
- **Market math**: ATR (Wikipedia), order-book microstructure, slippage +
  execution costs, bid-ask spread mechanics.
- **Timeframes/sessions**: XAUUSD multi-timeframe guide, MTF discipline,
  gold session volatility, NY/COMEX hours + US release times.
- **Risk math batches**: Kelly criterion (Wikipedia + papers), Optimal f /
  Ralph Vince, portfolio leverage (arXiv/Frontiers) — via deep research import.
- **News impact (24)**: CPI/NFP/FOMC → gold/FX reaction guides, Fed-rate event
  study on spot gold, news spread-widening, liquidity/microstructure papers.
- **In flight**: price-action vocabulary deep research (trends/ranges/wicks).
- **Total**: ~53 sources and counting.
- **OUR canon**: "Trader Machine Data Requirements v1" (text source) — our spec.

## 6. EA command-link protocol (v5.10)

Files in `MQL5/Files`: `mcp_cmd.txt` → `mcp_ack.txt`.
- Line 1: `COMMAND [args]`; line 2: `TS=<gmt-sec> NONCE=<token>`.
- Commands: PING, STATUS, SET_LOT, SET_STRIPES, BUY_BARCODE, SELL_BARCODE,
  BUY_LIMIT, SELL_LIMIT, STRADDLE, PANIC_CLOSE.
- Safety: InpAllowMCP gate (default off), single-use file, 60s freshness,
  nonce replay guard, whitelist, journaled + shown on panel row 8.
- Client: `/tmp/mcp_link.py` (to be promoted into `engine/`).
- **Needed next**: optional `SL=`/`TP=` on fire commands (atomic protection).

## 7. State log

- 2026-11-05: account FBS-Real 112324042, started $17.00.
- 2026-11-05: $2 test trade → -$1.36 (entry via EA OK; MCP SL set blocked;
  flattened via PANIC_CLOSE). Balance $15.64.
- 2026-11-05: agent DEBT to owner: **$2** (to be made back, disciplined only).
- Link status: ARMED on XAUUSD M1. Duplicate EA on XAUUSD H1 removed.
- MCP trade tools (send/check/modify): BLOCKED by terminal despite green flags.

## 8. Roadmap

1. [ ] Import remaining research batches (vocab, news impact).
2. [ ] EA: atomic SL/TP on fire commands → compile → push → attach → test.
3. [ ] Promote `mcp_link.py` + brief scripts into `engine/` (durable tooling).
4. [ ] Build mini-model v1 (data pull + features + latency-measured brief).
    Spec: Mini-Model Spec v2 (notebook canon, research-grounded). Open items:
    O1 loop latency, O2 session spread medians, O3 fill slippage log,
    O4 20-trade paper sample — measured before live autonomy.
5. [ ] Paper-trade 5 theses (analysis only, no orders) to calibrate.
6. [ ] Autonomous micro-trading under §3 gates.
