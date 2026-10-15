# Tax The Fools: Phase 6, profit ledger and price trends

Date: 2026-10-15
Status: approved in conversation, written for review
Builds on:
- phase 3a/3b's action engine (`auction.lua`)
- phase 4's sales (`sales.lua`, `mail.lua`)
- phase 5b's mailbox (`mailbox.lua`)
- the price history (`price.lua`: `entry.days[day] = { p25, min, n, ... }`, kept `D.KEEP_DAYS` = 60 days).

Where this document and an earlier one disagree, this one wins.

## 1. Decisions

| Topic | Decision |
|---|---|
| What counts | **Gold in:** AH sales (from mail), vendor sales, and money from other players' mail. **Gold out:** AH buyouts, won bids, posting deposits, vendor spending (including repairs), and money mailed to other players. |
| Transfers | Money moved between your own characters (any character on the realm in `DB.Realm().chars`) is recorded as a transfer, shown on its own, and left out of profit. |
| Deposits | Counted when paid, at the post. A sale's mail money already includes the returned deposit, so expired and cancelled auctions need no extra entry. |
| Bids | A bid is not spending. The amount is remembered as a pending bid; when the "Auction won" mail is recorded, the newest pending bid for that item name becomes a "bid" entry. An outbid mail removes the pending bid. Pending bids older than 7 days are dropped. |
| Backfill | On first load after the update, each character's existing `char.sales` sold entries are added as sale entries (once, behind a flag), so the ledger doesn't start empty. |
| Trend | Compare the median daily p25 of the last 7 days (days 0–6) with the 7 before (days 7–13). Each side needs at least 3 days. The change is `(recent − prior) / prior`. Below 5% either way is "steady", otherwise "rising" or "falling". |
| Chart | 30 days, one bar per day that has a p25, scaled from 0 to the window's maximum, with today's market value drawn as a line. |

## 2. Ledger rules (`ledger.lua`, pure)

- **Storage:** `char.ledger` is a list of `{ at, kind, amount, key, qty, who }`. `kind` is one of:
  - `"sale"`, `"buy"`, `"bid"`, `"deposit"`
  - `"vendorIn"`, `"vendorOut"`
  - `"mailIn"`, `"mailOut"`, `"transferIn"`, `"transferOut"`.

  `amount` is a positive copper amount.
- **`Ledger.Add(char, entry, now)`** appends the entry, ignores amounts ≤ 0, and caps the list at 5000 entries (dropping the oldest).
- **`Ledger.Prune(char, now)`** drops entries older than 180 days.
- **`Ledger.Sign(kind)`** is +1 for in, −1 for out, and 0 for transfers.
- **`Ledger.Totals(chars, days, now, who)`** returns `{ inn, out, net, perDay, transferIn, transferOut, byKind = {...} }` across the realm's characters, or just character `who`.
- **`Ledger.Days(chars, days, now, who)`** returns one row per calendar day with any entries, newest first. Each row is `{ day, sale, buy, deposit, vendor (net of in/out), mail (net), net }`.
- **`Ledger.ByItem(chars, days, now, who)`** returns one row per `key` with `{ key, income (sales), spend (buys + bids + deposits), net, sold qty, bought qty }`, sorted by net descending.
- **`Ledger.Backfill(char)`:** if `char.ledgerBackfilled` isn't set, it adds a `sale` entry for each `char.sales` entry with outcome `"sold"` (amount = money, key, qty, at), then sets the flag.
- **`Ledger.PendingBid(char, name, amount, now)`**, **`Ledger.BidWon(char, name, now)`** and **`Ledger.BidLost(char, name)`** manage `char.pendingBids`, a list of `{ name, amount, at, key }`.

## 3. Hooks

All hooks are wired through `Core.Safe`. None of them makes a game action call; they only record.

- **`auction.lua` finish:**
  - A successful **buy** adds `buy` with the buyout, key and count.
  - A successful **bid** calls `Ledger.PendingBid` with the item name and amount.
  - A successful **post** adds `deposit` with the deposit actually paid (`Sell.LearnDeposit` already works it out). If that is unknown, it uses the deposit preview; if that is also unknown, nothing is added.
- **`mail.lua`:** when `Sales.Record` records a `won` result, call `Ledger.BidWon`, which turns the newest pending bid for that name into a `bid` entry. An `outbid` result calls `Ledger.BidLost`. A `sold` result adds a `sale` entry, using the same money and qty as the sales entry.
- **Vendor:** while a merchant window is open (from `MERCHANT_SHOW` to `MERCHANT_CLOSED`), each `PLAYER_MONEY` change is recorded as `vendorIn` or `vendorOut` by its sign. This only happens when `settings.ledger.vendor` is on (the default).
- **Mailbox (`mailbox.lua`):**
  - A confirmed `TakeInboxMoney` from a non-AH mail is recorded as `transferIn` when the sender is one of your realm characters, otherwise `mailIn`. AH money is already covered by sales.
  - A successful send with money is recorded as `transferOut` or `mailOut` the same way.
  - Postage is recorded as `mailOut`.
- **Login:** `Ledger.Prune` and `Ledger.Backfill` run at login.

## 4. Ledger tab (`ui_ledger.lua`)

- **Where:** an AH window tab, "Ledger", after History. It can also be opened as a standalone window with `/ttf ledger`, reusing the Crafting-window pattern.
- **Header filters:** period (7 / 30 / 90 days, default 30) and character (all or one), the same pattern as History.
- **Totals strip:** "In X  -  Out Y  -  Net Z (W/day)  -  Transfers +A / -B". Net uses the good or bad colour. Use plain ASCII separators.
- **Two views,** picked with a toggle:
  - **Days:** columns Date, Sales, Buys, Deposits, Vendor, Mail, Net.
  - **Items:** columns Item, Income, Spend, Net, Sold, Bought.
- An empty state explains that the ledger records from now on, apart from past sales.

## 5. Trends (`price.lua`, `tooltip.lua`, `ui_browse.lua`, `ui_sell.lua`)

- **`P.Trend(entry, today)`** returns `{ pct, dir = "rising"|"falling"|"steady", recent, prior }`, or nil, following §1.
- **`P.Series(entry, today, days)`** returns a list of `{ day, p25 }` for the last `days` days, oldest first, with gaps left out.
- **Tooltip:** "Trend 7d: +12% rising", toggled by `settings.trend.tooltip` (default on). Rising and falling use the good and bad colours.
- **Browse:** a "Trend" column (width 56, not flex) showing "+12%", "-8%", "0%" or "-", sortable.
- **Chart widget** (`W.Chart(parent, w, h)` in `widgets.lua`):
  - `chart:SetSeries(series, marker)` draws up to 30 bars using solid textures, plus a horizontal line at `marker` (the market value).
  - It is empty when there are no points.
  - Hovering a bar shows a tooltip with the date and price.
- **Where the chart shows:**
  - **Browse:** in the bottom bar area when a row is selected, sized to fit the existing layout.
  - **Sell:** in the pricing panel, under the competition list.
  - If space is too tight at the minimum window size, the chart hides rather than overlapping anything.

## 6. Options

- **Ledger** category: "Count vendor buys and sales" (`settings.ledger.vendor`, default on).
- **Tooltip** category, or the existing tooltip options: "Price trend line" (`settings.trend.tooltip`, default on).

## 7. Testing

- **Ledger units:**
  - Add, the cap, and Prune
  - signs and totals, including transfers
  - Days and ByItem
  - Backfill running only once
  - pending bid → won (the bid entry) / outbid (removed) / expiry after 7 days.
- **Hooks:**
  - a buy, a bid then a won mail, a post deposit
  - merchant money in and out (with vendor off, nothing is recorded)
  - mail money from an alt (a transfer) and from a stranger (mailIn)
  - a send with money to the alt
  - the automation guard is unchanged: the hooks make no new game action calls.
- **Trend units:** rising, falling and steady; too few days; a gap; `Series` order.
- **UI:**
  - Ledger tab totals, the two views and filters, the empty state, `/ttf ledger`
  - the tooltip trend line, on and off
  - the Browse Trend column
  - the chart drawing N bars and the marker, empty with no data, hidden when too small.
- **In-game checklist:**
  - buy something, post something, bid and win something, sell to a vendor
  - mail gold to the alt and check it shows as a transfer, not profit
  - Ledger totals look right
  - trend line on a few items
  - the chart on Browse and Sell.
