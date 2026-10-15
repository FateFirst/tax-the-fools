# Tax The Fools: Phase 4, sales tracking

Date: 2026-10-15
Status: approved in conversation, written for review
Parent spec: `docs/superpowers/specs/2026-10-14-tax-the-fools-design.md` (§7 undersupplied, §10 sales tracking). This phase builds on phase 3b's posting log (`char.postings`) and Sell tab. Where this document and the parent disagree, this one wins.

## 1. Decisions

| Topic | Decision |
|---|---|
| Mail access | Read headers only (`GetInboxHeaderInfo`). Never call `GetInboxText`, `GetInboxInvoiceInfo`, `TakeInboxMoney`, `TakeInboxItem`, `DeleteInboxItem` or `ReturnInboxItem`. Opening mail or reading invoices marks mail read and shortens its expiry. Collecting mail is left to TurtleMail. |
| Sell tab | Shows the selected item's sell rate, average time to sell and average sale price per unit, with a warning when the buyout per unit is above `warnPct`% (default 120) of the average sale price. The suggested price is unchanged. |
| Undersupplied deals | The deal type from the parent spec §7, now that sales history exists. It is a sell suggestion with a **Sell** action that opens the Sell tab on the item; never a Buy. |
| Right-click from bags | With our AH window shown and no modifier keys held: on the Browse tab, a right-click on a bag item searches for it; on the Sell tab, it selects the item. Otherwise the click goes through to the game unchanged. It can be switched off in options. |

## 2. Reading mail (`mail.lua`)

- **Events:** `MAIL_SHOW` and `MAIL_INBOX_UPDATE` set a dirty flag. An OnUpdate tick handles it at most once per frame, because the update event fires many times on first open.
- **Per mail:** for `i = 1..GetInboxNumItems()`, read `GetInboxHeaderInfo(i)`. In 1.12 that returns `packageIcon, stationeryIcon, sender, subject, money, CODAmount, daysLeft, hasItem, wasRead, wasReturned, textCreated, canReply, isGM`.
- **Classifying the subject:** `Sales.Classify(subject)` turns the client globals into search patterns:

  | Global | Outcome |
  |---|---|
  | `AUCTION_SOLD_MAIL_SUBJECT` | sold |
  | `AUCTION_EXPIRED_MAIL_SUBJECT` | expired |
  | `AUCTION_REMOVED_MAIL_SUBJECT` | cancelled |
  | `AUCTION_WON_MAIL_SUBJECT` | won |
  | `AUCTION_OUTBID_MAIL_SUBJECT` | outbid |

  The probe showed the strings: "Auction successful: %s", "Auction expired: %s", "Auction cancelled: %s", "Auction won: %s" and "Outbid on %s". Escape the pattern's magic characters, then replace `%s` with `(.+)`. The result is `outcome, itemName` or nil.
- **De-duplication:**
  - Key: `subject .. "|" .. money .. "|" .. floor((time() - daysLeft*86400)/3600)` (the arrival hour, which survives relogs). It is stored per character in `char.seenMail[key] = at`.
  - A key already seen is skipped.
  - `seenMail` is pruned with sales (older than 120 days).
- **Recording:** a new sold, expired or cancelled mail calls `Sales.Record(char, outcome, itemName, money, now)`. Won and outbid are recorded for the History tab but don't affect sell rates.
- **Live chat note:** `CHAT_MSG_SYSTEM` equal to `ERR_AUCTION_SOLD_S` with the item name substituted puts a status note ("Sold: X") on the AH strip, or in chat. It doesn't record anything.

## 3. Matching sales to posts (`sales.lua`, pure)

- **`Sales.Record(char, outcome, itemName, money, now, items)`:**
  - Resolves the item key by name (`items`, like `I.FindByName`).
  - **Sold:** looks for open postings for that key (`char.postings` entries not yet consumed). The match is unambiguous when exactly one stack/buyout combination satisfies `abs(money − floor(buyout × 0.95)) <= 1 + (deposit or 0)`. Matching entries share the same stack and buyout, so any of them may be consumed; take the oldest.
    - **On a match:** consume that posting (`p.done = outcome`) and record `{ key, outcome, money, qty = stack, unit = buyout/stack, secs = now − p.at, at = now }`.
    - **Otherwise:** record `{ key, outcome, money, at = now }` with `qty` and `unit` nil.
  - **Expired or cancelled:** consume the oldest open posting for the key, if any, and record the outcome. Expired mail carries no money.
- **`Sales.Stats(chars, key, days, now)`** returns `{ sold, expired, cancelled, rate, n, avgUnit, avgSecs, income }` across every character on the realm:
  - `rate = sold / (sold + expired + cancelled)`; nil when the denominator is 0
  - `avgUnit` averages only the sales whose quantity is known
  - `income` is the money summed over sold mails.
- **`Sales.Reconcile(char, ownerRows, now)`:** adds a posting entry for any of your current auctions (from the owner list) with no open posting of the same key, stack and buyout. That covers posts made outside the addon. Entries are added, never removed.
- **`Sales.Prune(char, now)`:** drops sales and `seenMail` entries older than 120 days, keeps at most 2000 sales, and removes consumed postings older than 35 days. Phase 3b's `Sell.Prune` still handles the unconsumed ones.

## 4. Where it shows

- **History tab** (`ui_history.lua`):
  - **List:** one row per item with columns Item, Sold, Expired, Rate, Avg price, Avg time, Income.
  - **Filters:** a period dropdown (7, 30 or 90 days, default 30) and a character dropdown (all, or one character).
  - **Totals line:** income, the number sold, and the overall rate.
  - **Sorting:** by income, descending.
- **Tooltip:** a "Sells 72% (18)" line when the item has results (n is the number of results). It has its own toggle.
- **Sell tab panel:**
  - **Text:** "Sold 12 of 18 (67%), avg 1g 10s each, sells in ~9h", or "No sales history yet."
  - **Warning:** when the buyout per unit is above `warnPct`% of the average sale price, the warning colour and "You've sold this at about 1g 10s. 1g 40s rarely sells." Post is not blocked.
- **Undersupplied deals** (`deals.lua`):
  - **When:** `rate >= 0.5` with `n >= 3` over the stats window; today's snapshot listing count for the key is at most `underPct`% (default 33) of the median listing count over the last 30 days (`P.Market(...).n`); and the realm holdings (`Inventory.Held`) for the key are at least 1.
  - **Deal:** `{ type = "under", key, held, suggest = floor(max(market, lowestNow) × premiumPct/100), profit = held × suggest × 0.95 }`, with `premiumPct` default 110.
  - **Deals tab:** shown with type "Under". The action button reads **Sell**, which switches to the Sell tab and selects the item. It never makes a buy call.

## 5. Right-click from bags (`bagclick.lua`)

- **Wrapping:** wrap the global `ContainerFrameItemButton_OnClick`. In 1.12 it is called with `this` as the item button and `arg1` / the first argument as the mouse button; bag = `this:GetParent():GetID()`, slot = `this:GetID()`. Keep the original and call it for every click this feature doesn't consume.
- **Consumes when all of these hold:**
  - the setting is on, and the click is a right-click
  - `IsShiftKeyDown()`, `IsControlKeyDown()` and `IsAltKeyDown()` are all false
  - our AH window is shown, the Browse or Sell page is visible, and the slot holds an item.
- **On consuming:**
  - **Browse:** put the item name in the search box and run `Browse.Search(name, 0)`.
  - **Sell:** `SellUI.Select(key)` for that item. It must be auctionable; if it isn't, show "Can't auction that" and still consume the click.
- **Never consumes a left-click.**

## 6. Options

- **Sales:** sell-rate window (7–90 days, default 30), price warning % (100–200, step 10, default 120) and the "Sells" tooltip line toggle.
- **Deals:** the undersupplied switch, `underPct` (10–90, step 5) and `premiumPct` (100–150, step 5).
- **General:** "Right-click bag items to search or sell" (default on).

## 7. Testing

- **Fake client:**
  - `GetInboxNumItems`, `GetInboxHeaderInfo` (the 1.12 return order), the `MAIL_SHOW` and `MAIL_INBOX_UPDATE` events, and the subject globals as probed.
  - `ContainerFrameItemButton_OnClick` as a global the stub calls with `this` and `arg1` set.
  - `IsControlKeyDown` and `IsAltKeyDown`.
  - The forbidden mail calls are logged.
- **`sales.lua` units:**
  - `Classify` for every outcome, including item names containing pattern characters ("Potion of (Fire)?" style)
  - an unambiguous sold match giving qty, unit and secs
  - an ambiguous match leaving qty nil
  - expired consuming a posting
  - stats rate, average and income across two characters
  - `Reconcile` adding a missing posting
  - pruning.
- **Mail reading:**
  - a burst of `MAIL_INBOX_UPDATE` events gives one read per frame
  - the same mail is never recorded twice across visits
  - no forbidden mail call is ever made; the automation guard is extended with the mail calls.
- **UI:**
  - History rows, filters and totals
  - the tooltip line
  - the Sell panel text and warning
  - an undersupplied deal shown with Sell, which switches to the Sell tab with no buy call
  - right-click on Browse searches; on Sell, it selects
  - right-click passes through when the window is hidden, on another tab, with a modifier held, or with the setting off
  - a left-click always passes through.
- **In-game checklist:**
  - open the mailbox with AH mail and check History fills
  - reopen and confirm no double count
  - a tooltip "Sells" line
  - the Sell panel and warning
  - an undersupplied deal
  - right-click on Browse and on Sell
  - right-click elsewhere unchanged, for example drinking a potion away from the AH.
