# Tax The Fools: Phase 10 (Quick sell) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task by task.
> Requirements, interfaces and required tests. Implementers write the code test-first against the spec.

**Goal:** A Quick view on the Sell tab. One click scans prices for everything in the bags, then one **Post next** button posts one bag slot per click and moves on by itself.

**Spec:** `docs/superpowers/specs/2026-10-19-phase10-quick-sell-design.md`.

## Global Constraints

- **Lua 5.0 rules:**
  - no `#`, no `%` operator, no `string.match`/`gmatch`, no `select`, no `_G` (use `getglobal`)
  - no closures over loop variables
  - at most 32 upvalues per function.
- **Fake client:** `tests/wow_stub.lua` stays strict.
- **One click, one post:** each Post next click calls `StartAuction` at most once, and only through `Auction.Post`. Nothing posts without a click. The scan is the only automatic part.
- **Window size:** fits at 660×380 with nothing cut off.
- **Text:** plain ASCII in UI strings. Write "vendor x3", not "×".
- **Settings defaults:** `settings.sell.quickVendor = false` and `settings.sell.vendorMult = 3`.
- **Version:** 0.12.0 in the .toc and in `D.VERSION` (`data.lua`).
- **Tests:** baseline 811 passed; the gate is 0 failed (`make test` exit code 0).
- **Commits:** one commit per task, with a trailer naming the model.

## Review Focus

1. **Two slots of one item** (20 + 7 Runecloth): two rows at the same unit price, posted one after the other with no rescan. The second click posts the 7 (Task 1, Task 3).
2. **Clicking Post next again before the server answers:** nothing is sent, and the highlight doesn't move (Task 3).
3. **A failed post** (bags changed, or deposit unaffordable): the row shows Failed with the reason, the highlight moves on, and the next click posts the next row (Task 3).
4. **Vendor-priced rows with the checkbox off:** Post next passes over them. With it on, they post at vendor × vendorMult. The Bags view's vendor suggestion uses the same multiple (Task 1, Task 3).
5. **A scan query matching other items** (the name "Runecloth" also returns "Runecloth Bag", and a base name returns every random suffix): listings are grouped by key, so each row's price comes only from its own key (Task 2).

---

### Task 1: Pure rules

**Files:**
- Create `TaxTheFools/quick.lua`, placed in the .toc after `stock.lua`.
- Modify `TaxTheFools/sell.lua` (`Sell.Suggest`) and `TaxTheFools/data.lua` (the two settings).
- Create `tests/test_quick.lua`. Extend `tests/test_sell.lua`.

**Interfaces (produces):**
- `Sell.Suggest(listings, market, vendorSell, s)`:
  - uses `s.vendorMult` (default 3 when absent) in place of the fixed 3
  - adds `out.atFloor = true` when the buyout is the floor because a competing (not own) listing was at or below the floor, or because the undercut was clamped up to the floor.
  
  Every existing caller and test keeps working.
- `Quick.Rows(slots, prices)`, which returns a list of rows.
  - `slots` is a list of `{ bag, slot, key, id, name, count, tex, quality }`.
  - `prices[key]` is a `Sell.Suggest` result, or nil when the item was not scanned.
  - Each row is `{ bag, slot, key, id, name, count, tex, quality, unit, bid, source, atFloor, status }`.
    - `unit` and `bid` are per unit.
    - `status` is `nil` (postable), `"noprice"`, `"vendor"` or `"notscanned"`.
  - Rows are sorted by name, then by count with the bigger first. Ties keep bag and slot order.
- `Quick.Next(rows, from, includeVendor)` returns the index of the first postable row after `from` (0 means from the start), or nil.
  - **Postable:** status nil, or status `"vendor"` when `includeVendor` is true.
  - **Never chosen:** rows whose `done` field is `"posted"`, `"failed"` or `"skipped"`.

**Required tests:**
- One row per slot. Two slots of one key give two rows with the same `unit`.
- The sort order.
- `noprice`, `vendor` and `notscanned` statuses.
- `Next` skips done rows and non-postable statuses, and respects `includeVendor`.
- `Suggest` uses `vendorMult`.
- `atFloor`:
  - true when a competitor sits under the floor
  - true when the undercut is clamped
  - false for a normal undercut
  - false with no market value.
- Review Focus 1 and 4 (pure parts).

**Commit:** `feat: quick sell rules and vendor multiple`

### Task 2: The Scan bags session

**Files:** `TaxTheFools/quick.lua` and `tests/test_quick.lua`.

**Interfaces:**
- **Consumes:**
  - `Scan.Start(kind, queries, now)`, which returns false plus `"busy"` or `"empty"`.
  - `Scan.OnRows(fn)`, fired per page with `{ key, unit, qty, owner, ... }`.
  - `Scan.OnChange` and `Scan.Busy()`.
  - `Scan.lastFinished`.
  - `Sell.Auctionable`, and the bag reading used by `SellUI.ReadBags` (move the per-slot reading into a shared helper in `sell.lua` if needed, so Quick doesn't depend on UI files).
- **Produces:**
  - `Quick.Scan(now)`, which returns `true`, or `false, reason`.
    - It reads the bag slots.
    - It builds one exact-name query per distinct item id, using the base item name (from `GetItemInfo(id)`, falling back to the slot name), so every random suffix is covered.
    - It starts the scan with kind `"quick"`.
  - `Quick.state`, one of `"idle"`, `"scanning"` or `"ready"`.
  - `Quick.rows` and `Quick.scannedAt` (`time()`).
  - `Quick.OnChange(fn)` for the UI.
- **Behaviour:**
  - While Quick's own scan runs, rows are collected and grouped by key. Rows from scans Quick didn't start are ignored.
  - When the scan finishes, the bags are read again and `Quick.rows = Quick.Rows(slots, prices)`.
    - **Prices:** `Sell.Suggest(listingsForKey, market, vendor, settings)`. Settings are `floorPct`, `undercut`, `bidPct`, `vendorMult`, plus `me` set to the character name.
    - **Not scanned:** a slot whose key's item id wasn't in the query set gets status `"notscanned"`.
  - A scan that is paused or stalled stays `"scanning"` until it finishes. If it is discarded, the state goes back to `"idle"`.
  - Check how `Scan.Finish` treats a new kind before relying on it. A `"quick"` scan should record history and the snapshot the way a watch scan does.

**Required tests:**
- With the fake AH, a Quick scan sends one query per distinct item and fills prices by key. Review Focus 5 is covered: "Runecloth Bag" listings don't affect Runecloth.
- A busy scanner returns `false, "busy"`.
- A full scan finishing doesn't change `Quick.rows`.
- A slot added after the scan started shows `"notscanned"`.

**Commit:** `feat: quick sell bag scan`

### Task 3: The Quick view

**Files:**
- Create `TaxTheFools/ui_quick.lua`, in the .toc after `ui_stock.lua`.
- Modify `ui_stock.lua` (add the fourth view button, **Quick**, and route `StockUI.SetView` to it).
- Modify `options.lua` (Selling page: "Include vendor-priced items" and "Vendor price multiple", each with a hint).
- Tests.
- `docs/testing-checklist.md` (a Quick sell section).
- `README.md` (Quick sell under selling).
- Version 0.12.0.

**Required behaviour (spec §3 to §5):**
- **Top bar:**
  - Scan bags
  - status: "Scanning..." with progress, or "Prices from 2m ago"
  - the duration picker, which only changes the list and starts at `settings.sell.duration`
  - the checkbox "Include vendor-priced items" and the multiple box. Both write the saved settings; changing the multiple re-prices vendor rows.
- **List columns:** item, stack, unit, total, status.
- **Status column text:**
  - "at floor"
  - "no price"
  - "vendor x3", using the real multiple
  - "not scanned"
  - "Posted"
  - "Failed: <reason>"
  - "Skipped"
- **Highlight:** the row `Quick.Next(rows, 0, includeVendor)`. Clicking a postable row makes it the highlight.
- **Post next:** posts the highlighted row.
  - The call is `Auction.Post(bag, slot, count, bid*count, unit*count, minutes, key, false, onPosted, onFailed)`.
  - **Success:** `onPosted` marks the row Posted and moves the highlight with `Quick.Next`.
  - **Failure:** `onFailed(text)` marks the row Failed with that text and moves on.
  - **Refused at once:** if `Auction.Post` returns false, the row is marked Failed with the refusal text and the highlight moves on.
  - **While waiting:** the button reads "Waiting..." and a click does nothing while `Auction.busy` is set.
  - **Disabled:** the button is disabled before a scan, and when no row is postable.
- **Skip:** marks the highlighted row Skipped and moves on.
- **Summary line:** "N of M posted, <total gold>".
- A rescan clears every done mark.
- Switching views away and back keeps the list.

**Required tests:**
- With the fake client:
  - Each Post next click calls `StartAuction` exactly once.
  - The highlight moves only on the success reply.
  - Review Focus 1, 2, 3 and 4 (the UI parts).
  - Skip.
  - A rescan clears marks.
- The automation guard: the Quick view's OnUpdate and its events never call `StartAuction`.
- No text is cut off at 660 width, as the existing layout tests check.

**Commit:** `feat: Quick sell view on the Sell tab (0.12.0)`
