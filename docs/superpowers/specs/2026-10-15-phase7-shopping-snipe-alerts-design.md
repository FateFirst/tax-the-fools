# Tax The Fools: Phase 7, shopping list, snipe list, quick scans and alerts

Date: 2026-10-15
Status: approved in conversation, written for review

Builds on:
- crafting costs (`craft.lua`, including `Craft.Options` from 0.7.1)
- the Crafting detail pane with clickable materials and the "< Crafting" return (`ui_craft.lua`, `ui_browse.lua`)
- deals (`deals.lua`, `ui_deals.lua`, with Find → Buy)
- scanning (`scan.lua`: `Scan.Start(kind, queries)`, Watchlist)
- holdings (`Inv.Held(realm)`: bags plus bank on every character)
- options.

Where this document and an earlier one disagree, this one wins.

## 1. Decisions

| Topic | Decision |
|---|---|
| Holdings | The shopping list subtracts what every realm character holds in bags and bank (`Inv.Held`). Mail contents can't be seen without opening mail, so they aren't counted; the list says so in its footer. |
| Cheapest path | For each material, buy or craft is chosen by `Craft.Options`. Crafting expands into its own materials, at most `D.CRAFT_DEPTH` deep. Intermediates you already hold are used first. |
| One-click rule | Unchanged. The shopping list, snipe list, quick scans and alerts never buy, bid, post or cancel. Snipe matches are bought through the usual Deals Find → Buy, one click each. Alerts only print and play a sound. |
| Snipe price | A top price per item each (unit), stored per realm. A listing matches when its unit buyout is at or below it and it isn't yours. |
| Alerts | They fire during any scan (full, watch, materials, snipe or a Browse search) for new listings that are either a snipe match or a deal whose profit is at least `alerts.minProfit`. Each listing (key, count, buyout, owner) alerts once per session, and the sound plays at most once every 5 seconds. |
| Quick scans | The status strip's Watchlist button becomes **Quick scan** with a menu: **Watchlist** (as now), **Materials** (every reagent of every captured recipe on the realm, plus the current shopping list's AH lines), and **Snipe list**. Each one is a `Scan.Start` with name queries, kinds `"watch"`, `"mats"` and `"snipe"`, recorded to history like Watchlist. |

## 2. Shopping list (`shopping.lua` pure, `ui_craft.lua`)

- **`Shopping.Plan(recipe, n, ctx, held)`** returns `{ buys = { { key, name, qty, unit, source = "ah"|"vendor", total } }, crafts = { { key, name, qty } }, total, missing = { names } }`.
  1. Start from `n` crafts: the need for each reagent is `n × count`, divided by the recipe's yield and rounded up for intermediates.
  2. Take each material from `held` first, using a working copy so holdings aren't counted twice across lines.
  3. For what is still needed:
     - If `Craft.Options` says crafting is cheaper and a recipe exists, add a crafts line and expand its reagents, using the same holdings copy.
     - Otherwise add a buy line priced at `Craft.BuyPrice`.
     - A material with no price goes into `missing`.
  4. Merge lines with the same key, and sort buys by total descending.
- **UI:**
  - A "Craft" number box, 1–99 with a default of 1, sits at the top of the detail pane, next to a **List** toggle that swaps the material lines for the shopping list.
  - **Shopping lines:**
    - "Buy 14 x Silk Cloth   ~3g 36s (AH)"
    - "Buy 2 x Fine Thread   ~20s (vendor)"
    - "Craft 6 x Bolt of Silk Cloth"
    - a total line, "Total to buy: ~3g 56s"
    - a footer, "Counts bags and bank on all characters, not mail."
  - Buy lines are clickable and use the material search path from 0.7.1.
  - **Snipe these** adds every AH buy line to the snipe list, with the max set to that line's unit price (rounded down), keeping a higher existing max.
  - The plan is kept as `CraftUI.shopping`, for "Next material" and the Materials scan.
- **"Next material" on Browse:** while a shopping plan from the jump exists, Browse shows **Next material (2/5)** next to "< Crafting". It searches the next AH buy line, wrapping round to the start.

## 3. Snipe list (`snipe.lua` pure, `ui_deals.lua`, `ui_browse.lua`)

- **Storage:** `DB.Realm().snipe[key] = { max = copper per unit, name, at }`.
- **`Snipe.Set(list, key, name, max, now)`**, **`Snipe.Remove(list, key)`** and **`Snipe.Parse(text)`**:
  - `Parse` reads "Silk Cloth 20s", "Silk Cloth 1g 5s" or "Silk Cloth 2050". It takes the trailing money (g/s/c parts, or bare copper) and treats the rest as the name, returning `name, copper` or nil.
  - `Snipe.Match(list, key, unit)` is true when `list[key]` exists and `unit <= max`.
- **`Deals.FindSnipes(snapshot, list, me)`** returns deals `{ type = "snipe", key, count, buyout, unit, max, owner, profit = (max − unit) × count }` for every non-own snapshot listing that matches, sorted by profit descending. The Deals tab merges them, labelled "Snipe". A listing that is already another deal type is listed once, under that type. The action is Find → Buy.
- **Deals tab:** a **Deals | Snipe list** toggle.
  - The Snipe list view shows Item, Max each (an editable money input), Market, Listed now (the cheapest snapshot unit) and a Remove button for the selected row.
  - Its empty state says how to add items.
- **Browse:**
  - A **Snipe** button next to Watch, for the selected row. It adds the item with the max set to the row's unit price, or to the market price if that is lower.
  - Rows that match the snipe list are tinted with the accent colour.
- **Slash:** `/ttf snipe <name> <price>` adds an item (the name is resolved with `I.FindByName`, case-insensitive; unknown names report "Item not known yet: search for it once first"). `/ttf snipe` with no arguments opens the Deals Snipe list.

## 4. Quick scans and alerts (`alerts.lua`, `scan.lua`, `ui_window.lua`)

- **Queries:**
  - **`Scan.MatsQueries()`:** the unique names of every reagent of every captured recipe on the realm, plus the shopping plan's buy lines, sorted.
  - **`Scan.SnipeQueries()`:** the snipe list's names.
  - Empty query lists report "Nothing to scan: ..." with a hint, as Watchlist does.
- **Status strip:** the Watchlist button becomes **Quick scan** (same width) and opens a W.Dropdown-style menu with Watchlist, Materials and Snipe list, each showing its item count. Pause and Resume work as before; the paused text names the kind.
- **Alerts:**
  - **`Alerts.Check(listings, ctx, s, now)`** runs on each scanned page's new listings. It's hooked where `scan.lua` appends to `job.listings`, through a `Scan.OnRows` listener so `scan.lua` stays decoupled.
  - For each listing that isn't yours: a snipe match gives `{ kind = "snipe" }`; otherwise `Deals.ListingProfit` with a profit of at least `alerts.minProfit` gives `{ kind = "deal" }`.
  - Each alert prints to chat:
    - "TTF: Snipe: Silk Cloth x20 at 18s each (max 20s)"
    - "TTF: Deal: Runecloth x10 for 4g (profit 1g 20s)".
  - When `alerts.sound` is on, it plays `PlaySound("TellMessage")`, throttled to once every 5 seconds.
  - Alerted signatures go in a session table.
- **Settings:** `settings.alerts = { on = true, minProfit = 10000, sound = true, snipe = true }`.

## 5. Options

- An **Alerts** category with these rows, each with a hint:
  - Alerts on or off
  - Alert when profit is at least (a money slider, 0–20g)
  - Play a sound
  - Alert on snipe matches.
- The **Deals** category gains a **Snipe** deals switch (`settings.deals.snipe`, default on), shown in the rail too if it fits (the rail must stay ≤ 253px; otherwise Options only).

## 6. Testing

- **Shopping:**
  - buy only
  - craft cheaper (expands and uses held bolts first)
  - holdings across characters
  - yield rounding
  - missing prices
  - merged lines
  - totals.
- **Snipe:**
  - Parse forms (gold/silver/copper, bare copper, a name with digits)
  - Set keeping the higher max, and Remove
  - Match
  - FindSnipes, including your own listings and the de-duplication with other deal types.
- **Alerts:** a snipe and a deal alerting once each, a repeat suppressed, the sound throttle, alerts off, and own listings ignored.
- **Scan:** the Materials and Snipe queries and empty cases, the Quick scan menu starting each kind, and the paused text.
- **UI:**
  - the Craft box and List toggle
  - shopping lines clickable
  - Snipe these
  - Next material cycling
  - the Deals Snipe list view (editing max, removing)
  - the Browse Snipe button and tint
  - the slash command
  - options binding and hints.
- **Automation guard:** none of this calls `PlaceAuctionBid`, `StartAuction`, `CancelAuction` or any mail send or take; only the existing simulated Find → Buy clicks do.
- **In-game checklist:** each of the above, plus the alert sound and chat line during a quick scan.
