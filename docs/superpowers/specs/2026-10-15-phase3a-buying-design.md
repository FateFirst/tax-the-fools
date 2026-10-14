# Tax The Fools: Phase 3a, buying from our window

Date: 2026-10-15
Status: approved in conversation, written for review
Parent spec: `docs/superpowers/specs/2026-10-14-tax-the-fools-design.md` (§7 deals, §8 actions, §9 UI). This document settles what the parent left open for buying. Where the two disagree, this one wins.

Phase 3 is split in two:
- **3a, buying (this document):** Browse Buy/Bid, the Deals tab, confirmation and the action lock.
- **3b, selling:** the Sell and Auctions tabs and posting/cancelling.

## 1. Decisions

| Topic | Decision |
|---|---|
| Order | Buying first (3a), then Sell and Auctions (3b). |
| Confirmation | A buy whose total buyout is at or above `settings.buy.confirmAbove` (default 50000 copper = 5g; 0 switches confirmation off) opens a themed confirmation window. Below that, one click buys. Bids are never confirmed: a bid is not a purchase until the auction ends. |
| Deal types in 3a | Below market, below vendor and cheap materials. "Undersupplied" needs sales history, so it comes in phase 4. |
| Deal source | A listing snapshot saved by each full scan and refreshed by watchlist scans (§3). Deals can be browsed without the AH open; buying needs it open. |
| Buying a deal | Two clicks when the listing isn't on the current page. **Find** runs a targeted exact-name scan (scanning is allowed to be automatic). Once the listing is located, the button becomes **Buy** (subject to confirmation). |
| Action control | One shared action bar under each list acts on the selected row, rather than a button per row. |
| Profit strip | The tradeskill profit strip widens to fit its text (user feedback from phase 2). |

## 2. Action engine (`auction.lua`)

**Rule:** `PlaceAuctionBid` is only ever called from a button's OnClick, or from the confirmation window's Buy OnClick, and at most once per click. A test enforces this.

**The lock:** `Auction.busy` holds one pending action: `{ kind = "buy"|"bid", key, count, amount, at }`. It is released by:
- **Success:** a system message equal to `ERR_AUCTION_BID_PLACED` ("Bid accepted."). It may arrive as `CHAT_MSG_SYSTEM` or `UI_ERROR_MESSAGE`, so both are listened for and compared against the global string.
- **Failure:** an error equal to any of `ERR_NOT_ENOUGH_MONEY`, `ERR_ITEM_NOT_FOUND`, `ERR_AUCTION_HIGHER_BID`, `ERR_AUCTION_BID_OWN`, `ERR_AUCTION_DATABASE_ERROR` or `ERR_AUCTION_RESTRICTED_ACCOUNT`, matched only where the global exists. The message is shown on the status strip.
- **Timeout:** 5 seconds without either, shown as "no reply from the auction house".

While the lock is held, Buy, Bid and Find buttons are disabled.

**Verifying a listing:** `Auction.Match(index, sig)` re-reads row `index` of the current `"list"` page and compares item key, count, buyout and owner. The owner is compared only when both sides know it. On a mismatch the action is refused with "Listing changed. Search again." and no server call is made.

**Buy:** `Auction.Buy(index, sig)`:
- verify the listing
- check affordability against `GetMoney()`
- if the buyout is at or above the confirmation amount, open the confirmation window and return
- otherwise call `PlaceAuctionBid("list", index, buyout)`.

**Bid:** `Auction.Bid(index, sig)`:
- verify the listing
- amount = `bid > 0 and bid + minIncrement or minBid`
- refuse if a buyout exists and the amount is at or above it ("use Buy")
- refuse if the player is already the high bidder (the 11th return of `GetAuctionItemInfo`)
- otherwise call `PlaceAuctionBid("list", index, amount)`.

**After a successful buy or bid,** the page that was showing is searched again: a browse re-query, or the deal item's search. A query is allowed to be automatic. Bought listings leave the snapshot.

**Confirmation window:** a themed `W.Window` showing:
- the item in its quality colour, the quantity and the total price
- price per unit, market value and % of market
- **Buy** and **Cancel**.

Buy re-verifies with `Auction.Match` before calling `PlaceAuctionBid`. If the listing changed while the window was open, it refuses. Escape cancels.

## 3. Listing snapshot

Stored as `realm.snapshot = { at = time(), day = day, rows = { [key] = { "count|buyout|minBid|owner", ... } } }`.

- **Full scan:** at finish, the snapshot is rebuilt from that scan's listings. Only listings with a buyout are kept, since deals are buyouts.
- **Watchlist scan:** replaces `rows[key]` for every key it saw.
- **Browse:** never touches the snapshot. A browse sees one page, not the whole market.
- **Size:** about 8.5k listings of about 25 bytes each, roughly 200 KB in SavedVariables. That's acceptable. The snapshot is replaced, never appended to.
- **Removal:** a listing found gone by Find, or bought, is removed from its row list.
- **Stale snapshots:** with `day` older than 2 days, the Deals tab shows a banner: "Deals are from a scan N days ago. Run a full scan for fresh deals."

## 4. Deal rules (`deals.lua`, pure)

`Deals.Find(snapshot, ctx, settings) -> { deal, ... }`, where each deal is:

```lua
{ key, count, buyout, unit, owner, type = "market"|"vendor"|"mats", profit, pct, market, recipe = name|nil }
```

`ctx` is `craft.lua`'s evaluation context (market, items, recipes, holdings). The rules are the parent spec §7, with these values:

- **Below market (`market`):**
  - triggers when `unit <= belowMarketPct/100 × market`, the confidence is at or above `minConfidence` (default 0.4, "medium"), and profit is at least `minProfit`
  - profit = `count × market × 0.95 − buyout − deposit`, where `deposit` is the parent spec's Turtle formula for a stack of `count` at 480 minutes; when the vendor sell price is unknown, the deposit is 0 and the deal is flagged `depositUnknown`.
- **Below vendor (`vendor`):**
  - triggers when the vendor sell price is known and `buyout < count × vendorSell`, with profit at least 1 copper
  - profit = `count × vendorSell − buyout`.
- **Cheap materials (`mats`):**
  - applies when the item is a reagent in any captured recipe and `unit <= matPct/100 × market` (default 85%)
  - for each such recipe, re-evaluate it with this reagent's unit cost replaced by `unit`
  - `gain = newProfit − oldProfit` per craft
  - crafts covered = `floor(count / reagentCount)`
  - profit = `gain × crafts covered`, using the recipe with the largest profit
  - triggers when profit is at least `minProfit`.
- **Overlaps:** one listing may qualify for several types. It is listed once, under the type with the highest profit.
- **Your own listings** (owner equals the player's name) are never deals.
- **Defaults:** `belowMarketPct` 70, `minProfit` 5000 copper (50s), `matPct` 85, `minConfidence` 0.4, and every type enabled.

## 5. Interface

- **Browse:**
  - The action bar under the list shows **Buy** "Buy 1g 20s" and **Bid** "Bid 45s" for the selected row. Each is disabled when not applicable (no buyout, own auction, lock held, can't afford). Their tooltips explain why.
  - Double-clicking a row does nothing. There are no hidden buy gestures.
- **Deals tab:** a new tab, before Browse.
  - **Left rail (150 px):** a switch for each type, sliders for below-market %, minimum profit (0 to 10g in 10s steps) and materials %, plus a minimum-confidence dropdown (low, medium or high).
  - **Banner:** shows the snapshot's age, or that it is stale.
  - **List columns:** Item, Qty, Buyout, Each, Market, %, Profit, Type. Mats rows put the recipe name in the type column tooltip. The list is sorted by profit, descending.
  - **Action bar:**
    - **Find** searches for the selected deal's item, following its pages until the listing is located or the results run out.
    - **Buy** appears once the listing is found and acts on the located index. If the listing isn't found, the row says "gone" and is removed.
    - The bar's text says what is happening: "Searching…", "Found on page 2", or "Gone".
- **Confirmation window** as in §2.
- **Options:** a new **Deals & buying** category containing the deal settings (mirroring the rail) and "Confirm buys at or above" (0 to 50g, step 1g; 0 means never).
- **Tradeskill strip:** width = `max(330, text width + 16)`, capped at 600. It is recomputed whenever the text changes.

## 6. Error handling

- Any refusal (listing changed, can't afford, lock held, own auction, bid at or above the buyout) is a message on the status strip and in chat. It never makes a server call.
- If Find is clicked while a full scan is running, the full scan pauses, as Browse does. Find is refused with "A scan is using the auction house. Pause it to search."
- Nothing in this phase calls `PlaceAuctionBid` except `Auction.Buy`, `Auction.Bid` and the confirmation window's Buy. Each of those runs from a click.

## 7. Testing

- **Fake client:**
  - `PlaceAuctionBid` deducts money, removes the listing (for a buyout), and fires `CHAT_MSG_SYSTEM` with `ERR_AUCTION_BID_PLACED`.
  - Switches can make it fire an error instead (not enough money, item not found) or no reply at all.
  - The 11th return of `GetAuctionItemInfo` (high bidder) is modelled.
- **`deals.lua` units:**
  - each type's trigger and profit, with arithmetic shown
  - the confidence filter
  - the own-auction exclusion
  - an overlap resolved by highest profit
  - mats profit using the recipe with the largest profit
  - the unknown-deposit flag.
- **`auction.lua` units:**
  - match and mismatch (refused, with no `PlaceAuctionBid`)
  - can't afford
  - the lock: a second click while pending makes no call, and the lock releases on success, on error and on timeout
  - the bid refused at or above the buyout, and refused when you're the high bidder
  - the confirmation path: above the threshold, the first click makes no `PlaceAuctionBid` and the window's Buy makes exactly one
  - a threshold of 0 never confirms.
- **Snapshot:** a full scan builds it, a watchlist scan replaces its keys, and a browse leaves it untouched. Removal after a buy, the stale banner, and the size of the stored format.
- **UI:**
  - Browse Buy and Bid enablement and labels
  - Deals list contents and sorting
  - Find locating a listing on page 2, then Buy
  - Find marking a listing gone
  - the rail switches filtering the list.
- **Automation guard:** finishing a full scan with obvious bargains, opening Deals, and pressing Find must never call `PlaceAuctionBid`. Only the simulated Buy click does, exactly once.
- **In-game checklist:**
  - buy a cheap item from Browse
  - bid on something
  - buy above the threshold, confirming it
  - Find then Buy a deal
  - try a deal that has gone
  - check the strip width.
