# Tax The Fools: Phase 3b (Selling) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task by task.
> Like phase 3a, this plan gives requirements, interfaces and required tests. Implementers write the code test-first against the spec.

**Goal:** Sell from our own AH window: a Sell tab with a suggested price and one click per stack, an Auctions tab showing undercut status with one click per cancel, and a posting log for phase 4.

**Architecture:**
- **Pricing:** pure rules in `sell.lua`, tested directly.
- **Actions:** posting, splitting and cancelling extend `auction.lua`'s one-click engine, sharing its lock and reply handling.
- **UI:** two new pages, `ui_sell.lua` and `ui_auctions.lua`, registered as AH tabs.
- **Plumbing:** wired through `core.lua`.

**Tech stack:** Lua 5.0.3, the WoW 1.12.1 API, and the fake client in `tests/wow_stub.lua`.

**Spec:** `docs/superpowers/specs/2026-10-15-phase3b-selling-design.md`, with the phase 3a spec and the parent spec §7–§9.

## Global Constraints

- Everything in the phase 3a plan's Global Constraints still applies. That covers the Lua 5.0 rules, no closures over loop variables, initialising frame fields, a faithful fake client, checking ClassicAPI signatures, and one commit per task with a trailer naming the model.
- **One click:** `StartAuction`, `CancelAuction`, `SplitContainerItem` and `PlaceAuctionBid` are called only from `auction.lua`'s action functions, and those run only from a button OnClick or a confirmation window's button. Never from a search, a scan, an event or an OnUpdate.
- **Defaults:** `settings.sell = { bidPct = 90, floorPct = 80, undercut = 1, duration = 480 }`.
- **Durations:** 120, 480 and 1440 minutes, labelled 6h, 24h and 72h.
- **AH cut:** 0.05.
- **Posting log:** at most 500 entries, kept 35 days.
- **Pass counts:** each task reports its actual count; the gate is 0 failed. Baseline 278 passed.

## Review Focus

1. **The bag changes between selecting an item and clicking Post** (the stack moved, was split or was sold): Post refuses and makes no `StartAuction`. Tested in Task 2.
2. **A price below the floor:** Post is blocked until "Allow below floor" is ticked, and that permission resets when you pick another item. Tested in Tasks 2 and 3.
3. **Clicking Post twice quickly:** exactly one `StartAuction`. Tested in Task 2.
4. **Cancelling an auction that has a bid:** a confirmation first; Cancel never runs from the first click alone. Tested in Task 2.
5. **Soulbound, quest or conjured items:** never shown in the Sell grid. Tested in Task 1.

---

### Task 1: Pure selling rules (`sell.lua`) and the posting log

**Files:** create `TaxTheFools/sell.lua` (in the .toc after `deals.lua`) and `tests/test_sell.lua`. Add the `settings.sell` defaults to `data.lua`.

**Interfaces produced (spec §3):**
- `Sell.Suggest(listings, market, vendorSell, s)`
- `Sell.Stacks(have, stackSize, maxStack)`
- `Sell.Net(total, deposit)`
- `Sell.Auctionable(lines)`: `lines` are the tooltip text lines, so it stays pure. A game-side helper `Sell.TipLines(bag, slot)` reads them with `U.scanTip()`.
- `Sell.Log(char, entry, now)`: appends, caps at 500 and prunes entries older than 35 days.
- `Sell.Prune(char, now)`
- `Sell.LearnDeposit(items, id, minutes, perUnit)` and `Sell.Deposit(items, id, minutes, stack)`: the learned deposit or nil.

**Required tests:** every `sell.lua` case listed in spec §7. Show the arithmetic in comments.

**Commit:** `feat: pure selling rules, posting log and learned deposits`

### Task 2: Post, Split and Cancel in the action engine

**Files:** modify `TaxTheFools/auction.lua` and `tests/wow_stub.lua`, and create `tests/test_sell_engine.lua`. Also create a small `ui_cancel_confirm`, or generalise `ui_confirm.lua` to take a message and an action, without breaking 3a's tests.

**Required:**
- spec §2, exactly
- the fake client additions from spec §7, each citing its source in a comment
- reply handling that extends `Auction.OnMessage` and `finish()` for `post` and `cancel`
- on post success: `Sell.Log` and `Sell.LearnDeposit`
- on cancel success: re-request the owner list.

**Interfaces produced:**
- `Auction.Post(bag, slot, stack, bid, buyout, minutes, key, allowBelowFloor, after, onFail)`
- `Auction.Split(bag, slot, size)` returns true, or nil plus a reason
- `Auction.Cancel(index, sig, after, onFail, confirmed)`
- `Auction.OwnerRow(i)` reads owner row `i`, in the same shape as `Scan.ReadRow`.

**Required tests:**
- every engine case in spec §7
- Review Focus 1, 2, 3 and 4.

**Commit:** `feat: one-click post, split and cancel with replies, posting log and learned deposits`

### Task 3: Sell tab

**Files:** create `TaxTheFools/ui_sell.lua` (in the .toc after `ui_deals.lua`) and `tests/test_sell_ui.lua`. In `ui_window.lua`, `UI.TABS` becomes Deals, Browse, Sell, Auctions, Crafting. The Auctions builder comes in Task 4, so register only what exists, or add the tab key in Task 4.

**Required:** spec §4 in full, including the floor override resetting for each item. The competition search goes through `Scan.Browse` and is refused while a scan runs, falling back to the snapshot. Reuse the 3a list, money-field and action-bar patterns; check `ui_deals.lua` and `ui_browse.lua`, and add a money input widget to `widgets.lua` if none exists.

**Required tests:** the UI cases from spec §7 for Sell, plus Review Focus 2 at the UI level.

**Commit:** `feat: Sell tab with suggested price, split and one-click posting`

### Task 4: Auctions tab

**Files:** create `TaxTheFools/ui_auctions.lua` (in the .toc after `ui_sell.lua`) and `tests/test_auctions_ui.lua`. Register the tab.

**Required:** spec §5 in full: the owner-list request and read, status colours, the summary, and Cancel with confirmation. `AUCTION_OWNED_LIST_UPDATE` is routed through `Core.Safe`.

**Required tests:** owner rows; undercut, cheapest and no-competition status; Cancel without a bid makes one `CancelAuction`; Cancel with a bid confirms first; the list is re-requested after a cancel.

**Commit:** `feat: Auctions tab with undercut status and one-click cancel`

### Task 5: Options, wiring, pruning and the automation guard

**Files:** `options.lua`, `core.lua`, `tests/test_core.lua` and `tests/test_options.lua`.

- **Selling options:** the category from spec §6, bound to `settings.sell`.
- **Login pruning:** `Sell.Prune` runs at login.
- **Event routing:** any events not yet routed (`AUCTION_OWNED_LIST_UPDATE` and the post replies) go through `Core.Safe`.
- **Automation guard:** extended per spec §7.

**Commit:** `feat: Selling options, posting-log pruning, wiring and automation guard for selling`

### Task 6: Docs and version

**Files:** `docs/testing-checklist.md`, `README.md`, `TaxTheFools/TaxTheFools.toc` and `TaxTheFools/data.lua`.

- **Checklist:** add the steps from spec §7.
- **README:** add Sell and Auctions, and say that phase 4 (sales tracking from mail) is next.
- **Version:** bump to 0.4.0.

**Commit:** `docs: selling checklist, README and version 0.4.0`
