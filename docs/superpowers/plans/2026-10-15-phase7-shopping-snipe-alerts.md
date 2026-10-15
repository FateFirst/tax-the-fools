# Tax The Fools: Phase 7 (Shopping List, Snipe List, Quick Scans and Alerts) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task by task.
> Requirements, interfaces and required tests. Implementers write the code test-first against the spec.

**Goal:** Add three features:
- a crafting shopping list (cheapest path, after what you already hold)
- a snipe list of items with a max price each, whose matches show in Deals
- quick scans (Materials, Snipe list) and deal and snipe alerts while scanning.

**Spec:** `docs/superpowers/specs/2026-10-15-phase7-shopping-snipe-alerts-design.md`.

## Global Constraints

- **Lua 5.0 rules:**
  - no `#`, no `%` operator, no `string.match` / `gmatch`, no `select`, no `_G` (use `getglobal`)
  - no closures over loop variables
  - at most 32 upvalues per function.
- **Fake client:** keep it strict.
- **Commits:** one commit per task, with a trailer naming the model.
- **One-click rule:** nothing in this phase buys, bids, posts, cancels, sends or takes mail. The automation guards stay green.
- **Text and layout:**
  - all displayed text is plain ASCII
  - everything fits the 660×380 minimum AH window
  - the Deals rail stays at or under 253px.
- **Defaults:**
  - `settings.alerts = { on = true, minProfit = 10000, sound = true, snipe = true }`
  - `settings.deals.snipe = true`
  - `DB.Realm().snipe = {}`, created on demand.
- **Pass counts:** each task reports its actual count; the gate is 0 failed. Baseline 710 passed.

## Review Focus

1. **A bolt you already hold:** it is used before buying cloth to craft another. Tested in Task 1.
2. **Your own listing under your snipe price:** never a Snipe deal and never an alert. Tested in Tasks 2 and 3.
3. **The same listing seen again on the next page or the next scan:** no second alert. Tested in Task 3.
4. **A snipe match that is also a below-market deal:** listed once. Tested in Task 2.
5. **"Next material" after the last line:** it wraps to the first, and it hides once you leave the shopping flow. Tested in Task 4.

---

### Task 1: Shopping plan (`shopping.lua`, pure)

**Files:** fill in `TaxTheFools/shopping.lua` (the placeholder is already in the .toc after `craft.lua`) and create `tests/test_shopping.lua`.

**Interfaces:** spec §2, `Shopping.Plan`.

**Required tests:** the Shopping list in spec §6, plus Review Focus 1.

**Commit:** `feat: shopping plan for N crafts by the cheapest path after holdings`

### Task 2: Snipe rules and Snipe deals (`snipe.lua`, `Deals.FindSnipes`)

**Files:** fill in `TaxTheFools/snipe.lua` (the placeholder is already in the .toc after `deals.lua`), modify `TaxTheFools/deals.lua`, and create `tests/test_snipe.lua`.

**Interfaces:**
- `Snipe.Set`, `Snipe.Remove`, `Snipe.Parse` and `Snipe.Match` (spec §3)
- `Deals.FindSnipes(snapshot, list, me)`.

**Required tests:** the Snipe list in spec §6, plus Review Focus 2 (deal side) and 4 (the pure merge helper the UI will use).

**Commit:** `feat: snipe list rules and Snipe deals`

### Task 3: Quick scans and alerts

**Files:**
- create `TaxTheFools/alerts.lua` (in the .toc after `scan.lua`)
- modify `TaxTheFools/scan.lua` (`Scan.MatsQueries`, `Scan.SnipeQueries`, the kinds `"mats"` and `"snipe"`, and `Scan.OnRows` listeners fired with each page's new listings)
- modify `ui_window.lua` (the Quick scan menu and the paused text)
- modify `core.lua` (wire Alerts)
- tests: `tests/test_alerts.lua`, plus the scan and UI tests.

**Required:** spec §4.

**Required tests:** the Alerts and Scan lists in spec §6, plus Review Focus 2 (alert side) and 3.

**Commit:** `feat: Materials and Snipe quick scans, and deal and snipe alerts while scanning`

### Task 4: Shopping list on the Crafting tab, and Next material

**Files:** modify `TaxTheFools/ui_craft.lua`, `ui_browse.lua`, `tests/test_craft_ui.lua` and the Browse tests.

**Required:** spec §2 UI. "Snipe these" calls `Snipe.Set`.

**Required tests:** the shopping UI items in spec §6, plus Review Focus 5.

**Commit:** `feat: Craft N shopping list with clickable lines, Snipe these, and Next material on Browse`

### Task 5: Snipe list UI

**Files:**
- modify `TaxTheFools/ui_deals.lua` (the Deals | Snipe list toggle and view, merging FindSnipes deals)
- modify `ui_browse.lua` (the Snipe button and row tint)
- add the `/ttf snipe` slash command (in `core.lua`'s slash handler)
- tests.

**Required:** spec §3 UI.

**Required tests:** the Snipe UI items in spec §6, plus Review Focus 4 at the UI level.

**Commit:** `feat: Snipe list view in Deals, Snipe button on Browse, /ttf snipe`

### Task 6: Options, docs and version

**Files:**
- `options.lua` and `tests/test_options.lua`: the Alerts category and the Deals Snipe switch, every row with a hint.
- `docs/testing-checklist.md`: steps continuing the numbering.
- `README.md`.
- Version 0.9.0 in the .toc and `data.lua`.

**Commit:** `feat: Alerts options; docs: shopping, snipe and alerts checklist, README and version 0.9.0`

## Execution order

1. **Tasks 1 and 2 in parallel.** The controller pre-adds the placeholders, the .toc lines and the defaults. Task 1 owns `shopping.lua`; Task 2 owns `snipe.lua` and `deals.lua`.
2. **Task 3.**
3. **Task 4.**
4. **Task 5.**
5. **Task 6.**
