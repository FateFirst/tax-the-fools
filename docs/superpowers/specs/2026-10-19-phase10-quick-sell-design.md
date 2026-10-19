# Tax The Fools: Phase 10, Quick sell

Date: 2026-10-19
Status: agreed in conversation, written for review

## 1. Intent

The user's bank alt carries items in its bags only to sell them: new stock, or auctions that came back expired. Relisting today means, for each item, selecting it on the Sell tab, waiting for its price search, and then clicking Post. The user wants one button that they click again and again, posting one stack per click, with no selecting in between.

Ravencraft bans automating character actions. The user's own rule (since phase 1) is that only AH scan paging runs without a click, and every post is exactly one click. Quick sell keeps to that rule: the price scan runs by itself, and each post is one click.

## 2. Goals, non-goals, anti-goals

**Goals**
- One click scans prices for everything auctionable in the bags.
- A list then shows one row per bag slot with its suggested price.
- One button, **Post next**, posts the highlighted row and moves the highlight to the next postable row by itself. The user keeps clicking the same button until the list is done.
- Full stacks post at their size (for example 20 Runecloth). Odd amounts (1, 2, 7) post as they sit in the bag. Leftovers need no second scan.

**Non-goals**
- Splitting or merging stacks. Each bag slot is posted as it is.
- Replacing the Bags, Repost or Stock views. They stay unchanged.
- Pricing by hand inside Quick sell. Items that need a manual price are posted from the normal Bags view.

**Anti-goals (a failure even if it works)**
- One click causing more than one `StartAuction`, or any post happening without a click.
- Having to select a row before each Post.
- Posting below the user's floor.

## 3. Decisions made in conversation

| Topic | Decision |
|---|---|
| Where | A fourth view on the Sell tab, **Quick**, beside Bags / Repost / Stock. |
| Rows | One row per bag slot that `Sell.Auctionable` accepts (not soulbound, quest or conjured). The stack is the slot's count. |
| Scan | A **Scan bags** button. One click starts a scan of exact-name queries, one per distinct item in the bags, which pages automatically like the other scans. It is the only part that runs by itself. |
| Price | `Sell.Suggest` per item, with that item's listings from this scan, the market value, the vendor price and the user's sell settings (floorPct, undercut, bidPct). Price is per unit; the post is unit × stack. All rows of one item share its price. |
| Below floor | `Sell.Suggest` never goes below the floor. When the suggested buyout lands on the floor because another seller's listing is at or below it (listings under the floor were ignored, or the undercut was clamped), the row posts at the floor and is marked "at floor" so the user can skip it. *Builder's call, made by Claude:* `Suggest` gains a field saying it clamped to the floor, rather than the UI re-deriving it. |
| No price | A row whose item has no listings, no market value and no vendor price shows "no price". Post next passes over it; the user prices it on the Bags view. |
| Vendor-priced items | An item with no listings and no market value is priced at its vendor sell price × a multiple, and its row is marked "vendor ×3" (with the multiple shown). A checkbox in the Quick view, **Include vendor-priced items**, decides whether Post next posts these rows or passes over them. Beside it, a number box sets the multiple, default 3. *(The user's decision.)* Both are saved settings (`settings.sell.quickVendor`, default off, and `settings.sell.vendorMult`, default 3) and also appear on the Options window's Selling page with hints. *(Claude's calls: off by default, so nothing is posted at a guessed price until the user opts in; one multiple shared with the Bags view's existing vendor suggestion, which today is a fixed 3.)* |
| Duration | Starts at the Sell default (`settings.sell.duration`). The Quick view's picker changes it for the whole list only; it doesn't change the setting or the Bags view. *(Claude's call.)* |
| Row order | By item name, then the bigger stack first, so one item's stacks post one after another. *(Claude's call.)* |
| Post next | Posts the highlighted row with `Auction.Post` (its existing checks: bag still holds key × stack, floor, deposit). One click → at most one `StartAuction`. |
| After a post | On the server's success reply, the row is marked Posted and the highlight moves to the next postable row. While waiting for the reply, the button reads "Waiting..." and does nothing. |
| A failed post | The row is marked Failed with the reason (for example "Your bags changed" or "Not enough money for the deposit"), and the highlight moves on, so the user can keep clicking. |
| Skip | A Skip button moves the highlight past the current row without posting it. Clicking a row makes it the next one. |
| Selling one-click rule | Unchanged. The automation guard test (no `StartAuction`, `PlaceAuctionBid` or `CancelAuction` without a click) is extended to the Quick view. |

## 4. The screen

The Quick view sits in the Sell tab's main area, at the existing minimum window size of 660 × 380.

- **Top bar:** Scan bags, the scan's progress ("Scanning 3 of 11...") or its time ("Prices from 2m ago"), and the duration picker.
- **List columns:** item (icon and name), stack, unit price, total buyout, and a status column: blank, "at floor", "no price", "Posted", "Failed: reason", "Skipped".
- **The highlighted row** is the next to be posted. Rows that are Posted, Failed, Skipped or "no price" are never highlighted by Post next.
- **Bottom bar:** **Post next** (large, the main button), Skip, and a summary such as "5 of 12 posted, 3,420g".
- Before the first scan, the list shows the bag rows with "scan for prices" in place of a price, and Post next is disabled.

## 5. Behaviour details

- Only a scan started by Scan bags fills Quick's prices. A full scan or a Browse search doesn't. *(Claude's call.)*
- The list is built when the scan finishes, from the bags at that moment. A paused scan (for example the AH closed) builds nothing until it is resumed and finishes. An item whose query got no reply in this scan shows "not scanned" and is passed over, so no price silently comes from old data. An item whose query was answered with no listings uses the market value, as the Bags view does. *(Claude's call.)* A rescan rebuilds it and clears every status.
- A bag change after the scan doesn't rebuild the list. A row whose slot changed fails on its own click with `Auction.Post`'s "Your bags changed. Pick the item again.", and the rest stay usable.
- The scan uses the existing scanner (`Scan.Start` with name queries, collecting rows through `Scan.OnRows`). The Quick view must not start a scan while another scan runs, and says why.
- Posting from Quick logs postings, learns deposits and feeds the Ledger exactly like a post from the Bags view, because it uses the same `Auction.Post` path.
- With the window closed, or the AH closed, Quick does nothing and keeps its list until the next scan.

## 6. Left to the builder

- How the view is split across `ui_sell.lua`, `ui_stock.lua` or a new `ui_quick.lua`, within the 32-upvalue limit.
- Exact layout, column widths and colours, consistent with the existing views.
- Whether the pure rules (rows from bags, price per item, the next-row choice) live in `sell.lua`, `stock.lua` or a new `quick.lua`. They must be testable without the UI.
- The version: 0.12.0.

## 7. Testing

- **Pure rules:** one row per slot, stacks as in the bag, excluded items, price shared per item, "at floor" when cheaper listings sit below the floor, "no price", and the next-row choice skipping Posted, Failed, Skipped and no-price rows.
- **UI with the fake client:** Scan bags runs a scan and fills prices. Each Post next click calls `StartAuction` once. The highlight moves only after the success reply. A failure marks the row and moves on. Clicking while waiting does nothing. A rescan clears statuses. Leftover odd stacks post without a second scan.
- **Automation guard:** the Quick view never calls `StartAuction` outside a click.
- **Window size:** nothing is cut off at 660 × 380.
- **Manual checklist:** add a Quick sell section to `docs/testing-checklist.md`.
