# Tax The Fools: Phase 6 (Profit Ledger and Price Trends) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task by task.
> Requirements, interfaces and required tests. Implementers write the code test-first against the spec.

**Goal:**
- A Ledger that records gold in and out (with transfers between your own characters kept apart) and shows totals, days and items.
- Price trends shown in tooltips, as a Browse column, and as a 30-day chart on Browse and Sell.

**Architecture:**
- **Pure rules:** `ledger.lua`, plus `P.Trend` / `P.Series` in `price.lua`.
- **Recording hooks:** in `auction.lua`, `mail.lua`, `mailbox.lua` and `core.lua`.
- **UI:** `ui_ledger.lua`, a `W.Chart` widget, and additions to `tooltip.lua`, `ui_browse.lua`, `ui_sell.lua` and `options.lua`.

**Spec:** `docs/superpowers/specs/2026-10-15-phase6-ledger-trends-design.md`.

## Global Constraints

- **Lua 5.0 rules:** no `#`, no `%` operator, no `string.match`/`gmatch`, no `select`, no `_G` (use `getglobal`), no closures over loop variables, at most 32 upvalues per function.
- **Fake client:** keep it strict.
- **Commits:** one commit per task, with a trailer naming the model.
- **Record only:** the hooks only record. No new calls to game actions (auction, mail, merchant or trainer). The automation guards stay green.
- **Text:** plain ASCII in all displayed text.
- **Defaults:**
  - `settings.ledger = { vendor = true }`
  - `settings.trend = { tooltip = true }`.
- **Limits:**
  - ledger: 5000 entries, 180 days
  - pending bids: 7 days
  - trend: windows of 7 + 7 days, at least 3 days each, a 5% steady band.
- **Layout:** everything must fit the AH window's minimum of 660×380.
- **Pass counts:** each task reports its actual count; the gate is 0 failed. Baseline 630 passed.

## Review Focus

1. **Gold mailed to your bank alt:** it is a transfer and never changes net profit. Tested in Task 3.
2. **A bid that is outbid:** it never shows as spending. Tested in Tasks 1 and 3.
3. **A sold mail recorded once by phase 4:** exactly one sale entry, including when Collect all runs (phase 5b's payload rule) and with the backfill. Tested in Task 3.
4. **An item with a 5-day gap in its history:** the trend uses only the days that exist and needs at least 3 on each side. Tested in Task 2.
5. **The chart at the AH window's minimum size:** it hides, and never overlaps the Buy/Bid bar or the Sell pricing fields. Tested in Task 5.

---

### Task 1: Pure ledger rules (`ledger.lua`)

**Files:** create `TaxTheFools/ledger.lua` (in the .toc after `sales.lua`) and `tests/test_ledger.lua`; add the defaults to `data.lua`.

**Interfaces:** spec §2, exactly.

**Required tests:** the ledger units in spec §7, plus Review Focus 2 (rules side).

**Commit:** `feat: pure ledger rules for totals, days, items, transfers and pending bids`

### Task 2: Trends (`P.Trend`, `P.Series`), tooltip line and Browse column

**Files:** modify `TaxTheFools/price.lua`, `tooltip.lua` and `ui_browse.lua`, and `tests/test_price.lua`, `test_tooltip.lua` and `test_browse_buy.lua` (or a new `tests/test_trend.lua`). Add `settings.trend` to `data.lua` only if Task 1 hasn't; coordinate by adding only your own key.

**Required:** spec §1 (trend row) and §5, except the chart.

**Required tests:** the trend units, the tooltip line on and off, the Browse column, and Review Focus 4.

**Commit:** `feat: 7-day price trend in tooltips and a Trend column on Browse`

### Task 3: Recording hooks

**Files:** modify `TaxTheFools/auction.lua`, `mail.lua`, `mailbox.lua` and `core.lua` (`MERCHANT_SHOW` / `MERCHANT_CLOSED`, `PLAYER_MONEY` routing alongside the existing deposit learning, and Prune/Backfill at login); create `tests/test_ledger_hooks.lua`.

**Required:** spec §3 in full.

**Required tests:** the hook cases in spec §7, Review Focus 1, 2 and 3, and the automation guard unchanged.

**Commit:** `feat: record buys, won bids, deposits, sales, vendor and mail gold in the ledger`

### Task 4: Ledger tab and options

**Files:** create `TaxTheFools/ui_ledger.lua` (in the .toc after `ui_history.lua`) and `tests/test_ledger_ui.lua`; modify `ui_window.lua` (the tab after History), `core.lua` or the slash-command handler (`/ttf ledger`), `options.lua` and `tests/test_options.lua` (the Ledger option, and the trend tooltip toggle).

**Required:** spec §4 and §6.

**Required tests:** totals, both views, filters, the empty state, `/ttf ledger`, and options binding.

**Commit:** `feat: Ledger tab with totals, days and items; ledger and trend options`

### Task 5: Chart widget on Browse and Sell

**Files:** modify `TaxTheFools/widgets.lua` (`W.Chart`), `ui_browse.lua`, `ui_sell.lua`, `tests/test_widgets.lua`, `tests/test_sell_ui.lua` and the Browse tests.

**Required:** spec §5 (the chart).

**Required tests:** bars and marker, the empty state, the hover tooltip, shown on selection on both Browse and Sell, and Review Focus 5.

**Commit:** `feat: 30-day price chart on Browse and Sell`

### Task 6: Docs and version

**Files:** `docs/testing-checklist.md` (the spec §7 in-game steps, continuing the numbering), `README.md` (Ledger and trends), and version 0.8.0 in the .toc and `data.lua`.

**Commit:** `docs: ledger and trends checklist, README and version 0.8.0`

## Execution order

1. Tasks 1 and 2 in parallel. Task 1 owns `ledger.lua` and the `settings.ledger` line; Task 2 owns `price.lua`, `tooltip.lua`, `ui_browse.lua` and the `settings.trend` line. The controller pre-adds the `.toc` line and both `data.lua` defaults.
2. Task 3.
3. Tasks 4 and 5 in parallel. Task 4 owns `ui_ledger.lua`, `ui_window.lua`, `options.lua` and the slash command; Task 5 owns `widgets.lua`, `ui_browse.lua` and `ui_sell.lua`.
4. Task 6.
