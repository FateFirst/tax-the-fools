# Tax The Fools: Phase 8 (Repost List and Stock View) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task by task.
> Requirements, interfaces and required tests. Implementers write the code test-first against the spec.

**Goal:** The Sell tab gets two new views:
- **Repost:** items that came back from the AH, preset at your last stack and priced at today's market.
- **Stock:** everything your characters hold, with its value.

**Spec:** `docs/superpowers/specs/2026-10-15-phase8-repost-stock-design.md`.

## Global Constraints

- **Lua 5.0 rules:**
  - no `#`, no `%` operator, no `string.match`/`gmatch`, no `select`, no `_G`
  - no closures over loop variables
  - at most 32 upvalues per function (`ui_sell.lua` is large, so split it into helpers or a new `ui_stock.lua`).
- **Fake client:** keep it strict.
- **Commits:** one commit per task, each with a trailer naming the model.
- **Posting:** stays one click per stack. Nothing new calls `StartAuction`.
- **Text:** plain ASCII.
- **Window size:** fits at 660×380.
- **Default:** `settings.sell.repostDays = 7`.
- **Tests:** baseline 762 passed; the gate is 0 failed.

## Review Focus

1. **Bag counts changed:** an item that came back but has since been sold or moved out of the bags is not in Repost (Task 1).
2. **Stack preset larger than the bag count:** when the bags no longer hold the last stack size, the stack size falls back to the Sell panel's default (Task 2).
3. **Your own auctions in Stock:** they are counted once, from open postings only (Task 1).
4. **Stock at 660 width:** no column is cut off (Task 2).
5. **Switching to Stock and back to Bags:** the pricing panel and its selection come back as they were (Task 2).

---

### Task 1: Pure rules (`stock.lua`)

**Files:**
- Create `TaxTheFools/stock.lua`, placed in the .toc after `sales.lua`.
- Create `tests/test_stock.lua`.
- Add `repostDays = 7` to `settings.sell` in `data.lua`.

**Interfaces:** spec §2.

**Required tests:** spec §4, the `stock.lua` items, plus Review Focus 1 and 3.

**Commit:** `feat: pure repost and stock rules`

### Task 2: Sell tab views

**Files:**
- `TaxTheFools/ui_sell.lua`, plus a new `ui_stock.lua` if that keeps `ui_sell.lua` within its limits (placed in the .toc after `ui_sell.lua`).
- `options.lua`.
- Tests.
- `docs/testing-checklist.md`.
- `README.md`.
- Version 0.10.0 in the .toc and `data.lua`.

**Required:** spec §3.

**Required tests:** spec §4, the UI items, plus Review Focus 2, 4 and 5.

**Commit:** `feat: Repost and Stock views on the Sell tab (0.10.0)`
