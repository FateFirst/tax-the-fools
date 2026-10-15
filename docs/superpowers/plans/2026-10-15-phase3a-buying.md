# Tax The Fools: Phase 3a (Buying) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task by task.
> Unlike the phase 1 and 2 plans, this one gives requirements, interfaces and required tests rather than complete code. The first plan-writing run stalled. Implementers write the code test-first against the spec.

**Goal:** Buy from our own AH window. Browse gets Buy and Bid buttons. A Deals tab finds below-market, below-vendor and cheap-material listings, using a saved snapshot of the last scan. Every purchase is one click, with confirmation above a gold amount.

**Architecture:**
- **Pure rules:** `deals.lua`, with no game calls. It is tested directly.
- **Engine:** the one-click `auction.lua` engine (already built), with its lock and reply handling.
- **UI:** an action bar in Browse; a Deals page with a filter rail and Find/Buy.
- **Plumbing:** everything is wired through `core.lua`, as in earlier phases.

**Tech stack:** Lua 5.0.3, the WoW 1.12.1 API (Interface 11200), and the fake client in `tests/wow_stub.lua`.

**Spec:** `docs/superpowers/specs/2026-10-15-phase3a-buying-design.md`, with the parent `docs/superpowers/specs/2026-10-14-tax-the-fools-design.md` §7–§9.

## Global Constraints

- Everything in the phase 2 plan's Global Constraints still applies.
- **Lua 5.0:**
  - No `#`, `%`, hex literals, `string.match`/`gmatch` or `select`.
  - Never capture a `for` loop variable in a closure.
  - Initialise every frame field that is later tested for truth.
  - At most 32 upvalues per function.
- **One click:** `PlaceAuctionBid` is called only by `auction.lua`'s `place()`, and that runs only from `Auction.Buy` or `Auction.Bid`, which are called only from a button OnClick or from the confirmation window's Buy OnClick. A scan, a Find, an event or an OnUpdate must never reach them.
- **Fake client:** it must model the real client exactly, including erroring on wrong argument types. If a test needs a new API, add it to `tests/wow_stub.lua`, with a comment citing where the behaviour comes from.
- **ClassicAPI:** if you use a `C_Item` function, check its signature in ClassicAPI's `docs/API.md`. Plain names take an itemLocation; `…ByID` names take an id.
- **Deal defaults (spec §4):** `belowMarketPct` 70, `minProfit` 5000, `matPct` 85, `minConfidence` 0.4, all types on. Confirmation threshold `settings.buy.confirmAbove` = 50000 (already in `data.lua`).
- **Deposit:** `Craft.Deposit(vendorUnit, maxStack, stack, D.DEPOSIT_MINUTES, 1)`. The AH cut is 0.05.
- **Pass counts:** each task reports its actual count; the gate is `0 failed`. Baseline at the start of Task 1 is 228 passed.
- **Commits:** one per task, message as given, plus a `Co-Authored-By` trailer naming the model that wrote it.

## Already built (salvaged from the stalled planning run, on branch `phase3a-buying`)

- `ab9c8cf`, **snapshot:** `Scan.SaveSnapshot(job)`, `Scan.SnapRow`, `Scan.ParseSnapRow(s) -> count, buyout, minBid, owner`, `Scan.SnapshotRemove(sig) -> bool` and `Scan.SnapshotAge(today) -> days|nil`, stored at `realm.snapshot = { at, day, rows = { [key] = { "count|buyout|minBid|owner" } } }`. Tests are in `tests/test_snapshot.lua`.
- `c350f33`, **engine:**
  - `Auction.busy` (false or a table), `Auction.Sig(row)`, `Auction.Match(index, sig) -> row|nil`, `Auction.BidAmount(row)` and `Auction.NeedsConfirm(amount)`.
  - `Auction.Own(row)`, `Auction.Buy(index, sig, after, confirmed) -> true|"confirm"|nil`, `Auction.Bid(index, sig, after)`, `Auction.OnMessage(msg)` and `Auction.Tick(now)`.
  - `Auction.Say(text, token)` puts a message on the strip and in chat; `Auction.OnChange(fn)` registers a listener.
  - Tests are in `tests/test_auction.lua`.
- `1e02779`, **confirmation window:** `Confirm.Open(index, sig, row, after)`, `Confirm.Buy()`, `Confirm.Cancel()` and `Confirm.Lines(row, market)`. Tests are in `tests/test_confirm.lua`.

Rows from `Scan.ReadRow(i)` are `{ key, id, name, link, texture, quality, count, minBid, bid, minInc, buyout, unit, owner, high, index }`. `high` was added by the salvaged work; check `scan.lua`.

## Review Focus

1. **A deal for an item with no market value, or with low confidence:** never a below-market deal; it may still be a vendor or materials deal. Tested in Task 1.
2. **A listing whose seller is you:** never a deal, and never buyable from Browse. Tested in Tasks 1 and 2.
3. **Clicking Buy twice quickly:** exactly one `PlaceAuctionBid`. Tested in Task 2 at the UI level.
4. **Find while a full scan runs:** refused with a message; the scan is untouched. Tested in Task 3.
5. **A deal whose listing has gone:** Find marks it gone and removes it from the snapshot, with no buy attempted. Tested in Task 3.

---

### Task 1: Pure deal rules (`deals.lua`)

**Files:** create `TaxTheFools/deals.lua` (in the .toc after `craft.lua`) and `tests/test_deals.lua`.

**Interfaces produced:**
- `Deals.Find(snapshot, ctx, s, me) -> { deal, ... }`, sorted by profit descending.
  - `ctx` comes from `Craft.Context`.
  - `s` is the deal settings table `{ market=bool, vendor=bool, mats=bool, belowMarketPct, minProfit, matPct, minConfidence }`.
  - `me` is the player name, used to exclude your own listings.
- Each deal is `{ key, count, buyout, unit, owner, type = "market"|"vendor"|"mats", profit, pct, market, recipe = name|nil, depositUnknown = bool }`.
- `Deals.ListingProfit(key, count, buyout, ctx, s)` returns `best` (that deal, or nil) for one listing. `Find` loops over the snapshot through it.

**Rules:** spec §4, exactly, including the overlap rule (the type with the highest profit wins) and own listings never counting. Confidence comes from `ctx.market[key].conf`.

**Materials rule:**
- For each captured recipe that uses the item, evaluate the recipe twice: normally, and with the reagent's unit cost overridden to the listing's unit price.
- Add an override hook to `Craft.Evaluate` or `Craft.UnitCost`, for example `ctx.override = { [key] = unit }`, checked first. Keep it pure, and don't break existing craft tests.
- Profit per craft is the difference between the two evaluations; multiply by `floor(count / reagentCount)` and keep the recipe that gives the largest result.

**Required tests (show the arithmetic in comments):**
- **Below market:** triggers at exactly 70%. Not at 71%. Not when confidence is below the minimum. Not when market value is missing. Profit includes the 5% cut and the deposit. `depositUnknown` is set when the vendor sell price is unknown.
- **Below vendor:** triggers when the buyout is under count × vendor sell price, with profit = the difference. Not when the vendor price is unknown.
- **Cheap materials:** a cheap reagent makes a recipe profitable, so profit = gain × crafts covered and the deal names the recipe. With two recipes, the larger profit wins. It doesn't trigger above `matPct`.
- **Overlap:** a listing that is both below market and below vendor appears once, typed by the higher profit.
- **Other:** your own listing is excluded; a type switched off is excluded; results come sorted by profit.

**Commit:** `feat: pure deal rules for below market, below vendor and cheap materials`

### Task 2: Browse Buy and Bid action bar

**Files:** modify `TaxTheFools/ui_browse.lua` and `tests/test_ui.lua` (or a new `tests/test_browse_buy.lua`).

**Behaviour (spec §5, Browse):**
- **Buttons:** an action bar under the Browse list with **Buy** and **Bid** buttons for the selected row.
  - **Labels:** "Buy 1g 20s" (buyout) and "Bid 45s" (`Auction.BidAmount`).
  - **Disabled when:**
    - nothing is selected or `Auction.busy`
    - Buy: no buyout, or the buyout is above `GetMoney()`
    - Bid: the next bid would reach the buyout, or you're the high bidder
    - both: it's your own listing.
  - **Tooltips:** each says why it is disabled.
- **Click:** a click calls `Auction.Buy(row.index, Auction.Sig(row), after)` or `Auction.Bid(...)`.
- **On success:** `after` re-runs the current browse page with `Browse.Search(Browse.query, Browse.page)`.
- **Refreshing:** the bar refreshes on selection change, `Auction.OnChange` and `Scan.OnChange`.
- **No hidden gestures:** no double-click or modifier-click buying.

**Required tests:**
- **Labels and enablement** for each disabled case listed above.
- **Buy click:**
  - It produces exactly one `PlaceAuctionBid` with the buyout.
  - A second click while pending produces none.
  - On a confirmed reply, the page is re-searched.
- **Bid click:** it places `BidAmount`.
- **Above the threshold:** Buy opens the confirmation window and makes no `PlaceAuctionBid`.

**Commit:** `feat: Buy and Bid buttons on the Browse tab`

### Task 3: Deals tab with filter rail, Find and Buy

**Files:** create `TaxTheFools/ui_deals.lua` (in the .toc after `ui_browse.lua`) and `tests/test_deals_ui.lua`. Modify `ui_window.lua` so that `UI.TABS` puts Deals first (Deals, Browse, Crafting), registered via `UI.builders.deals`. If any test assumes Browse is the default tab, keep Browse selected on open, or update that test and explain why in the report.

**Behaviour (spec §5, Deals tab):**
- **Left rail (150 px):**
  - **Switches:** market, vendor and mats.
  - **Sliders:** below-market % (50–95, step 5), minimum profit (0–100000, step 1000, shown as money) and materials % (50–100, step 5).
  - **Dropdown:** minimum confidence (low 0, medium 0.4, high 0.7).
  - **Storage:** settings live in `settings.deals = { market=true, vendor=true, mats=true, belowMarketPct=70, minProfit=5000, matPct=85, minConfidence=0.4 }`; add them to `data.lua` defaults.
- **Banner:** "Deals from a scan N days ago", or the spec's stale text when N ≥ 2, or "No scan yet. Run a full scan." when there's no snapshot.
- **List:** columns Item, Qty, Buyout, Each, Market, %, Profit, Type. Rows come from `Deals.Find` and are recomputed on show, on any rail change and on `Scan.OnChange`.
- **Action bar:**
  - **Find:**
    - Refused while `Scan.Busy()`, with the message from spec §6.
    - Otherwise it starts an exact-name search for the item using the scan engine's browse job. It pages until a row matches the deal by key, count, buyout and owner (owner only when both are known), or the results run out.
    - Paging is automatic: it's a scan, not a buy.
    - **Found:** the bar says "Found on page N" and the button becomes **Buy**, which calls `Auction.Buy(index, sig, after)`.
    - **Not found:** the bar says "Gone", the deal is removed with `Scan.SnapshotRemove`, and the list refreshes.
  - A Find that is located goes stale if any other query replaces the list. Buy must still use `Auction.Match`, which refuses a stale index; that is already built.
- **Implementing the paging:** add a minimal "browse until match" helper to `scan.lua`, such as `Scan.Locate(name, sig, onDone)`. It runs Browse pages 0..N through the existing job machinery, so pacing, retries and the busy lock all apply. It calls `onDone(index|nil, page)` once. Test it in `tests/test_scan.lua`.

**Required tests:**
- **Rows:** come from a seeded snapshot.
- **Rail:** switching off "vendor" removes the vendor deals; raising the minimum profit removes small ones.
- **Banner:** the text for no snapshot, a fresh one, and a stale one.
- **Find:**
  - It locates a listing on page 2, then Buy makes exactly one `PlaceAuctionBid`.
  - On a gone listing it removes the row and makes no `PlaceAuctionBid`.
  - It is refused during a full scan, leaving the scan running.

**Commit:** `feat: Deals tab with filter rail, Find and Buy`

### Task 4: Options, strip width, wiring and the automation guard

**Files:** modify `options.lua`, `tradeskill.lua`, `core.lua` and `tests/test_core.lua` / `tests/test_options.lua` / `tests/test_tradeskill.lua`.

- **Options:** a "Deals & buying" category mirroring the rail (bound to `settings.deals`), plus "Confirm buys at or above" (0–500000 step 10000, shown as money, where 0 means never), bound to `settings.buy.confirmAbove`.
- **Strip width:** strip width = `max(330, text width + 16)`, capped at 600 and recomputed when the text changes. In the fake client `GetStringWidth` is 6 px per character. Test a long text, a short text and the cap.
- **Wiring:** `CHAT_MSG_SYSTEM` and `UI_ERROR_MESSAGE` go to `Auction.OnMessage` through `Core.Safe`, and `Auction.Tick` is called from `Core.Update`. Check what the salvaged commits already wired and add only what's missing.
- **Automation guard:** extend the core test.
  - Set up a full scan whose snapshot is full of obvious bargains, run it to completion through the core, open the Deals page, and press Find on a deal.
  - Assert `PlaceAuctionBid` is never called.
  - Then press Buy and assert it is called exactly once.

**Commit:** `feat: Deals and buying options, wider profit strip, core wiring and automation guard`

### Task 5: Docs and version

**Files:** `docs/testing-checklist.md`, `README.md`, `TaxTheFools/TaxTheFools.toc` and `TaxTheFools/data.lua` (version 0.3.0).

- **Checklist:** add the steps from spec §7.
- **README:** describe buying from Browse and Deals, the confirmation amount, and that Sell and Auctions come next (phase 3b).
- **Version:** bump to 0.3.0 in both files.
- **Commit:** `docs: buying checklist, README and version 0.3.0`
