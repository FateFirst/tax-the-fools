# Tax The Fools: Phase 2, tailoring profit

Date: 2026-10-14
Status: approved in conversation, written for review
Parent spec: `docs/superpowers/specs/2026-10-14-tax-the-fools-design.md` (§2 phase 2, §5, §9 Crafting window and tradeskill strip). This document settles what the parent left open. Where the two disagree, this one wins.

## 1. Goal

For every recipe a character has learned, show the cost to make it, what the product is worth, and the profit or loss. Show this on any character, using prices from the bank alt's scans. It works for Tailoring first, and for any profession the tradeskill window shows.

## 2. Decisions

| Topic | Decision |
|---|---|
| Vendor-bought materials (thread, dye, salt) | Buy price is the cheaper of the AH market value and the learned vendor buy price. |
| Materials you can craft (bolts) | Cost is the cheaper of buying and crafting. Crafting cost is worked out recursively from your own captured recipes. The material line shows which source won: `AH`, `vendor` or `craft`. |
| Self-gathered materials | Always at their buy price (parent spec). "Cash profit" is the separate figure that treats held materials as free. |
| Product value | Market value × 0.95 (AH cut) − estimated deposit. With no market value but a known vendor sell price, the vendor price is used instead, labelled `vendor`. |
| Recipes covered | Learned recipes only, captured when the tradeskill window is open. A recipe database is phase 5. |
| Icons | The goblin coin (`media/minimap.tga`) becomes the minimap button. The logo (`media/logo.tga`) sits in the header of the AH and Crafting windows. |

## 3. What the probe established (2026-10-14, Ravencraft, client 1.18.1 build 7272)

- **ClassicAPI is installed.** Use `C_Item.GetItemSellPrice` and `C_Item.GetItemInfoInstant` when they are present, but keep the stock path working.
- **`CalculateAuctionDeposit` and `GetInboxInvoiceInfo` exist.** They matter in phases 3 and 4, not here.
- **`AUCTION_DURATION_*` globals are nil.** Duration labels have to be hard-coded (phase 3).

## 4. Data

Additions to the parent spec §5 shapes:

```lua
TaxTheFoolsDB.items[id].vb      -- vendor BUY price per unit (copper), learned at merchants; nil if never seen
TaxTheFoolsDB.items[id].vbLimited -- true when the merchant had limited stock (still used, flagged)

realm.chars[name] = {
  class = ...,
  professions = {
    ["Tailoring"] = {
      rank = 225, maxRank = 300, at = time(),
      recipes = {
        ["Bolt of Silk Cloth"] = {
          item = "4305:0",            -- product item key
          yieldMin = 1, yieldMax = 1,
          color = "optimal" | "medium" | "easy" | "trivial",   -- GetTradeSkillInfo's skill type
          reagents = { { item = "4306:0", count = 4 } },
        },
      },
    },
  },
  bags = { ["4306:0"] = 37 }, bagsAt = time(),   -- bags 0..4
  bank = { ["4306:0"] = 120 }, bankAt = time(),  -- bank -1 and bags 5..10, recorded while the bank is open
}

settings.craft = { autoWatch = true, staleDays = 7 }
```

- **When a profession is captured,** its whole `recipes` table is replaced, so unlearned or renamed recipes don't linger.
- **Header rows are skipped.** These are the rows where `GetTradeSkillInfo` returns type `"header"`.
- **Missing reagent links:** a reagent whose item link isn't available yet (uncached) is stored by name, with `item = nil`, and filled in on the next capture. Such a recipe reports as incomplete.

## 5. Costing (`craft.lua`, pure)

`Craft.UnitCost(key, ctx, depth)` returns `cost, source`. `source` is `"ah"`, `"vendor"`, `"craft"` or `nil`.

**Buy price:** the minimum of the market value and the vendor buy price, ignoring any that are missing.

**Craft price:** applies when any captured recipe, from any character on the realm, produces this item.
- Cost one craft as the sum over its reagents of `UnitCost(reagent) × count`, then divide by the average yield `(yieldMin + yieldMax) / 2`.
- If any reagent has no cost, there is no craft price.

**Result:** the cheaper of the buy and craft prices.

**Limits:**
- Recursion stops at depth 4.
- A key already being costed higher up the chain returns `nil`, which guards against cycles.
- Results are memoised per evaluation context.

**Recipe evaluation:** `Craft.Evaluate(recipe, ctx)` returns:

```lua
{
  cost = number|nil,          -- one craft's materials
  value = number|nil,         -- per craft, after AH cut and deposit
  valueSource = "ah" | "vendor" | nil,
  profit = number|nil,        -- per craft
  cash = number|nil,          -- profit if held materials (all characters' bags and bank) are free;
                              -- only what is missing is bought
  missing = { "Item name", ... },   -- items with no usable price
  oldest = day|nil,           -- oldest price day used, for the stale dimming
  lines = { { item, name, need, have, unit, source, day } },
}
```

**Value:**
- `market × yieldAvg × 0.95 − deposit × yieldAvg`.
- `deposit` uses the parent spec's Turtle formula for a single-item stack with `minutes = 480`. It is 0 when the vendor sell price is unknown, and the result is then flagged `depositUnknown = true`.
- When there is no market value, `vendorSell × yieldAvg` is used, with `valueSource = "vendor"`.

**Incomplete:**
- When the product has no value, or any reagent has no cost, `profit` and `cash` are nil and `missing` names the items involved.
- The UI shows "incomplete: <names>" and never a guessed number.

**Cash profit:**
- For each reagent, `buy = max(0, need − have)` and the cash cost is `buy × unit`.
- `have` counts the item across every character's bags and bank on this realm.

**The context `ctx`** carries the market table, the item records (vendor prices), every captured recipe on the realm indexed by product key, the combined holdings, and `today`. `craft.lua` makes no game calls.

## 6. Capturing recipes and inventory

- **`tradeskill.lua`:** on `TRADE_SKILL_SHOW` and `TRADE_SKILL_UPDATE` (throttled to one capture per 0.5 s), it reads:
  - `GetTradeSkillLine()` for name, rank and max rank
  - `GetNumTradeSkills()` and `GetTradeSkillInfo(i)` for name, type and number available
  - `GetTradeSkillItemLink(i)`, `GetTradeSkillNumMade(i)` (min, max)
  - `GetTradeSkillNumReagents(i)`, `GetTradeSkillReagentInfo(i, r)` (name, texture, count, player count) and `GetTradeSkillReagentItemLink(i, r)`.

  Every product and reagent seen is remembered in `items`. When `settings.craft.autoWatch` is on, products and reagents are added to `realm.watch`.
- **`inventory.lua`:**
  - **Bags:** on `BAG_UPDATE` (throttled to 1 s) and at login, bags 0 to 4 are recorded into `char.bags`.
  - **Bank:** on `BANKFRAME_OPENED` and on `PLAYERBANKSLOTS_CHANGED` / `BAG_UPDATE` while the bank is open, bank slots (container −1) and bags 5 to 10 are recorded into `char.bank`.
  - **Combined holdings:** `Inventory.Held(realm)` sums both across all characters.
- **Vendor buy prices:** on `MERCHANT_SHOW` (as well as the existing sell-price learning), every merchant item is read with `GetMerchantItemInfo(i)`, which returns name, texture, price, quantity, numAvailable and usable, plus `GetMerchantItemLink(i)`. The addon stores `vb = floor(price / quantity)`, and `vbLimited = numAvailable >= 0`.

## 7. Interface

- **Tradeskill strip:**
  - A themed 22 px bar anchored under `TradeSkillFrame`, created when `TRADE_SKILL_SHOW` first fires. `TradeSkillFrame` is load-on-demand.
  - It shows the selected recipe's cost, value and profit (or "incomplete: …"), coloured good or bad.
  - The selected recipe comes from `GetTradeSkillSelectionIndex()`. It refreshes on `TRADE_SKILL_UPDATE`, and on a 0.25 s poll while the window is shown, because selecting a recipe fires no event.
- **Crafting page** (`ui_craft.lua`), used in two places, built from the same builder:
  - a standalone window `TaxTheFoolsCraft`, opened by minimap left-click or `/ttf craft`
  - an AH window tab, "Crafting".
- **Page contents:**
  - **Header:** a character dropdown (characters on this realm with captured professions) and a profession dropdown.
  - **List columns:** Recipe (coloured by skill type), Cost, Value, Profit, Cash, Age. The default sort is Profit descending, and incomplete recipes sort last.
  - **Expanded row:** a detail pane below the list for the selected recipe. It shows one line per material: need, have, unit, source and age. Prices older than `staleDays` are dimmed.
  - **No captured recipes:** the page says "Open your Tailoring window once on this character to load its recipes."
- **Minimap:**
  - The button texture is `media/minimap.tga`, replacing the "TF" text.
  - Left-click opens the Crafting window and right-click opens options. The tooltip text is updated to match.
- **Window headers:** the AH and Crafting windows show `media/logo.tga` at 24 px before the title.
- **Options:** a new **Crafting** category with "Watch recipe materials automatically" (`craft.autoWatch`) and a "Dim prices older than" slider, 1 to 30 days (`craft.staleDays`).

## 8. Testing

- **Fake client additions:**
  - tradeskill: a recipe list with headers, links, yields and reagents
  - merchant: items with price, quantity and stock
  - bank: slots, bag updates, and the open and closed events
  - a fake `TradeSkillFrame`.
- **`craft.lua` unit tests:**
  - cheapest of AH and vendor
  - craft beats buy, and buy beats craft
  - a three-level chain
  - a cycle returns nil instead of looping
  - depth limit
  - varying yield averaged
  - missing reagent price gives incomplete, with the item named
  - vendor-valued product
  - deposit-unknown flag
  - cash profit with partial holdings across two characters
  - stale-day reporting
- **Capture tests:** headers skipped; recipes replaced on recapture; uncached reagent stored by name, then filled in; auto-watch on and off.
- **Inventory tests:** bags recorded; bank recorded only while open; holdings summed across characters.
- **UI tests:**
  - strip text for complete and incomplete recipes
  - Crafting page sorting with incomplete last
  - character and profession switching
  - the empty-state message
  - minimap left-click opens Crafting.
- **Automation guard:** the core test is extended to show that opening a tradeskill window and a merchant calls nothing that crafts, buys or sells (`DoTradeSkill`, `BuyMerchantItem`).
- **In-game checklist:** add steps for the strip, the Crafting window on the alt after logging over, and vendor thread pricing.
