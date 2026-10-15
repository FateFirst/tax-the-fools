# Tax The Fools: Phase 3b, selling and your auctions

Date: 2026-10-15
Status: approved in conversation, written for review
Parent spec: `docs/superpowers/specs/2026-10-14-tax-the-fools-design.md` (§7 costs, §8 Post and Cancel, §9 Sell and Auctions). Phase 3a (buying) is in `docs/superpowers/specs/2026-10-15-phase3a-buying-design.md`; this phase reuses its action lock and reply handling. This document settles what the parent left open. Where the two disagree, this one wins.

## 1. Decisions

| Topic | Decision |
|---|---|
| Starting bid | `bidPct`% of the buyout (default 90, adjustable), at least 1 copper. |
| Suggested buyout per unit | 1c below (`undercut`, default 1c) the cheapest competing unit price at or above `floorPct`% (default 80) of market. With no such listing, the market value. With no market value, the vendor sell price × 3 (a placeholder, shown in warning colour). With none of those, empty: the user must type a price. |
| Duration | `StartAuction` takes minutes, 120, 480 or 1440, which Turtle shows as 6h, 24h and 72h. Default 480 (`settings.sell.duration`). Labels are hard-coded because the client globals are nil (probe, 2026-10-14). |
| Deposit | The preview uses `CalculateAuctionDeposit(minutes)` with the item in the sell slot, labelled "approx". Aegis_Exchange found the client figure about 0.6× off on Turtle, so the actual deposit is learned from the money lost on a successful post and preferred next time for that item and duration. |
| Posting | One click posts one stack: pick up the stack, `ClickAuctionSellItemButton()`, then `StartAuction(bid, buyout, minutes)`, all inside that click. When no bag stack matches the chosen size exactly, the button reads **Split**, and that click splits one into an empty bag slot (`SplitContainerItem` + `PickupContainerItem`). The next click reads **Post**. |
| Cancelling | One click cancels one auction (`CancelAuction(index)` on the owner list), re-verified first. Cancelling an auction that has a bid asks for confirmation (the deposit is lost and the bidder refunded). |
| Lock | `Auction.busy` from 3a is shared: one buy, bid, post, split or cancel at a time. |

## 2. Actions (`auction.lua`, extended)

All of these run only from a button click (or a confirmation window's button), and each makes one action's worth of calls.

- **`Auction.Split(bag, slot, size)`:**
  - Refuses when the lock is held, or no empty bag slot exists ("No empty bag slot to split into").
  - Otherwise `SplitContainerItem(bag, slot, size)` then `PickupContainerItem(emptyBag, emptySlot)`.
  - No server reply is expected: the result shows on the next `BAG_UPDATE`. The lock isn't taken; the button is just disabled until the bags update.
- **`Auction.Post(bag, slot, stack, bid, buyout, minutes, key)`:**
  - **Refuses when:**
    - the lock is held
    - the bag slot no longer holds `key` × `stack`
    - `buyout` is below `floorPct`% of market without the "allow below floor" override (see §4)
    - `bid` is above `buyout`
    - you can't afford the deposit.
  - **Otherwise:** `ClearCursor()`; if `GetAuctionSellItemInfo()` shows an item in the slot, `ClickAuctionSellItemButton()` then `ClearCursor()` to empty it; then `PickupContainerItem(bag, slot)`, `ClickAuctionSellItemButton()`, `StartAuction(bid, buyout, minutes)`.
  - It takes the lock with `kind = "post"` and records the money before.
- **Replies:**
  - **Post success:** `ERR_AUCTION_STARTED` (CHAT_MSG_SYSTEM; also accepted on UI_ERROR_MESSAGE). Write a posting-log entry, learn the actual deposit (money before − money after), release the lock.
  - **Cancel success:** `ERR_AUCTION_REMOVED`.
  - **Failures:** the existing failure list plus `ERR_AUCTION_LIMITED_DURATION_ITEM`, `ERR_NOT_ENOUGH_MONEY`, `ERR_AUCTION_REPAIR_ITEM` and `ERR_AUCTION_USED_CHARGES`, wherever the client defines the global.
  - **Timeout:** 5 seconds, as before.
- **`Auction.Cancel(index, sig)`:**
  - Refuses when the lock is held, or when owner row `index` no longer matches `sig` (key, count, buyout).
  - If the row has a bid, opens a confirmation first.
  - Otherwise `CancelAuction(index)` with the lock `kind = "cancel"`. On success the owner list is re-requested.

## 3. Pricing and the posting log (`sell.lua`, pure)

- **`Sell.Suggest(listings, market, vendorSell, s)`** returns `{ buyout = perUnit, bid = perUnit, source = "undercut"|"market"|"vendor"|nil, floor = perUnit }`.
  - `listings` are competing `{ unit, count, owner }` entries; your own listings are ignored.
  - `s` holds `{ floorPct, undercut, bidPct }`.
- **`Sell.Stacks(have, stackSize, maxStack)`** returns how many stacks of `stackSize` can be made from the units held (a stack bigger than `maxStack` is clamped).
- **`Sell.Net(buyoutTotal, deposit)`:** `buyoutTotal × 0.95 − deposit`.
- **`Sell.Auctionable(bagItem)`:** false for soulbound items (the tooltip has `ITEM_SOULBOUND`), quest items (`ITEM_BIND_QUEST`), and items whose tooltip says "Conjured" (`ITEM_CONJURED`). Each check runs only where its global exists; the scan tooltip is used.
- **Posting log:** `char.postings`, a list of `{ key, stack, bid, buyout, minutes, deposit, at }`. At most 500 entries are kept, and entries older than 35 days are pruned at login.
- **Learned deposits:** `TaxTheFoolsDB.items[id].dep = { [minutes] = perUnitDeposit }`.

## 4. Sell tab (`ui_sell.lua`)

- **Bag grid (left):**
  - One cell per auctionable item key, combining every bag slot, showing the icon and the total count.
  - Sorted by item name.
  - Refreshes on `BAG_UPDATE`, through the existing inventory throttle.
- **Selecting an item:**
  - Starts a competition search: `Scan.Browse` with the item's name, page 0 only, filtered to the item key.
  - The search is refused while a full or watch scan runs, with the usual message, and the panel then prices from the snapshot instead (spec 3a §3).
- **Pricing panel (right):**
  - **Competition list:** stack, price each, % of market, and "you".
  - **Suggested buyout each** (editable money field) and **starting bid each** (editable). Both show the source ("undercut", "market", "vendor ×3" in warning colour, or "set a price").
  - **Stack size** (1 to the maximum stack, default the maximum or what you hold) and **stacks** (1 to `Sell.Stacks`, default the most possible).
  - **Duration:** three toggles, 6h / 24h / 72h.
  - **Deposit:** the learned value, or "≈ approx" from the client.
  - **After cut:** what you receive.
  - **Floor warning:** when the buyout is below the floor, the warning colour plus "Below your floor (80% of market)". Post is disabled until **Allow below floor** is ticked. This resets per item.
- **Post button:**
  - Reads **Post 1 of N**, **Split**, or disabled with a tooltip reason.
  - After each success it moves to the next stack ("2 of 5 posted").
  - A status line shows the last result.

## 5. Auctions tab (`ui_auctions.lua`)

- **Owner list:** requested with `GetOwnerAuctionItems(0)` when the tab opens and after each cancel or post. It is read on `AUCTION_OWNED_LIST_UPDATE` from `GetNumAuctionItems("owner")` and `GetAuctionItemInfo("owner", i)`. Phase 3b reads only one page: up to 50 of your auctions, which is enough for now; the tab says when there are more.
- **Columns:** Item, Qty, Bid, Buyout, Time left (1 to 4 shown as short / medium / long / very long), Status.
- **Status:** compares your price per unit with the cheapest competing unit price in the snapshot or the latest browse for that key.
  - **Undercut** (red): someone is cheaper, and their price is shown.
  - **Cheapest** (green).
  - **No competition** (dim).
- **Summary:** "N active auctions".
- **Cancel button:** acts on the selected row. It shows a confirmation when the auction has a bid.

## 6. Options

The **Selling** category: starting bid % (50–100, step 5), price floor % (50–100, step 5), undercut amount (1c to 1g, shown as money), and default duration (dropdown).

## 7. Testing

- **Fake client additions:**
  - `ClickAuctionSellItemButton` / `GetAuctionSellItemInfo`: the cursor and sell-slot model.
  - `StartAuction(minBid, buyout, minutes)`: arguments checked, deposit taken, `ERR_AUCTION_STARTED` fired, owner list updated.
  - `CalculateAuctionDeposit(minutes)`.
  - `CancelAuction(index)` and `ERR_AUCTION_REMOVED`.
  - `GetOwnerAuctionItems(page)`, `AUCTION_OWNED_LIST_UPDATE` and the `"owner"` list type.
  - `SplitContainerItem` / `PickupContainerItem` / `ClearCursor` / `GetContainerItemInfo` with a cursor.
  - Wrong argument types error, as the real client does.
- **`sell.lua` units:**
  - undercut chosen from listings above the floor
  - your own listings ignored
  - only listings below the floor, so the market value is used
  - no market, so vendor × 3
  - nothing, so empty
  - bid percentage and the 1c minimum
  - `Stacks`, `Net` and `Auctionable`
  - log capping and pruning.
- **Engine:**
  - Post makes the exact call sequence, logs, and learns the deposit.
  - Refusals (slot changed, below floor, bid above buyout, can't afford, lock held) make no `StartAuction`.
  - Split with an empty slot, and with none.
  - Cancel re-verifies; cancelling with a bid confirms first.
  - Success, failure and timeout all release the lock.
- **UI:**
  - The grid shows only auctionable items.
  - Selecting runs the competition search.
  - Suggested price and labels.
  - The Split, then Post flow.
  - "2 of N" after a post.
  - The floor override.
  - Auctions rows with undercut and cheapest status.
  - Cancel.
- **Automation guard:** opening Sell and Auctions, selecting items and running searches never calls `StartAuction`, `CancelAuction`, `SplitContainerItem` or `PlaceAuctionBid`. Only the simulated clicks do, once each.
- **In-game checklist:**
  - post one stack
  - split, then post
  - post several stacks
  - a price below the floor is blocked until allowed
  - cancel an auction
  - the undercut colours
  - the learned deposit versus the preview.
