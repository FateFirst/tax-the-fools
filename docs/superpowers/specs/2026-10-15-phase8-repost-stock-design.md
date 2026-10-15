# Tax The Fools: Phase 8, repost list and stock view

Date: 2026-10-15
Status: approved in conversation, written for review

Builds on:
- **Sell tab** (`ui_sell.lua`): the bag grid on the left, the pricing panel on the right, and one-click Post.
- **Results and stats** (`sales.lua`): `char.sales` holds the results, including expired and cancelled ones with `key` and `at`; `Sales.StatsAll` gives the stats.
- **Posting log** (`char.postings`): `{ key, stack, bid, buyout, minutes, at, done }`.
- **Holdings** (`inventory.lua`): `char.bags` and `char.bank` give counts per key for each character.
- **Market and trends** (`price.lua`).

Where this document and an earlier one disagree, this one wins.

## 1. Decisions

| Topic | Decision |
|---|---|
| Where | The Sell tab gets a three-way switch: **Bags** (today's grid), **Repost** and **Stock**. Bags and Repost keep the pricing panel on the right. Stock uses the whole page. |
| Repost | Lists items in this character's bags that have an expired or cancelled result in the last `settings.sell.repostDays` days (default 7). |
| Repost click | Selects the item in the pricing panel, exactly as clicking it in the grid does. The stack size is set to the most recent posting's stack for that key, when the bags still hold that many. Posting stays one click per stack. |
| Stock scope | Everything the realm's characters hold in bags and bank, plus what is on the AH (open postings in `char.postings` with no `done`, summed by stack). Mail contents are not counted, because they can't be read without opening mail. The view says so. |
| Value | Count × market value (`DB.Realm().market[key].v`). An item with no market value shows "-" and adds nothing to the total. |

## 2. Pure rules (`stock.lua`)

### `Stock.Repost(char, bagCounts, items, market, days, now)`

Returns one row per key, sorted by name:

```
{ key, name, have, lastStack, lastBuyout (per unit), lastAt, outcome = "expired"|"cancelled", suggest (per unit) }
```

- **Which keys:** keys with `have = bagCounts[key] > 0` and a `char.sales` entry with outcome expired or cancelled, where `at >= now − days·86400`.
- **lastStack, lastBuyout:** from the newest posting for the key in `char.postings`, done or not.
- **suggest:** today's market value per unit, or nil.

### `Stock.Rows(chars, market, statsByKey, trendFn)`

Returns one row per key held anywhere, sorted by value descending with unvalued rows last:

```
{ key, name, bags, bank, onAH, total, perChar = { { name, bags, bank, onAH } }, unit, value, rate, trend }
```

- **onAH:** the stacks of open postings, summed per character.
- **rate:** the sell rate from `statsByKey[key].rate`.
- **trend:** `trendFn(key)`, the percent from `P.Trend`.

### `Stock.Total(rows)`

Returns `{ items = number of keys, units, value }`.

## 3. UI (`ui_sell.lua`)

### View switch

- A **Bags | Repost | Stock** switch sits at the top of the left area. It reuses the switch pattern from `ui_craft.lua`.
- The last view used is kept in `TaxTheFoolsCharDB`.

### Repost view

- A list replaces the grid, with columns Item, Have, Last price, Now, and Change (+x% or −x%, coloured).
- Clicking a row selects the item in the pricing panel, with the stack preset described in §1.
- **Empty state:** "Nothing came back from the auction house in the last N days."

### Stock view

- A full-width list with columns Item (flex), Bags, Bank, On AH, Total, Each, Value, Sells, Trend.
- Hovering a row shows a tooltip breaking down each character's bags, bank and on-AH counts.
- **Totals strip:** "N items  -  X units  -  worth ~Yg  (not counting mail)".
- The list refreshes on bag and bank updates, scans and posts.

### Layout

- Everything fits the AH window's minimum size of 660×380. The Stock columns sum to at most the list width there, which needs a fit test.
- Plain ASCII.

### Options

- In the Selling category: "Repost list covers" (`settings.sell.repostDays`, 1–30, default 7), with a hint.

## 4. Testing

- **`Stock.Repost`:**
  - expired and cancelled results inside the window
  - outside the window
  - not in bags
  - the last posting's stack and price
  - no posting
  - sort order.
- **`Stock.Rows`:**
  - bags and bank across two characters
  - on AH from open postings only (done ones excluded)
  - value and unvalued rows last
  - the perChar breakdown
  - rate and trend passed through
  - `Total`.
- **UI:**
  - the switch and the remembered view
  - Repost rows and a click selecting the item with the stack preset
  - the Repost empty state
  - Stock rows, the tooltip and totals
  - the fit test at 660
  - the options binding and hint.
- **Automation guard:** opening, switching views and clicking Repost rows never calls `StartAuction`. Only the Post click does.
- **In-game checklist:**
  - let an auction expire and collect it, then check it appears in Repost and reposts in one click per stack
  - Stock totals match the bags, bank and AH across characters
  - the tooltip breakdown.
