# Tax The Fools — Phase 2 (Tailoring Profit) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** For every recipe any character has learned, show the cost to make it, what the product is worth, the profit and the cash profit, on any character, in a strip under the tradeskill window, a standalone Crafting window and an AH Crafting tab.

**Architecture:** Same layout as phase 1:
- One new pure module, `craft.lua`, does all costing from a context table (market values, item records, every captured recipe on the realm, combined holdings, today). It makes no game calls and is unit-tested directly.
- Game-facing modules gather the inputs: `items.lua` learns vendor buy prices at merchants, `inventory.lua` records bags and bank, `tradeskill.lua` captures recipes and draws the profit strip, `ui_craft.lua` builds the Crafting page used by both the Crafting window and the AH tab.
- `core.lua` (loaded last) routes the new events and ticks.

**Tech Stack:** Lua 5.0.3 (built by the Makefile), WoW 1.12.1 API (Interface 11200, Turtle 1.18.1 / Ravencraft), the fake client in `tests/wow_stub.lua`.

**Spec:** `docs/superpowers/specs/2026-10-14-phase2-tailoring-profit-design.md` (the authority), with the parent `docs/superpowers/specs/2026-10-14-tax-the-fools-design.md` §5 (data), §7 (deposit formula) and §9 (Crafting window, tradeskill strip). Conventions follow `docs/superpowers/plans/2026-10-14-phase1-core-scanning.md`.

## Global Constraints

Carried over from phase 1:

- Client: WoW 1.12.1 build 5875 (Turtle 1.18.1 / Ravencraft), `## Interface: 11200`, **Lua 5.0**.
- Banned constructs: `#`, `%` (as an operator), hex literals such as `0xc7`, `string.match`, `string.gmatch`, `select`, `hooksecurefunc`, `strsplit`, `math.huge`, `function(self, event`. Use `table.getn`, `math.mod`, `string.find` captures and `string.gfind` instead. Event and script handlers read the globals `this`, `event`, `arg1`..`arg9`.
- A function may reference at most 32 upvalues. `luac -p` from Lua 5.0 rejects more (`make lint`, run by `make test`).
- **Never capture a `for` loop variable in a closure.** In Lua 5.0 every iteration shares the same variable. Pass the value through a function parameter, or store it on the frame and read it back via `this`.
- **Never pass a multi-return call straight into `ipairs(...)`.** Assign the result to a local first. Likewise never build `{ a, b }` from values that may be nil and `ipairs` over it: `ipairs` stops at the first nil.
- Each file begins with `TaxTheFools = TaxTheFools or {}`, reads the modules it depends on into locals at the top, and attaches its own module table. A function is never named the same as a module. A module that keeps per-session state defines `ResetState()`, which `WoW.reset()` calls before every test.
- SavedVariables: `TaxTheFoolsDB` (account-wide), `TaxTheFoolsDB_broken`, `TaxTheFoolsCharDB` (per character, window state only). Prices and characters are keyed by realm name (`DB.Realm()`), the current character by `DB.Char()`.
- Item key is `itemId:suffixId` (strings such as `"4306:0"`); `TaxTheFoolsDB.items` is keyed by the numeric id (`U.keyId(key)`).
- Day number is `math.floor(time() / 86400)` (`U.day`). Saved timestamps use `time()`, never `GetTime()`; `GetTime()` is only for pacing within a session.
- Chat prefix `TTF:` via `U.msg`; slash commands `/ttf` and `/taxthefools`.
- Visual: colour tokens from `theme.lua` only (`good`, `bad`, `warn`, `dim`, `text`, …); no Blizzard frame art in our own frames; no code copied from Aegis Pathfinder (GPLv3).
- Fake-client rule: unknown widget methods are no-ops, and an **unset field on a frame reads back as a function, not nil**. Initialise every frame field the code later tests for truth (to `false`). Getters (`GetWidth`, `GetHeight`, `GetScale`, …) use `rawget`. `Show`/`Hide` fire `OnShow`/`OnHide` only when visibility changes. Anchors do not size frames in the stub: a test that needs list rows drawn sets the list's height.
- Test helpers: `T.test`, `T.eq`, `T.near`, `T.ok`, `T.calledWith`, `T.count`; `WoW.reset()` re-inits the DB before every test; `WoW.fire(event, ...)`, `WoW.runScript(frame, script, arg1)`.

New in phase 2:

- **Automation rule, extended:** nothing in this phase calls `DoTradeSkill`, `BuyMerchantItem` or `UseContainerItem` (selling), as well as phase 1's `PlaceAuctionBid`, `StartAuction`, `CancelAuction`. The core automation test proves it.
- Costing (spec §5):
  - buy price = min(market value, vendor buy price `items[id].vb`), ignoring missing ones
  - craft price = Σ `UnitCost(reagent) × count` ÷ average yield `(yieldMin + yieldMax) / 2`, from any captured recipe on the realm; nil if any reagent has no cost
  - unit cost = the cheaper of buy and craft; recursion stops at depth **4**; a key already being costed returns nil; memoised per context
  - value = `market × yieldAvg × 0.95 − deposit × yieldAvg`, deposit = Turtle formula for one single-item stack with `minutes = 480`, 0 and `depositUnknown = true` when the vendor sell price is unknown; no market but a vendor sell price → `vendorSell × yieldAvg`, `valueSource = "vendor"`
  - incomplete (any reagent or the product unpriced) → `profit` and `cash` nil, `missing` names the items; **never a guessed number**
  - cash = value − Σ `max(0, need − have) × unit`, `have` = every character's bags + bank on the realm
- Deposit: `floor(vendorUnit × stack × (minutes/120) × (1 + (maxStack − stack) × 0.05) × 0.025) × stackCount`.
- Settings: `settings.craft = { autoWatch = true, staleDays = 7 }`; "Dim prices older than" slider 1–30 days.
- Tradeskill capture throttled to one per 0.5 s; bag counting throttled to one per 1 s; strip poll every 0.25 s while the window is shown.
- Strip: 22 px high, under `TradeSkillFrame`, created lazily on the first `TRADE_SKILL_SHOW` (TradeSkillFrame is load-on-demand).
- Logo `media/logo.tga` at 24 px before the title of the AH and Crafting windows; minimap button texture `media/minimap.tga`. Both are full-colour art: never tinted.
- Empty Crafting page text, verbatim: `Open your Tailoring window once on this character to load its recipes.`
- **Numbers in tests:** every numeric expectation carries its arithmetic in a comment or message next to the assertion. All of them were computed with a script, not by hand.

## Review Focus

1. **A collapsed header in the tradeskill window** hides its recipes from `GetNumTradeSkills`; replacing the recipe table would silently drop them. Expected: recipes under a collapsed header are kept. Test in Task 3.
2. **The first tradeskill open after login lists nothing yet** (the client fills the list on a later `TRADE_SKILL_UPDATE`). Expected: an empty read leaves the stored recipes alone. Test in Task 3.
3. **A bag update after the bank closes**, when bank containers read as empty. Expected: the stored bank record is left alone, never overwritten with nothing. Test in Task 2.
4. **Merchant items priced in tokens or tickets** (price 0) and items whose link is not cached. Expected: skipped, no `vb = 0` that would make the material free. Test in Task 2.
5. **The tradeskill selection on a header, or `TRADE_SKILL_SHOW` before TradeSkillFrame has loaded.** Expected: the strip shows a prompt instead of a stale or wrong recipe, and a missing frame is no error. Tests in Task 4.

## Decisions made while planning (the spec left these open)

- **Age of an AH price** is `today − market.lowDay`: `lowDay` is the newest scan day that saw the item. A vendor buy price has no age and is never dimmed. A crafted cost is as old as the oldest price behind it.
- **Vendor wins a tie** with the AH (`vb <= ah`): a vendor's price is guaranteed.
- **Reagents always store `name`** next to `item` and `count` (the spec stores the name only when the link is missing): the Crafting page and `missing` need a name even for items not yet in `TaxTheFoolsDB.items`.
- **Collapsed headers and empty reads** do not drop recipes (Review Focus 1 and 2). Otherwise a capture replaces the profession's recipe table, as the spec says.
- **Unknown max stack size** in the deposit counts as a stack of 1 (`maxStack = stack`), the smallest deposit.
- **Product vendor sell price via ClassicAPI**: capture calls `Items.Vendor(id)` for each product, which stores `C_Item.GetItemSellPrice` when ClassicAPI is present, so deposits are known without visiting a merchant.
- **Memoisation** only stores a result when no cycle guard or depth limit cut its calculation short. A cut result depends on the path that reached it.
- **The Crafting page opens on this character** if it has captured recipes, else on the first character (alphabetically) that does. The empty message shows only when no character on the realm has any.
- **Strip anchor:** `TOPLEFT` of the strip to `BOTTOMLEFT` of TradeSkillFrame at (14, 73), width 330. TradeSkillFrame is 384×512 with `HitRectInsets` right 34, bottom 75, so the visible panel ends 75 px above the frame's bottom. The in-game checklist verifies this and names the constants to adjust.
- **Strip money is plain** (`U.money(v, true)`) so the whole line takes the good/bad colour; the Crafting list keeps coloured coins for Cost and Value and uses plain money for Profit and Cash.
- **`W.Dropdown` gains `SetOptions`** (the character and profession lists change at run time). A dropdown whose value matches no option now shows an empty label.
- **Bags are counted at login** from `PLAYER_ENTERING_WORLD`, and `Core.Init` also marks bags dirty in case that event came first.
- **`BANKFRAME_CLOSED` drops a pending bank recount** rather than reading containers that may already be unreadable.
- **Auto-watch re-adds** products and materials on every capture, even ones you unwatched by hand; the Crafting option turns that off.
- **Version** becomes 0.2.0 (Task 7).
- **Not in this phase:** shift-left-click on the minimap button (Deals, phase 3); the Enchanting window (it uses the separate Craft API).

---

## File Structure

```
TaxTheFools/data.lua          + CRAFT_DEPTH, AH_CUT, DEPOSIT_MINUTES, settings.craft defaults, VERSION 0.2.0
TaxTheFools/util.lua          + U.linkName
TaxTheFools/craft.lua         NEW  pure costing: Index, Context, Deposit, Yield, BuyPrice, UnitCost, Evaluate
TaxTheFools/items.lua         + I.LearnMerchantPrices (vb, vbLimited)
TaxTheFools/inventory.lua     NEW  bags 0..4 and bank -1, 5..10 per character; Held(realm)
TaxTheFools/tradeskill.lua    NEW  recipe capture, auto-watch, the profit strip, TS.Context()
TaxTheFools/widgets.lua       + Dropdown:SetOptions; Window opts.logo
TaxTheFools/ui_window.lua     + Crafting tab; logo in the AH header
TaxTheFools/ui_craft.lua      NEW  Crafting page builder, Crafting window
TaxTheFools/options.lua       + Crafting category
TaxTheFools/minimap.lua       goblin coin texture; left-click Crafting, right-click options
TaxTheFools/theme.lua         + logo, minimap in Th.TEXTURES
TaxTheFools/core.lua          new events, ticks, /ttf craft
TaxTheFools/TaxTheFools.toc   craft.lua, inventory.lua, tradeskill.lua, ui_craft.lua; Version 0.2.0
tests/wow_stub.lua            + merchant, bank containers, tradeskill API, TradeSkillFrame, logged DoTradeSkill/BuyMerchantItem/UseContainerItem
tests/test_craft.lua          NEW
tests/test_inventory.lua      NEW
tests/test_tradeskill.lua     NEW
tests/test_craft_ui.lua       NEW
tests/test_items.lua, test_core.lua, test_util.lua, test_widgets.lua, test_options.lua   extended
docs/testing-checklist.md     + Crafting section
README.md                     crafting usage, /ttf craft
```

Final `.toc` file list, in load order (new files marked):

```
data.lua
util.lua
stats.lua
price.lua
craft.lua          <- new (Task 1), line 13: pure, needs Util and Data only
db.lua
items.lua
inventory.lua      <- new (Task 2), line 16: needs Util and DB
scan.lua
ahhook.lua
theme.lua
widgets.lua
list.lua
tooltip.lua
tradeskill.lua     <- new (Task 3), line 23: needs Items, Theme (Task 4), Craft, Inventory
ui_window.lua
ui_browse.lua
ui_craft.lua       <- new (Task 5), line 26: needs Widgets, List, TradeSkill, UI, Scan
options.lua
minimap.lua
probe.lua
core.lua
```

(Line numbers count the seven `##` header lines and the blank line after them: `data.lua` is line 9.)

Test count: 136 now. Running totals: Task 1 → 151, Task 2 → 161, Task 3 → 170, Task 4 → 174, Task 5 → 181, Task 6 → 186, Task 7 → 186.

---

### Task 1: Pure recipe costing (`craft.lua`)

**Files:**
- Create: `TaxTheFools/craft.lua`
- Modify: `TaxTheFools/data.lua:20` (constants after `D.PRUNE_PER_FRAME`)
- Modify: `TaxTheFools/TaxTheFools.toc` (add `craft.lua` after `price.lua`, line 13)
- Test: `tests/test_craft.lua` (new)

**Interfaces:**
- Consumes: `U.keyId(key) -> id`, `D.CRAFT_DEPTH`, `D.AH_CUT`, `D.DEPOSIT_MINUTES` (added here).
- Produces (`TaxTheFools.Craft`):
  - `Craft.Index(chars) -> { [productKey] = { recipe, ... } }` — every recipe of every character in `chars` (`realm.chars`) whose `item` is set.
  - `Craft.Context(realm, items, held, today) -> ctx` where `ctx = { market = realm.market, items = items, recipes = Craft.Index(realm.chars), held = held, today = today, memo = {}, busy = {}, cuts = 0 }`. `items` is `TaxTheFoolsDB.items` (records `{ n, st, v = vendor sell, vb = vendor buy, vbLimited }`), `held` is `{ [key] = count }`, `today` a day number. Build a fresh context for each repaint.
  - `Craft.Deposit(vendorUnit, maxStack, stack, minutes, stacks) -> copper`
  - `Craft.Yield(recipe) -> number` (average of `yieldMin`, `yieldMax`, at least 1 when both are missing)
  - `Craft.BuyPrice(key, ctx) -> cost, "ah"|"vendor", day` or `nil`
  - `Craft.UnitCost(key, ctx, depth) -> cost|nil, source ("ah"|"vendor"|"craft"|nil), day|nil`
  - `Craft.Evaluate(recipe, ctx) -> ev` with `ev = { cost, value, valueSource, profit, cash, missing = { names }, oldest, depositUnknown, lines = { { item, name, need, have, unit, source, day, limited } } }`
  - A recipe is `{ item = key|nil, yieldMin, yieldMax, color, reagents = { { item = key|nil, name = string|nil, count } } }`.

- [ ] **Step 1: Write the failing test**

`tests/test_craft.lua`:
```lua
local C = TaxTheFools.Craft
local TODAY = 20375

-- A realm's worth of inputs: market { key = { v=, lowDay= } }, items { id = record },
-- recipes as one character's Tailoring, held { key = count }.
local function ctxOf(market, items, recipes, held)
  local chars = { Tailor = { professions = { Tailoring = { recipes = recipes or {} } } } }
  return C.Context({ market = market or {}, chars = chars }, items or {}, held or {}, TODAY)
end

local function bolt()
  return { item = "4305:0", yieldMin = 1, yieldMax = 1, color = "medium",
           reagents = { { item = "4306:0", name = "Silk Cloth", count = 4 } } }
end

local function link(from, to, n)   -- a recipe making `to` from n of `from`
  return { item = to, yieldMin = 1, yieldMax = 1, reagents = { { item = from, count = n or 1 } } }
end

T.test("buy price is the cheaper of the market value and the vendor price", function()
  local ctx = ctxOf({ ["2321:0"] = { v = 150, lowDay = 20374 }, ["4306:0"] = { v = 300, lowDay = 20373 } },
    { [2321] = { n = "Fine Thread", vb = 100 }, [4306] = { n = "Silk Cloth", vb = 500 } })
  local cost, source, day = C.UnitCost("2321:0", ctx, 0)
  T.eq(cost, 100) T.eq(source, "vendor") T.eq(day, nil, "a vendor price has no age")
  cost, source, day = C.UnitCost("4306:0", ctx, 0)
  T.eq(cost, 300) T.eq(source, "ah") T.eq(day, 20373)
  T.eq(C.UnitCost("9999:0", ctx, 0), nil, "no price at all")
end)

T.test("crafting a material beats buying it when it is cheaper", function()
  local ctx = ctxOf({ ["4306:0"] = { v = 300, lowDay = 20374 }, ["4305:0"] = { v = 2000, lowDay = 20375 } }, {},
    { ["Bolt of Silk Cloth"] = bolt() })
  local cost, source, day = C.UnitCost("4305:0", ctx, 0)
  T.eq(cost, 1200, "4 x 300 = 1200 < 2000")
  T.eq(source, "craft")
  T.eq(day, 20374, "as old as the silk price behind it")
end)

T.test("buying a material beats crafting it when it is cheaper", function()
  local ctx = ctxOf({ ["4306:0"] = { v = 300 }, ["4305:0"] = { v = 1000 } }, {}, { ["Bolt of Silk Cloth"] = bolt() })
  local cost, source = C.UnitCost("4305:0", ctx, 0)
  T.eq(cost, 1000, "1000 < 4 x 300 = 1200")
  T.eq(source, "ah")
end)

T.test("a three-level chain is costed from the bottom up", function()
  -- 9003 is bought from a vendor at 10; 9002 = 3 x 9003; 9001 = 2 x 9002; the recipe uses one 9001.
  local ctx = ctxOf({ ["9002:0"] = { v = 100 }, ["9001:0"] = { v = 1000 }, ["9000:0"] = { v = 5000 } },
    { [9003] = { n = "Chain C", vb = 10 } },
    { B = link("9003:0", "9002:0", 3), A = link("9002:0", "9001:0", 2), Top = link("9001:0", "9000:0", 1) })
  local ev = C.Evaluate(link("9001:0", "9000:0", 1), ctx)
  T.eq(ev.lines[1].unit, 60, "3 x 10 = 30 < 100, then 2 x 30 = 60 < 1000")
  T.eq(ev.lines[1].source, "craft")
  T.eq(ev.cost, 60)
end)

T.test("a cycle of recipes returns nil instead of looping", function()
  -- Loop A = 2 x Loop B, Loop B = 1 x Loop A. B also sells for 30; A has no market value.
  local ctx = ctxOf({ ["9102:0"] = { v = 30 } }, {},
    { A = link("9102:0", "9101:0", 2), B = link("9101:0", "9102:0", 1) })
  local cost, source = C.UnitCost("9101:0", ctx, 0)
  T.eq(cost, 60, "2 x 30: B is bought because crafting B leads back to A")
  T.eq(source, "craft")
  local bare = ctxOf({}, {}, { A = link("9102:0", "9101:0", 2), B = link("9101:0", "9102:0", 1) })
  T.eq(C.UnitCost("9101:0", bare, 0), nil, "no price anywhere in the loop")
end)

T.test("crafting recursion stops at depth 4", function()
  -- 9201..9205 each sell for 1000 and are each made from one of the next; 9206 sells for 100.
  local market = { ["9201:0"] = { v = 1000 }, ["9202:0"] = { v = 1000 }, ["9203:0"] = { v = 1000 },
                   ["9204:0"] = { v = 1000 }, ["9205:0"] = { v = 1000 }, ["9206:0"] = { v = 100 } }
  local recipes = { a = link("9202:0", "9201:0"), b = link("9203:0", "9202:0"), c = link("9204:0", "9203:0"),
                    d = link("9205:0", "9204:0"), e = link("9206:0", "9205:0") }
  -- From 9201 (depth 0), 9205 sits at depth 4: it may only be bought (1000), so nothing beats 1000.
  local cost, source = C.UnitCost("9201:0", ctxOf(market, {}, recipes), 0)
  T.eq(cost, 1000) T.eq(source, "ah")
  -- From 9203 (depth 0), 9206 is reached at depth 3 and bought for 100: 100 all the way up.
  cost, source = C.UnitCost("9203:0", ctxOf(market, {}, recipes), 0)
  T.eq(cost, 100) T.eq(source, "craft")
end)

T.test("a varying yield is averaged", function()
  local r = { item = "9301:0", yieldMin = 1, yieldMax = 3, reagents = { { item = "4306:0", count = 1 } } }
  local ctx = ctxOf({ ["4306:0"] = { v = 300 }, ["9301:0"] = { v = 1000 } }, {}, { R = r })
  local ev = C.Evaluate(r, ctx)
  T.eq(C.Yield(r), 2, "(1 + 3) / 2")
  T.near(ev.value, 1900, 0.001, "1000 x 2 x 0.95")
  T.eq(ev.cost, 300)
  T.near(ev.profit, 1600, 0.001, "1900 - 300")
  local unit = C.UnitCost("9301:0", ctxOf({ ["4306:0"] = { v = 300 }, ["9301:0"] = { v = 1000 } }, {}, { R = r }), 0)
  T.eq(unit, 150, "as a material: 300 / 2 = 150 < 1000")
end)

T.test("a material with no price makes the recipe incomplete and is named", function()
  local r = { item = "4305:0", yieldMin = 1, yieldMax = 1, reagents = {
    { item = "4306:0", name = "Silk Cloth", count = 4 }, { item = "3182:0", name = "Spider's Silk", count = 1 } } }
  local ev = C.Evaluate(r, ctxOf({ ["4306:0"] = { v = 300 }, ["4305:0"] = { v = 2000 } }, {}, {}))
  T.eq(ev.profit, nil) T.eq(ev.cash, nil) T.eq(ev.cost, nil)
  T.eq(table.getn(ev.missing), 1)
  T.eq(ev.missing[1], "Spider's Silk")
  T.ok(ev.value, "the product still has its value")
end)

T.test("a reagent stored by name only, link not cached yet, is incomplete", function()
  local r = { item = "4305:0", reagents = { { name = "Spider's Silk", count = 1 } } }
  local ev = C.Evaluate(r, ctxOf({ ["4305:0"] = { v = 2000 } }, {}, {}))
  T.eq(ev.profit, nil)
  T.eq(ev.missing[1], "Spider's Silk")
  T.eq(ev.lines[1].have, 0)
end)

T.test("a product with no market value is valued at its vendor price", function()
  local ev = C.Evaluate(bolt(), ctxOf({ ["4306:0"] = { v = 300 } }, { [4305] = { n = "Bolt of Silk Cloth", v = 250 } }, {}))
  T.eq(ev.value, 250) T.eq(ev.valueSource, "vendor")
  T.eq(ev.profit, -950, "250 - 4 x 300")
  local none = C.Evaluate(bolt(), ctxOf({ ["4306:0"] = { v = 300 } }, { [4305] = { n = "Bolt of Silk Cloth" } }, {}))
  T.eq(none.value, nil) T.eq(none.profit, nil)
  T.eq(none.missing[1], "Bolt of Silk Cloth", "the product is named when it has no value")
end)

T.test("the deposit comes off the value, or is flagged unknown", function()
  local market = { ["4306:0"] = { v = 300 }, ["4305:0"] = { v = 2000 } }
  local ev = C.Evaluate(bolt(), ctxOf(market, { [4305] = { v = 100, st = 10 } }, {}))
  -- deposit floor(100 x 1 x 480/120 x (1 + (10 - 1) x 0.05) x 0.025) = floor(14.5) = 14
  T.near(ev.value, 1886, 0.001, "2000 x 0.95 - 14")
  T.eq(ev.depositUnknown, nil)
  ev = C.Evaluate(bolt(), ctxOf(market, {}, {}))
  T.near(ev.value, 1900, 0.001, "2000 x 0.95, no deposit")
  T.eq(ev.depositUnknown, true)
end)

T.test("Turtle's deposit formula", function()
  T.eq(C.Deposit(100, 20, 1, 480, 1), 19, "floor(100 x 4 x 1.95 x 0.025) = floor(19.5)")
  T.eq(C.Deposit(100, nil, 1, 480, 1), 10, "unknown stack size counts as 1: floor(100 x 4 x 0.025)")
  T.eq(C.Deposit(37, 20, 1, 480, 3), 21, "floor(37 x 4 x 1.95 x 0.025) = floor(7.215) = 7, x 3 stacks")
end)

T.test("cash profit buys only what is not already held", function()
  local market = { ["4306:0"] = { v = 300 }, ["4305:0"] = { v = 2000 } }
  local ev = C.Evaluate(bolt(), ctxOf(market, {}, {}, { ["4306:0"] = 3 }))
  T.near(ev.profit, 700, 0.001, "1900 - 4 x 300")
  T.near(ev.cash, 1600, 0.001, "1900 - (4 - 3) x 300")
  T.eq(ev.lines[1].have, 3)
  ev = C.Evaluate(bolt(), ctxOf(market, {}, {}, { ["4306:0"] = 10 }))
  T.near(ev.cash, 1900, 0.001, "nothing to buy")
end)

T.test("the oldest price day used is reported for dimming", function()
  local r = { item = "4305:0", reagents = { { item = "4306:0", count = 4 }, { item = "2321:0", count = 1 } } }
  local ctx = ctxOf({ ["4306:0"] = { v = 300, lowDay = 20370 }, ["4305:0"] = { v = 2000, lowDay = 20372 } },
    { [2321] = { vb = 100 } }, {})
  local ev = C.Evaluate(r, ctx)
  T.eq(ev.oldest, 20370, "the silk price, older than the product's 20372")
  T.eq(ev.lines[1].day, 20370)
  T.eq(ev.lines[2].day, nil, "vendor thread has no age")
end)

T.test("recipes from every character are indexed by product", function()
  local chars = {
    Tailor = { professions = { Tailoring = { recipes = { Bolt = bolt() } } } },
    Alt = { professions = { Tailoring = { recipes = { Bolt = bolt(), Odd = { reagents = {} } } } } },
    Bank = {},
  }
  local by = C.Index(chars)
  T.eq(table.getn(by["4305:0"]), 2)
  local n = 0
  for _ in pairs(by) do n = n + 1 end
  T.eq(n, 1, "a recipe with no product link is left out")
end)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `make test`
Expected: `136 passed, 15 failed`; every `test_craft.lua` test fails with `attempt to index a nil value` (`TaxTheFools.Craft` does not exist yet).

- [ ] **Step 3: Implement**

In `TaxTheFools/data.lua`, after the line `D.PRUNE_PER_FRAME = 50` add:
```lua
D.CRAFT_DEPTH = 4         -- a material crafted from materials crafted from ..., at most this deep
D.AH_CUT = 0.05
D.DEPOSIT_MINUTES = 480   -- the middle duration (8h, shown as 24h on Turtle)
```

In `TaxTheFools/TaxTheFools.toc`, add the line `craft.lua` directly after `price.lua` (it becomes line 13, before `db.lua`).

`TaxTheFools/craft.lua`:
```lua
TaxTheFools = TaxTheFools or {}
local U, D = TaxTheFools.Util, TaxTheFools.Data
local Craft = {}
TaxTheFools.Craft = Craft

-- Pure: every price, recipe and holding arrives in ctx. No game calls here.

-- Every captured recipe on the realm, from every character, by the item it makes.
function Craft.Index(chars)
  local by = {}
  for _, c in pairs(chars or {}) do
    for _, prof in pairs(c.professions or {}) do
      for _, r in pairs(prof.recipes or {}) do
        if r.item then
          local list = by[r.item]
          if not list then
            list = {}
            by[r.item] = list
          end
          table.insert(list, r)
        end
      end
    end
  end
  return by
end

-- One evaluation's worth of inputs. memo and busy live as long as the context:
-- build a fresh one whenever prices or holdings may have changed.
function Craft.Context(realm, items, held, today)
  return { market = realm.market or {}, items = items or {}, recipes = Craft.Index(realm.chars),
           held = held or {}, today = today, memo = {}, busy = {}, cuts = 0 }
end

-- Turtle's deposit (parent spec §7):
-- floor(vendorUnit × stack × (minutes/120) × (1 + (maxStack − stack) × 0.05) × 0.025) × stacks
function Craft.Deposit(vendorUnit, maxStack, stack, minutes, stacks)
  stack = stack or 1
  maxStack = maxStack or stack
  if maxStack < stack then maxStack = stack end
  return math.floor(vendorUnit * stack * (minutes / 120) * (1 + (maxStack - stack) * 0.05) * 0.025) * (stacks or 1)
end

function Craft.Yield(recipe)
  local lo = recipe.yieldMin or 1
  local hi = recipe.yieldMax or lo
  local y = (lo + hi) / 2
  if y <= 0 then y = 1 end
  return y
end

local function record(ctx, key) return ctx.items[U.keyId(key)] end

local function older(a, b)
  if a == nil then return b end
  if b == nil then return a end
  if b < a then return b end
  return a
end

-- The cheaper of the market value and a vendor's buy price. A vendor price
-- has no age; a market value is as old as the newest scan row behind it.
function Craft.BuyPrice(key, ctx)
  local m = ctx.market[key]
  local rec = record(ctx, key)
  local ah = m and m.v
  local vb = rec and rec.vb
  if vb and (not ah or vb <= ah) then return vb, "vendor", nil end
  if ah then return ah, "ah", m.lowDay end
  return nil
end

-- One craft's materials over the average yield; nil if any material has no price.
local function perUnit(recipe, ctx, depth)
  local total, day = 0, nil
  for _, g in ipairs(recipe.reagents or {}) do
    if not g.item then return nil end
    local c, _, d = Craft.UnitCost(g.item, ctx, depth + 1)
    if not c then return nil end
    total = total + c * (g.count or 1)
    day = older(day, d)
  end
  return total / Craft.Yield(recipe), day
end

-- cost, source ("ah" | "vendor" | "craft" | nil), day (oldest price day behind it).
-- A result is only memoised when no cycle guard or depth limit cut it short:
-- the same item reached by a shorter path may cost less.
function Craft.UnitCost(key, ctx, depth)
  depth = depth or 0
  local memo = ctx.memo[key]
  if memo then return memo.cost, memo.source, memo.day end
  if ctx.busy[key] then
    ctx.cuts = ctx.cuts + 1
    return nil
  end
  local cutsBefore = ctx.cuts
  local cost, source, day = Craft.BuyPrice(key, ctx)
  local recipes = ctx.recipes[key]
  if recipes then
    if depth >= D.CRAFT_DEPTH then
      ctx.cuts = ctx.cuts + 1
    else
      ctx.busy[key] = true
      for _, r in ipairs(recipes) do
        local c, d = perUnit(r, ctx, depth)
        if c and (not cost or c < cost) then cost, source, day = c, "craft", d end
      end
      ctx.busy[key] = nil
    end
  end
  if ctx.cuts == cutsBefore then ctx.memo[key] = { cost = cost, source = source, day = day } end
  return cost, source, day
end

local function nameOf(ctx, key, fallback)
  local rec = key and record(ctx, key)
  if rec and rec.n then return rec.n end
  if fallback then return fallback end
  if key then return "Unknown item #" .. tostring(U.keyId(key)) end
  return "Unknown item"
end

-- Cost, value, profit and cash profit of one craft. Never guesses: with any
-- price missing, profit and cash are nil and missing names the items.
function Craft.Evaluate(recipe, ctx)
  local ev = { missing = {}, lines = {} }
  local y = Craft.Yield(recipe)
  local product = recipe.item
  if product then ctx.busy[product] = true end
  local cost, cash, priced = 0, 0, true
  for _, g in ipairs(recipe.reagents or {}) do
    local line = { item = g.item, name = nameOf(ctx, g.item, g.name), need = g.count or 1, have = 0 }
    if g.item then
      line.have = ctx.held[g.item] or 0
      line.unit, line.source, line.day = Craft.UnitCost(g.item, ctx, 0)
      local rec = record(ctx, g.item)
      if line.source == "vendor" and rec and rec.vbLimited then line.limited = true end
    end
    if line.unit then
      cost = cost + line.unit * line.need
      local buy = line.need - line.have
      if buy < 0 then buy = 0 end
      cash = cash + buy * line.unit
      ev.oldest = older(ev.oldest, line.day)
    else
      priced = false
      table.insert(ev.missing, line.name)
    end
    table.insert(ev.lines, line)
  end
  if product then ctx.busy[product] = nil end
  if priced then ev.cost = cost end

  local m = product and ctx.market[product]
  local rec = product and record(ctx, product)
  local sell = rec and rec.v
  if m and m.v then
    local deposit = 0
    if sell then deposit = Craft.Deposit(sell, rec.st, 1, D.DEPOSIT_MINUTES, 1)
    else ev.depositUnknown = true end
    ev.value = m.v * y * (1 - D.AH_CUT) - deposit * y
    ev.valueSource = "ah"
    ev.oldest = older(ev.oldest, m.lowDay)
  elseif sell then
    ev.value = sell * y
    ev.valueSource = "vendor"
  else
    table.insert(ev.missing, nameOf(ctx, product))
  end

  if priced and ev.value then
    ev.profit = ev.value - cost
    ev.cash = ev.value - cash
  end
  return ev
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: `151 passed, 0 failed` (136 + 15 new `T.test` calls in `test_craft.lua`), no lint output.

- [ ] **Step 5: Commit**

```bash
git add TaxTheFools/craft.lua TaxTheFools/data.lua TaxTheFools/TaxTheFools.toc tests/test_craft.lua
git commit -m "feat: pure recipe costing with buy, vendor and craft sources"
```

---

### Task 2: Vendor buy prices and bag/bank inventory

**Files:**
- Modify: `tests/wow_stub.lua:206` (reset), `tests/wow_stub.lua:313-324` (containers; merchant API added after them)
- Modify: `TaxTheFools/items.lua:89` (new function before `I.FindByName`)
- Create: `TaxTheFools/inventory.lua`
- Modify: `TaxTheFools/TaxTheFools.toc` (add `inventory.lua` after `items.lua`, line 16)
- Modify: `TaxTheFools/core.lua:33` (Init), `:46-55` (OnEvent), `:71` (Update), `:151-152` (event list)
- Test: `tests/test_items.lua`, `tests/test_core.lua`, `tests/test_inventory.lua` (new)

**Interfaces:**
- Consumes: `I.Remember(id, name, quality, stack, texture) -> record`, `U.parseLink`, `U.keyFromLink(link) -> key, id`, `DB.Char()`, `DB.Realm()`, `Craft.Evaluate`, `Craft.Context` (Task 1).
- Produces:
  - `I.LearnMerchantPrices()` — sets `items[id].vb = floor(price / quantity)` and `items[id].vbLimited = true|nil` for every merchant item with a link and a price above 0.
  - `TaxTheFools.Inventory` (`Inv`): `Inv.BAGS = { 0..4 }`, `Inv.BANK = { -1, 5..10 }`, `Inv.Count(bags) -> { [key] = n }`, `Inv.ScanBags()` (writes `char.bags`, `char.bagsAt`), `Inv.ScanBank()` (writes `char.bank`, `char.bankAt`, only while `Inv.bankOpen`), `Inv.OnEvent(event)`, `Inv.Tick(now)`, `Inv.Held(realm) -> { [key] = count }` summed over every character's bags and bank. Fields `Inv.bankOpen`, `Inv.bagsDirty`, `Inv.bankDirty`, `Inv.scannedAt`.
  - `Core.INVENTORY_EVENTS` (set of event names routed to `Inv.OnEvent`).
  - Stub: `WoW.merchant`, `WoW.bankOpen`, `GetMerchantNumItems`, `GetMerchantItemInfo`, `GetMerchantItemLink`, logged `BuyMerchantItem` and `UseContainerItem`.

- [ ] **Step 1: Extend the fake client with merchants and the bank**

The real client reads bank containers (−1 and 5..10) as empty while the bank is closed; the stub must too, or the "bank only while open" test proves nothing.

In `tests/wow_stub.lua`, inside `WoW.reset()`, replace:
```lua
  WoW.merchantOpen = false
```
with:
```lua
  WoW.merchantOpen = false
  WoW.merchant = {}
  WoW.bankOpen = false
```

Replace the whole bag block (from the `-- Bags:` comment to the end of `GetContainerItemInfo`):
```lua
-- Bags: WoW.bags[bag][slot] = { id=, name=, count=, vendor= } or {} for an empty slot.
function GetContainerNumSlots(bag) return WoW.bags[bag] and table.getn(WoW.bags[bag]) or 0 end
function GetContainerItemLink(bag, slot)
  local it = WoW.bags[bag] and WoW.bags[bag][slot]
  if it and it.id then return WoW.link(it.id, it.name) end
  return nil
end
function GetContainerItemInfo(bag, slot)
  local it = WoW.bags[bag] and WoW.bags[bag][slot]
  if not it or not it.id then return nil end
  return it.tex or "tex", it.count or 1
end
```
with:
```lua
-- Bags: WoW.bags[bag][slot] = { id=, name=, count=, vendor= } or {} for an empty slot.
-- Bags 0..4 are carried. The bank is container -1 plus bags 5..10, and like the
-- real client it reads as empty unless the bank window is open (WoW.bankOpen).
local function bankBag(bag) return bag == -1 or (bag >= 5 and bag <= 10) end
local function slotItem(bag, slot)
  if bankBag(bag) and not WoW.bankOpen then return nil end
  return WoW.bags[bag] and WoW.bags[bag][slot]
end
function GetContainerNumSlots(bag)
  if bankBag(bag) and not WoW.bankOpen then return 0 end
  return WoW.bags[bag] and table.getn(WoW.bags[bag]) or 0
end
function GetContainerItemLink(bag, slot)
  local it = slotItem(bag, slot)
  if it and it.id then return WoW.link(it.id, it.name) end
  return nil
end
function GetContainerItemInfo(bag, slot)
  local it = slotItem(bag, slot)
  if not it or not it.id then return nil end
  return it.tex or "tex", it.count or 1
end
-- Selling at a merchant is a right-click on a bag item, which is this call.
function UseContainerItem(bag, slot) WoW.log("UseContainerItem", bag, slot) end
-- Merchant: WoW.merchant[i] = { id=, name=, price=, quantity=, numAvailable=, noLink= }.
-- price is for the whole lot of `quantity` units; numAvailable -1 means unlimited stock.
function GetMerchantNumItems() return table.getn(WoW.merchant) end
function GetMerchantItemInfo(i)
  local m = WoW.merchant[i]
  if not m then return nil end
  return m.name, m.tex or "tex", m.price or 0, m.quantity or 1, m.numAvailable or -1, 1
end
function GetMerchantItemLink(i)
  local m = WoW.merchant[i]
  if m and m.id and not m.noLink then return WoW.link(m.id, m.name) end
  return nil
end
function BuyMerchantItem(i, n) WoW.log("BuyMerchantItem", i, n) end
```

Run: `make test`
Expected: `151 passed, 0 failed` (the stub change alone breaks nothing).

- [ ] **Step 2: Write the failing tests**

Append to `tests/test_items.lua`:
```lua

T.test("merchant buy prices are stored per unit and flagged when stock is limited", function()
  WoW.merchant = {
    { id = 2321, name = "Fine Thread", price = 100, quantity = 1, numAvailable = -1 },
    { id = 4470, name = "Simple Wood", price = 38, quantity = 5, numAvailable = -1 },
    { id = 2604, name = "Red Dye", price = 50, quantity = 1, numAvailable = 4 },
  }
  I.LearnMerchantPrices()
  T.eq(I.Get(2321).vb, 100) T.eq(I.Get(2321).vbLimited, nil)
  T.eq(I.Get(4470).vb, 7, "floor(38 / 5) = floor(7.6) = 7")
  T.eq(I.Get(2604).vb, 50) T.eq(I.Get(2604).vbLimited, true)
  T.eq(I.Get(2321).n, "Fine Thread", "the name is remembered too")
end)

T.test("merchant items with no link or a non-gold price are skipped", function()
  WoW.merchant = {
    { id = 2321, name = "Fine Thread", price = 100, quantity = 1, noLink = true },
    { id = 19182, name = "Darkmoon Faire Prize Ticket", price = 0, quantity = 1 },
  }
  I.LearnMerchantPrices()
  T.eq(I.Get(2321), nil)
  T.eq(I.Get(19182), nil)
end)
```

In `tests/test_core.lua`, insert this test directly before `T.test("watch, list and unwatch by name", ...)`:
```lua
T.test("opening a merchant learns what it sells, and for how much", function()
  WoW.merchant = { { id = 2321, name = "Fine Thread", price = 100, quantity = 1, numAvailable = -1 } }
  WoW.merchantOpen = true
  WoW.fire("MERCHANT_SHOW")
  T.eq(A.Items.Get(2321).vb, 100)
end)
```

`tests/test_inventory.lua`:
```lua
local A = TaxTheFools
local Inv, DB, C = A.Inventory, A.DB, A.Craft

local function tick() WoW.runScript(TaxTheFoolsCore, "OnUpdate") end

T.test("bags 0 to 4 are counted per item key, stacks added together", function()
  WoW.bags[0] = { { id = 4306, name = "Silk Cloth", count = 20 }, {}, { id = 4306, name = "Silk Cloth", count = 17 } }
  WoW.bags[4] = { { id = 2321, name = "Fine Thread", count = 5 } }
  WoW.fire("BAG_UPDATE", 0)
  tick()
  local c = DB.Char()
  T.eq(c.bags["4306:0"], 37, "20 + 17")
  T.eq(c.bags["2321:0"], 5)
  T.eq(c.bagsAt, WoW.now)
end)

T.test("a burst of bag updates is counted at most once a second", function()
  WoW.bags[0] = { { id = 4306, name = "Silk Cloth", count = 20 } }
  WoW.fire("BAG_UPDATE", 0)
  tick()
  T.eq(DB.Char().bags["4306:0"], 20)
  WoW.bags[0][1].count = 10
  WoW.fire("BAG_UPDATE", 0)
  WoW.clock = WoW.clock + 0.5
  tick()
  T.eq(DB.Char().bags["4306:0"], 20, "half a second later: not yet")
  WoW.clock = WoW.clock + 0.5
  tick()
  T.eq(DB.Char().bags["4306:0"], 10, "a second later: counted")
end)

T.test("the bank is recorded only while it is open", function()
  WoW.bags[-1] = { { id = 4306, name = "Silk Cloth", count = 100 } }
  WoW.bags[5] = { { id = 4306, name = "Silk Cloth", count = 20 }, { id = 4339, name = "Bolt of Mageweave", count = 3 } }
  Inv.ScanBank()
  T.eq(DB.Char().bank, nil, "closed: nothing read")
  WoW.bankOpen = true
  WoW.fire("BANKFRAME_OPENED")
  T.eq(DB.Char().bank["4306:0"], 120, "100 in the bank slots + 20 in bank bag 5")
  T.eq(DB.Char().bank["4339:0"], 3)
  T.eq(DB.Char().bags, nil, "bank items are not counted as carried")
  WoW.fire("BANKFRAME_CLOSED")
  WoW.bankOpen = false
  WoW.fire("BAG_UPDATE", 0)
  WoW.clock = WoW.clock + 2
  tick()
  T.eq(DB.Char().bank["4306:0"], 120, "a bag update after closing leaves the bank record alone")
end)

T.test("changes while the bank is open are recorded", function()
  WoW.bankOpen = true
  WoW.bags[-1] = { { id = 4306, name = "Silk Cloth", count = 100 } }
  WoW.fire("BANKFRAME_OPENED")
  WoW.bags[-1][1].count = 60
  WoW.fire("PLAYERBANKSLOTS_CHANGED")
  WoW.clock = WoW.clock + 2
  tick()
  T.eq(DB.Char().bank["4306:0"], 60)
end)

T.test("holdings add up bags and bank across every character", function()
  local chars = DB.Realm().chars
  chars.Bankalt = { bags = { ["4306:0"] = 3 }, bank = { ["4306:0"] = 100, ["2321:0"] = 2 } }
  chars.Tailor = { bags = { ["4306:0"] = 7 } }
  chars.Empty = {}
  local held = Inv.Held(DB.Realm())
  T.eq(held["4306:0"], 110, "3 + 100 + 7")
  T.eq(held["2321:0"], 2)
end)

T.test("cash profit counts what two characters hold between them", function()
  local realm = DB.Realm()
  realm.market["4306:0"] = { v = 300 }
  realm.market["4305:0"] = { v = 2000 }
  realm.chars.Bankalt = { bank = { ["4306:0"] = 1 } }
  realm.chars.Tailor = { bags = { ["4306:0"] = 2 }, professions = { Tailoring = { recipes = {} } } }
  local bolt = { item = "4305:0", reagents = { { item = "4306:0", count = 4 } } }
  local ev = C.Evaluate(bolt, C.Context(realm, TaxTheFoolsDB.items, Inv.Held(realm), 20375))
  T.eq(ev.lines[1].have, 3, "1 + 2")
  T.near(ev.cash, 1600, 0.001, "2000 x 0.95 - (4 - 3) x 300")
end)

T.test("bags are counted at login", function()
  WoW.bags[0] = { { id = 4306, name = "Silk Cloth", count = 4 } }
  WoW.fire("PLAYER_ENTERING_WORLD")
  tick()
  T.eq(DB.Char().bags["4306:0"], 4)
end)
```

- [ ] **Step 3: Run them to verify they fail**

Run: `make test`
Expected: `151 passed, 10 failed`: the two new item tests (`attempt to call field 'LearnMerchantPrices'`), the core merchant test and all seven inventory tests (`attempt to index a nil value`).

- [ ] **Step 4: Implement vendor buy prices**

In `TaxTheFools/items.lua`, insert before `function I.FindByName(name)`:
```lua
-- What the open merchant sells. price covers `quantity` units (some vendors
-- sell in fives); a merchant with limited stock is still used, but flagged.
-- Items costing something other than gold read price 0 and are skipped.
function I.LearnMerchantPrices()
  for i = 1, GetMerchantNumItems() do
    local name, texture, price, quantity, numAvailable = GetMerchantItemInfo(i)
    local id = U.parseLink(GetMerchantItemLink(i))
    if id and price and price > 0 and quantity and quantity > 0 then
      local rec = I.Remember(id, name, nil, nil, texture)
      rec.vb = math.floor(price / quantity)
      if numAvailable and numAvailable >= 0 then rec.vbLimited = true else rec.vbLimited = nil end
    end
  end
end
```

- [ ] **Step 5: Implement the inventory**

`TaxTheFools/inventory.lua`:
```lua
TaxTheFools = TaxTheFools or {}
local U, DB = TaxTheFools.Util, TaxTheFools.DB
local Inv = { bankOpen = false, bagsDirty = false, bankDirty = false, scannedAt = -1000 }
TaxTheFools.Inventory = Inv

Inv.BAGS = { 0, 1, 2, 3, 4 }
Inv.BANK = { -1, 5, 6, 7, 8, 9, 10 }   -- the bank's own slots, then its bag slots
Inv.THROTTLE = 1                        -- seconds between counts; BAG_UPDATE comes in bursts

function Inv.ResetState()
  Inv.bankOpen, Inv.bagsDirty, Inv.bankDirty, Inv.scannedAt = false, false, false, -1000
end

function Inv.Count(bags)
  local counts = {}
  for _, bag in ipairs(bags) do
    for slot = 1, GetContainerNumSlots(bag) do
      local key = U.keyFromLink(GetContainerItemLink(bag, slot))
      if key then
        local _, n = GetContainerItemInfo(bag, slot)
        counts[key] = (counts[key] or 0) + (n or 1)
      end
    end
  end
  return counts
end

function Inv.ScanBags()
  local c = DB.Char()
  c.bags, c.bagsAt = Inv.Count(Inv.BAGS), time()
end

-- The bank can only be read while its window is open; closed, it reads as
-- empty, and recording that would wipe what is really there.
function Inv.ScanBank()
  if not Inv.bankOpen then return end
  local c = DB.Char()
  c.bank, c.bankAt = Inv.Count(Inv.BANK), time()
end

function Inv.OnEvent(e)
  if e == "BANKFRAME_OPENED" then
    Inv.bankOpen = true
    Inv.ScanBank()
  elseif e == "BANKFRAME_CLOSED" then
    Inv.bankOpen, Inv.bankDirty = false, false
  elseif e == "PLAYERBANKSLOTS_CHANGED" then
    if Inv.bankOpen then Inv.bankDirty = true end
  elseif e == "BAG_UPDATE" then
    Inv.bagsDirty = true
    if Inv.bankOpen then Inv.bankDirty = true end
  elseif e == "PLAYER_ENTERING_WORLD" then
    Inv.bagsDirty = true
  end
end

function Inv.Tick(now)
  if not Inv.bagsDirty and not Inv.bankDirty then return end
  if now - Inv.scannedAt < Inv.THROTTLE then return end
  Inv.scannedAt = now
  if Inv.bagsDirty then
    Inv.bagsDirty = false
    Inv.ScanBags()
  end
  if Inv.bankDirty then
    Inv.bankDirty = false
    Inv.ScanBank()
  end
end

local function add(held, counts)
  for key, n in pairs(counts or {}) do held[key] = (held[key] or 0) + n end
end

-- Everything every character on the realm holds, bags and bank together.
function Inv.Held(realm)
  local held = {}
  for _, c in pairs(realm.chars or {}) do
    add(held, c.bags)
    add(held, c.bank)
  end
  return held
end
```

In `TaxTheFools/TaxTheFools.toc`, add the line `inventory.lua` directly after `items.lua` (line 16, before `scan.lua`).

- [ ] **Step 6: Wire them into the core**

In `TaxTheFools/core.lua`:

In `Core.Init`, replace:
```lua
  DB.StartPrune()
  Core.pruned = false
  Core.ready = true
```
with:
```lua
  DB.StartPrune()
  Core.pruned = false
  A.Inventory.bagsDirty = true      -- count the bags once at login, whichever event comes first
  Core.ready = true
```

Replace the line `function Core.OnEvent(e)` with:
```lua
Core.INVENTORY_EVENTS = { BAG_UPDATE = true, BANKFRAME_OPENED = true, BANKFRAME_CLOSED = true,
                          PLAYERBANKSLOTS_CHANGED = true, PLAYER_ENTERING_WORLD = true }

function Core.OnEvent(e)
```

Inside `Core.OnEvent`, replace:
```lua
  elseif e == "MERCHANT_SHOW" then Core.Safe("items", A.Items.LearnVendorPrices)
```
with:
```lua
  elseif e == "MERCHANT_SHOW" then
    Core.Safe("items", A.Items.LearnVendorPrices)
    Core.Safe("items", A.Items.LearnMerchantPrices)
  elseif Core.INVENTORY_EVENTS[e] then Core.Safe("inventory", A.Inventory.OnEvent, e)
```

In `Core.Update`, replace:
```lua
  Core.Safe("scan", A.Scan.Tick, now)
```
with:
```lua
  Core.Safe("scan", A.Scan.Tick, now)
  Core.Safe("inventory", A.Inventory.Tick, now)
```

In the event registration at the bottom, replace:
```lua
                     "MERCHANT_SHOW", "PLAYER_MONEY" }) do
```
with:
```lua
                     "MERCHANT_SHOW", "PLAYER_MONEY", "BAG_UPDATE", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
                     "PLAYERBANKSLOTS_CHANGED", "PLAYER_ENTERING_WORLD" }) do
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `make test`
Expected: `161 passed, 0 failed` (151 + 2 in `test_items.lua` + 1 in `test_core.lua` + 7 in `test_inventory.lua`).

- [ ] **Step 8: Commit**

```bash
git add TaxTheFools/items.lua TaxTheFools/inventory.lua TaxTheFools/core.lua TaxTheFools/TaxTheFools.toc tests/wow_stub.lua tests/test_items.lua tests/test_core.lua tests/test_inventory.lua
git commit -m "feat: vendor buy prices at merchants, bag and bank inventory per character"
```

---

### Task 3: Capture recipes from the tradeskill window, with auto-watch

**Files:**
- Modify: `tests/wow_stub.lua` (reset; tradeskill API after `BuyMerchantItem`)
- Modify: `TaxTheFools/util.lua:74` (new function before `U.linkString`)
- Modify: `TaxTheFools/data.lua:34` (`settings.craft` defaults)
- Create: `TaxTheFools/tradeskill.lua`
- Modify: `TaxTheFools/TaxTheFools.toc` (add `tradeskill.lua` after `tooltip.lua`, line 23)
- Modify: `TaxTheFools/core.lua` (OnEvent, Update, event list)
- Test: `tests/test_util.lua`, `tests/test_tradeskill.lua` (new)

**Interfaces:**
- Consumes: `I.Remember`, `I.Vendor(id)`, `U.keyFromLink`, `DB.Char()`, `DB.Realm().watch`, `DB.S()`.
- Produces:
  - `U.linkName(link) -> string|nil`
  - `settings.craft = { autoWatch = true, staleDays = 7 }` (defaults; `staleDays` is used in Task 5)
  - `TaxTheFools.TradeSkill` (`TS`): `TS.THROTTLE = 0.5`, `TS.ReadRecipe(i) -> recipe`, `TS.Capture() -> prof|nil` (writes `char.professions[line] = { rank, maxRank, at, recipes = { [recipeName] = recipe } }`), `TS.Watch(recipes)`, `TS.OnEvent(event, now)`, `TS.Tick(now)`. Fields `TS.open`, `TS.dirty`, `TS.capturedAt`.
  - Recipe shape as in Task 1, with `color` = the `GetTradeSkillInfo` type and every reagent `{ item = key|nil, name, count }`.
  - Stub: `WoW.tradeskill = { name, rank, maxRank, selected, rows }`, `GetTradeSkillLine`, `GetNumTradeSkills`, `GetTradeSkillInfo`, `GetTradeSkillItemLink`, `GetTradeSkillNumMade`, `GetTradeSkillNumReagents`, `GetTradeSkillReagentInfo`, `GetTradeSkillReagentItemLink`, `GetTradeSkillSelectionIndex`, logged `DoTradeSkill`.

- [ ] **Step 1: Extend the fake client with the tradeskill API**

These follow 1.12 exactly: `GetTradeSkillInfo(i)` returns name, type (`"header"`, `"optimal"`, `"medium"`, `"easy"`, `"trivial"`), numAvailable, isExpanded; `GetTradeSkillLine()` returns name, rank, maxRank (`"UNKNOWN"` with no window); `GetTradeSkillNumMade(i)` returns min, max; `GetTradeSkillReagentInfo(i, r)` returns name, texture, count, playerCount. A collapsed header hides the rows under it from every call, as in the real list.

In `tests/wow_stub.lua`, inside `WoW.reset()`, replace:
```lua
  WoW.bankOpen = false
```
with:
```lua
  WoW.bankOpen = false
  WoW.tradeskill = { name = "Tailoring", rank = 0, maxRank = 0, selected = 0, rows = {} }
```

Directly after the line `function BuyMerchantItem(i, n) WoW.log("BuyMerchantItem", i, n) end` add:
```lua
-- ---------- tradeskill window ----------
-- WoW.tradeskill = { name=, rank=, maxRank=, selected=, rows = {
--   { header = true, name = "Cloth", collapsed = nil|true },
--   { name = "Bolt of Silk Cloth", type = "medium", id = 4305, made = { 1, 1 }, available = 2, noLink = nil|true,
--     reagents = { { id = 4306, name = "Silk Cloth", count = 4, have = 37, noLink = nil|true } } } } }
-- Like the real list, a collapsed header hides the recipes under it from every call below.
local function tsRows()
  local out, hide = {}, false
  for _, r in ipairs(WoW.tradeskill.rows) do
    if r.header then
      hide = r.collapsed and true or false
      table.insert(out, r)
    elseif not hide then
      table.insert(out, r)
    end
  end
  return out
end
local function tsRow(i)
  local rows = tsRows()
  return rows[i]
end
function GetTradeSkillLine()
  local t = WoW.tradeskill
  return t.name or "UNKNOWN", t.rank or 0, t.maxRank or 0
end
function GetNumTradeSkills() return table.getn(tsRows()) end
function GetTradeSkillInfo(i)
  local r = tsRow(i)
  if not r then return nil end
  if r.header then
    if r.collapsed then return r.name, "header", 0, nil end
    return r.name, "header", 0, 1
  end
  return r.name, r.type or "medium", r.available or 0, nil
end
function GetTradeSkillItemLink(i)
  local r = tsRow(i)
  if r and r.id and not r.noLink then return WoW.link(r.id, r.product or r.name) end
  return nil
end
function GetTradeSkillNumMade(i)
  local r = tsRow(i)
  if not r or r.header then return 0, 0 end
  local m = r.made or { 1, 1 }
  return m[1], m[2]
end
function GetTradeSkillNumReagents(i)
  local r = tsRow(i)
  if not r or not r.reagents then return 0 end
  return table.getn(r.reagents)
end
function GetTradeSkillReagentInfo(i, n)
  local r = tsRow(i)
  local g = r and r.reagents and r.reagents[n]
  if not g then return nil end
  return g.name, g.tex or "tex", g.count or 1, g.have or 0
end
function GetTradeSkillReagentItemLink(i, n)
  local r = tsRow(i)
  local g = r and r.reagents and r.reagents[n]
  if g and g.id and not g.noLink then return WoW.link(g.id, g.name) end
  return nil
end
function GetTradeSkillSelectionIndex() return WoW.tradeskill.selected or 0 end
function DoTradeSkill(i, n) WoW.log("DoTradeSkill", i, n) end
```

Run: `make test`
Expected: `161 passed, 0 failed`.

- [ ] **Step 2: Write the failing tests**

Append to `tests/test_util.lua`:
```lua

T.test("the name is read from between a link's brackets", function()
  T.eq(U.linkName(WoW.link(4305, "Bolt of Silk Cloth")), "Bolt of Silk Cloth")
  T.eq(U.linkName(nil), nil)
end)
```

`tests/test_tradeskill.lua`:
```lua
local A = TaxTheFools
local TS, DB = A.TradeSkill, A.DB

local function tick() WoW.runScript(TaxTheFoolsCore, "OnUpdate") end

-- Two headers and two recipes, as the Tailoring window lists them.
local function tailoring()
  WoW.tradeskill = { name = "Tailoring", rank = 225, maxRank = 300, selected = 0, rows = {
    { header = true, name = "Cloth" },
    { name = "Bolt of Silk Cloth", type = "medium", id = 4305, made = { 1, 1 }, available = 9,
      reagents = { { id = 4306, name = "Silk Cloth", count = 4, have = 37 } } },
    { header = true, name = "Robes" },
    { name = "Brown Linen Robe", type = "trivial", id = 6238, made = { 1, 1 },
      reagents = { { id = 2996, name = "Bolt of Linen Cloth", count = 3 }, { id = 2320, name = "Coarse Thread", count = 2 } } },
  } }
end

local function tailoringRecipes() return DB.Char().professions.Tailoring.recipes end

T.test("opening the window captures every recipe, skipping headers", function()
  tailoring()
  WoW.fire("TRADE_SKILL_SHOW")
  local prof = DB.Char().professions.Tailoring
  T.eq(prof.rank, 225) T.eq(prof.maxRank, 300) T.eq(prof.at, WoW.now)
  local n = 0
  for _ in pairs(prof.recipes) do n = n + 1 end
  T.eq(n, 2, "two recipes, no headers")
  T.eq(prof.recipes.Cloth, nil)
  local bolt = prof.recipes["Bolt of Silk Cloth"]
  T.eq(bolt.item, "4305:0") T.eq(bolt.color, "medium") T.eq(bolt.yieldMin, 1) T.eq(bolt.yieldMax, 1)
  T.eq(bolt.reagents[1].item, "4306:0") T.eq(bolt.reagents[1].count, 4) T.eq(bolt.reagents[1].name, "Silk Cloth")
  T.eq(table.getn(prof.recipes["Brown Linen Robe"].reagents), 2)
  T.eq(A.Items.Get(4305).n, "Bolt of Silk Cloth", "the product is remembered by its link's name")
  T.eq(A.Items.Get(2320).n, "Coarse Thread", "and every reagent")
end)

T.test("a recapture replaces the recipes, so unlearned ones go", function()
  tailoring()
  WoW.fire("TRADE_SKILL_SHOW")
  table.remove(WoW.tradeskill.rows, 4)
  WoW.fire("TRADE_SKILL_UPDATE")
  WoW.clock = WoW.clock + 0.5
  tick()
  T.eq(tailoringRecipes()["Brown Linen Robe"], nil)
  T.ok(tailoringRecipes()["Bolt of Silk Cloth"])
end)

T.test("updates are captured at most twice a second", function()
  tailoring()
  WoW.fire("TRADE_SKILL_SHOW")
  WoW.tradeskill.rank = 226
  WoW.fire("TRADE_SKILL_UPDATE")
  WoW.clock = WoW.clock + 0.2
  tick()
  T.eq(DB.Char().professions.Tailoring.rank, 225, "0.2s later: not yet")
  WoW.clock = WoW.clock + 0.3
  tick()
  T.eq(DB.Char().professions.Tailoring.rank, 226, "0.5s later: captured")
  WoW.fire("TRADE_SKILL_CLOSE")
  WoW.tradeskill.rank = 227
  WoW.fire("TRADE_SKILL_UPDATE")
  WoW.clock = WoW.clock + 1
  tick()
  T.eq(DB.Char().professions.Tailoring.rank, 226, "nothing is read once the window has closed")
end)

T.test("a reagent with no cached link is stored by name, then filled in", function()
  tailoring()
  WoW.tradeskill.rows[2].reagents[1].noLink = true
  WoW.fire("TRADE_SKILL_SHOW")
  local g = tailoringRecipes()["Bolt of Silk Cloth"].reagents[1]
  T.eq(g.item, nil) T.eq(g.name, "Silk Cloth") T.eq(g.count, 4)
  WoW.tradeskill.rows[2].reagents[1].noLink = nil
  WoW.fire("TRADE_SKILL_UPDATE")
  WoW.clock = WoW.clock + 0.5
  tick()
  T.eq(tailoringRecipes()["Bolt of Silk Cloth"].reagents[1].item, "4306:0")
end)

T.test("with auto-watch on, products and materials join the watchlist", function()
  tailoring()
  WoW.fire("TRADE_SKILL_SHOW")
  local w = DB.Realm().watch
  T.ok(w["4305:0"]) T.ok(w["4306:0"]) T.ok(w["6238:0"]) T.ok(w["2996:0"]) T.ok(w["2320:0"])
end)

T.test("with auto-watch off, the watchlist is left alone", function()
  DB.S().craft.autoWatch = false
  tailoring()
  WoW.fire("TRADE_SKILL_SHOW")
  T.eq(next(DB.Realm().watch), nil)
  T.ok(tailoringRecipes()["Bolt of Silk Cloth"], "recipes are still captured")
end)

T.test("recipes hidden under a collapsed header are kept, not dropped", function()
  tailoring()
  WoW.fire("TRADE_SKILL_SHOW")
  WoW.tradeskill.rows[3].collapsed = true
  WoW.fire("TRADE_SKILL_UPDATE")
  WoW.clock = WoW.clock + 0.5
  tick()
  T.ok(tailoringRecipes()["Brown Linen Robe"], "still there while its header is collapsed")
  T.ok(tailoringRecipes()["Bolt of Silk Cloth"])
end)

T.test("a list that reads empty leaves the stored recipes alone", function()
  tailoring()
  WoW.fire("TRADE_SKILL_SHOW")
  local rows = WoW.tradeskill.rows
  WoW.tradeskill.rows = {}
  WoW.fire("TRADE_SKILL_CLOSE")
  WoW.fire("TRADE_SKILL_SHOW")
  WoW.clock = WoW.clock + 0.5
  tick()
  T.ok(tailoringRecipes()["Bolt of Silk Cloth"], "the first open after login can list nothing yet")
  WoW.tradeskill.rows = rows
end)
```

- [ ] **Step 3: Run them to verify they fail**

Run: `make test`
Expected: `161 passed, 9 failed`: the `linkName` test (`attempt to call field 'linkName'`) and all eight tradeskill tests (nothing captures yet, so `professions` is nil; with no `settings.craft`, the auto-watch-off test fails on `DB.S().craft`).

- [ ] **Step 4: Implement**

In `TaxTheFools/util.lua`, insert before `function U.linkString(link)`:
```lua
-- The name between the brackets of an item link: "|H...|h[Bolt of Silk Cloth]|h|r".
function U.linkName(link)
  local _, _, n = string.find(link or "", "%[(.-)%]")
  return n
end

```

In `TaxTheFools/data.lua`, inside `D.DEFAULTS.settings`, replace:
```lua
    tooltip = { market = true, low = true, vendor = true },
```
with:
```lua
    tooltip = { market = true, low = true, vendor = true },
    craft = { autoWatch = true, staleDays = 7 },
```

`TaxTheFools/tradeskill.lua`:
```lua
TaxTheFools = TaxTheFools or {}
local U, DB, I = TaxTheFools.Util, TaxTheFools.DB, TaxTheFools.Items
local TS = { open = false, dirty = false, capturedAt = -1000 }
TaxTheFools.TradeSkill = TS

TS.THROTTLE = 0.5    -- seconds between captures; TRADE_SKILL_UPDATE fires in bursts

function TS.ResetState() TS.open, TS.dirty, TS.capturedAt = false, false, -1000 end

-- Every item seen in the window is remembered account-wide, so its name is
-- known to the watchlist scan and the Crafting page on every character.
local function remember(link, name, texture)
  local key, id = U.keyFromLink(link)
  if not key then return nil end
  I.Remember(id, name, nil, nil, texture)
  return key, id
end

-- One recipe row. A reagent whose link is not cached yet is kept by name
-- with no item key; the next capture fills it in.
function TS.ReadRecipe(i)
  local link = GetTradeSkillItemLink(i)
  local key, id = remember(link, U.linkName(link))
  if id then I.Vendor(id) end          -- ClassicAPI supplies the sell price the deposit needs
  local lo, hi = GetTradeSkillNumMade(i)
  if not lo or lo < 1 then lo = 1 end
  if not hi or hi < lo then hi = lo end
  local r = { item = key, yieldMin = lo, yieldMax = hi, reagents = {} }
  for n = 1, GetTradeSkillNumReagents(i) do
    local name, texture, count = GetTradeSkillReagentInfo(i, n)
    local rkey = remember(GetTradeSkillReagentItemLink(i, n), name, texture)
    table.insert(r.reagents, { item = rkey, name = name, count = count or 1 })
  end
  return r
end

-- Reads the open window into this character's professions. The recipe table
-- is replaced, so unlearned recipes go, with two exceptions that protect what
-- is stored: a list that reads empty (the client has not sent it yet) changes
-- nothing, and recipes hidden under a collapsed header are kept.
function TS.Capture()
  local line, rank, maxRank = GetTradeSkillLine()
  if not line or line == "UNKNOWN" then return nil end
  local recipes, found, collapsed = {}, 0, false
  for i = 1, GetNumTradeSkills() do
    local name, kind, _, expanded = GetTradeSkillInfo(i)
    if kind == "header" then
      if not expanded then collapsed = true end
    elseif name then
      local r = TS.ReadRecipe(i)
      r.color = kind
      recipes[name] = r
      found = found + 1
    end
  end
  if found == 0 then return nil end
  local c = DB.Char()
  c.professions = c.professions or {}
  local prof = c.professions[line]
  if not prof then
    prof = {}
    c.professions[line] = prof
  end
  if collapsed and prof.recipes then
    for name, r in pairs(prof.recipes) do
      if not recipes[name] then recipes[name] = r end
    end
  end
  prof.rank, prof.maxRank, prof.at, prof.recipes = rank, maxRank, time(), recipes
  if DB.S().craft.autoWatch then TS.Watch(recipes) end
  return prof
end

function TS.Watch(recipes)
  local watch = DB.Realm().watch
  for _, r in pairs(recipes) do
    if r.item then watch[r.item] = true end
    for _, g in ipairs(r.reagents) do
      if g.item then watch[g.item] = true end
    end
  end
end

function TS.OnEvent(e, now)
  if e == "TRADE_SKILL_SHOW" then
    TS.open, TS.dirty = true, true
    TS.Tick(now)
  elseif e == "TRADE_SKILL_UPDATE" then
    TS.dirty = true
  elseif e == "TRADE_SKILL_CLOSE" then
    TS.open, TS.dirty = false, false
  end
end

function TS.Tick(now)
  if not TS.open or not TS.dirty then return end
  if now - TS.capturedAt < TS.THROTTLE then return end
  TS.dirty, TS.capturedAt = false, now
  TS.Capture()
end
```

In `TaxTheFools/TaxTheFools.toc`, add the line `tradeskill.lua` directly after `tooltip.lua` (line 23, before `ui_window.lua`). It sits this late because Task 4 gives it the strip, which needs `theme.lua`.

In `TaxTheFools/core.lua`, inside `Core.OnEvent`, replace:
```lua
  elseif Core.INVENTORY_EVENTS[e] then Core.Safe("inventory", A.Inventory.OnEvent, e)
```
with:
```lua
  elseif Core.INVENTORY_EVENTS[e] then Core.Safe("inventory", A.Inventory.OnEvent, e)
  elseif e == "TRADE_SKILL_SHOW" or e == "TRADE_SKILL_UPDATE" or e == "TRADE_SKILL_CLOSE" then
    Core.Safe("tradeskill", A.TradeSkill.OnEvent, e, GetTime())
```

In `Core.Update`, replace:
```lua
  Core.Safe("inventory", A.Inventory.Tick, now)
```
with:
```lua
  Core.Safe("inventory", A.Inventory.Tick, now)
  Core.Safe("tradeskill", A.TradeSkill.Tick, now)
```

In the event registration, replace:
```lua
                     "PLAYERBANKSLOTS_CHANGED", "PLAYER_ENTERING_WORLD" }) do
```
with:
```lua
                     "PLAYERBANKSLOTS_CHANGED", "PLAYER_ENTERING_WORLD", "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE",
                     "TRADE_SKILL_CLOSE" }) do
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `make test`
Expected: `170 passed, 0 failed` (161 + 1 in `test_util.lua` + 8 in `test_tradeskill.lua`).

- [ ] **Step 6: Commit**

```bash
git add TaxTheFools/util.lua TaxTheFools/data.lua TaxTheFools/tradeskill.lua TaxTheFools/core.lua TaxTheFools/TaxTheFools.toc tests/wow_stub.lua tests/test_util.lua tests/test_tradeskill.lua
git commit -m "feat: capture learned recipes from the tradeskill window, auto-watch their materials"
```

---

### Task 4: The profit strip under the tradeskill window

**Files:**
- Modify: `tests/wow_stub.lua` (load-on-demand `TradeSkillFrame`, reset)
- Modify: `TaxTheFools/tradeskill.lua` (locals, constants, capture and show hooks, strip functions appended)
- Modify: `TaxTheFools/core.lua` (0.25 s poll in `Core.Update`)
- Test: `tests/test_tradeskill.lua` (appended)

**Interfaces:**
- Consumes: `Craft.Context`, `Craft.Evaluate` (Task 1), `Inv.Held` (Task 2), `TS.Capture` (Task 3), `Th.Panel`, `Th.Text`, `Th.Color`, `U.money(c, plain)`, `GetTradeSkillSelectionIndex()`.
- Produces:
  - `TS.STRIP_X, TS.STRIP_Y, TS.STRIP_W` (14, 73, 330)
  - `TS.Context() -> ctx` — the realm's prices, all recipes and combined holdings, for today. **Task 5's Crafting page uses this too.**
  - `TS.CreateStrip() -> frame|nil` (`TaxTheFoolsStrip`, fields `text`, `sel`)
  - `TS.StripText(ev|nil) -> text, token`
  - `TS.Selected() -> recipe|nil`
  - `TS.RefreshStrip(force)`, `TS.Poll(now)`
  - `TS.strip` (the frame, or nil before the first open)
  - Stub: `WoW.openTradeSkill()` creates `TradeSkillFrame` on first use, shows it and fires `TRADE_SKILL_SHOW`.

- [ ] **Step 1: Make TradeSkillFrame load on demand in the fake client**

In `tests/wow_stub.lua`, directly after the line `function DoTradeSkill(i, n) WoW.log("DoTradeSkill", i, n) end` add:
```lua
-- TradeSkillFrame is load-on-demand: it does not exist until the first
-- tradeskill window opens. WoW.openTradeSkill() does what the client does:
-- load it if needed, show it, then fire TRADE_SKILL_SHOW.
function WoW.openTradeSkill()
  if not TradeSkillFrame then
    TradeSkillFrame = newFrame("Frame", "TradeSkillFrame", UIParent)
    TradeSkillFrame.shown = false
  end
  TradeSkillFrame:Show()
  WoW.fire("TRADE_SKILL_SHOW")
end
```

Inside `WoW.reset()`, replace:
```lua
  if AuctionFrame then AuctionFrame.shown = false end
```
with:
```lua
  if AuctionFrame then AuctionFrame.shown = false end
  if TradeSkillFrame then TradeSkillFrame.shown = false end
```

Run: `make test`
Expected: `170 passed, 0 failed`.

- [ ] **Step 2: Write the failing tests**

Append to `tests/test_tradeskill.lua`:
```lua
-- ---------- the profit strip ----------

local function priced()
  DB.Realm().market["4306:0"] = { v = 300, lowDay = 20375 }    -- Silk Cloth
  DB.Realm().market["4305:0"] = { v = 2000, lowDay = 20375 }   -- Bolt of Silk Cloth
  DB.Realm().market["6238:0"] = { v = 900, lowDay = 20375 }    -- Brown Linen Robe; its bolts and thread have no price
end

T.test("the strip is made under TradeSkillFrame when the window first opens", function()
  local savedFrame, savedStrip = TradeSkillFrame, TS.strip
  TradeSkillFrame, TS.strip = nil, nil
  tailoring()
  WoW.fire("TRADE_SKILL_SHOW")
  T.eq(TS.strip, nil, "no TradeSkillFrame loaded yet: no strip, no error")
  T.ok(not T.calledWith("stopped after an error"))
  TradeSkillFrame, TS.strip = savedFrame, savedStrip
  WoW.openTradeSkill()
  local s = TS.strip
  T.ok(s, "made once the frame exists")
  T.eq(s:GetParent(), TradeSkillFrame)
  local p = s.points[1]
  T.eq(p[1], "TOPLEFT") T.eq(p[2], TradeSkillFrame) T.eq(p[3], "BOTTOMLEFT")
  T.eq(s:GetHeight(), 22)
  T.ok(s:IsVisible(), "shown with the window")
end)

T.test("strip text: cost, value and profit coloured by sign, or what is missing", function()
  local text, token = TS.StripText({ cost = 1200, value = 1900, valueSource = "ah", profit = 700, missing = {} })
  T.eq(text, "Cost 12s   Value 19s   Profit 7s") T.eq(token, "good")
  text, token = TS.StripText({ cost = 1200, value = 250, valueSource = "vendor", profit = -950, missing = {} })
  T.eq(text, "Cost 12s   Value 2s 50c (vendor)   Profit -9s 50c", "250 - 1200 = -950") T.eq(token, "bad")
  text, token = TS.StripText({ value = 900, missing = { "Bolt of Linen Cloth", "Coarse Thread" } })
  T.eq(text, "incomplete: Bolt of Linen Cloth, Coarse Thread") T.eq(token, "warn")
  text, token = TS.StripText(nil)
  T.eq(token, "dim")
end)

T.test("the strip shows the selected recipe's profit and follows the selection without an event", function()
  priced()
  tailoring()
  WoW.tradeskill.selected = 2                    -- Bolt of Silk Cloth
  WoW.openTradeSkill()
  -- cost 4 x 300 = 1200; value 2000 x 0.95 = 1900 (no vendor price, so no deposit); profit 700
  T.eq(TS.strip.text:GetText(), "Cost 12s   Value 19s   Profit 7s")
  T.eq(TS.strip.text.color[1], A.Theme.color.good[1])
  WoW.tradeskill.selected = 4                    -- Brown Linen Robe
  WoW.clock = WoW.clock + 0.25
  tick()
  T.eq(TS.strip.text:GetText(), "incomplete: Bolt of Linen Cloth, Coarse Thread")
  WoW.tradeskill.selected = 1                    -- a header
  WoW.clock = WoW.clock + 0.25
  tick()
  T.eq(TS.strip.text:GetText(), "Select a recipe to see its profit.")
end)

T.test("the strip repaints after a recapture even when the selection stays", function()
  priced()
  tailoring()
  WoW.tradeskill.selected = 2
  WoW.openTradeSkill()
  DB.Realm().market["4305:0"] = { v = 1000, lowDay = 20375 }
  WoW.fire("TRADE_SKILL_UPDATE")
  WoW.clock = WoW.clock + 0.5
  tick()
  -- value 1000 x 0.95 = 950; profit 950 - 1200 = -250
  T.eq(TS.strip.text:GetText(), "Cost 12s   Value 9s 50c   Profit -2s 50c")
  T.eq(TS.strip.text.color[1], A.Theme.color.bad[1])
end)
```

- [ ] **Step 3: Run them to verify they fail**

Run: `make test`
Expected: `170 passed, 4 failed` (no strip is made yet; `TS.StripText` does not exist).

- [ ] **Step 4: Implement the strip**

In `TaxTheFools/tradeskill.lua`:

Replace the header:
```lua
local U, DB, I = TaxTheFools.Util, TaxTheFools.DB, TaxTheFools.Items
local TS = { open = false, dirty = false, capturedAt = -1000 }
```
with:
```lua
local U, DB, I, Th, Craft, Inv = TaxTheFools.Util, TaxTheFools.DB, TaxTheFools.Items, TaxTheFools.Theme,
  TaxTheFools.Craft, TaxTheFools.Inventory
local TS = { open = false, dirty = false, capturedAt = -1000, strip = nil }
```

Replace:
```lua
TS.THROTTLE = 0.5    -- seconds between captures; TRADE_SKILL_UPDATE fires in bursts
```
with:
```lua
TS.THROTTLE = 0.5    -- seconds between captures; TRADE_SKILL_UPDATE fires in bursts
-- TradeSkillFrame is 384x512 but its art leaves the bottom 75px and right 34px
-- transparent (its HitRectInsets): the strip sits just under the visible panel.
TS.STRIP_X, TS.STRIP_Y, TS.STRIP_W = 14, 73, 330
```

At the end of `TS.Capture`, replace:
```lua
  if DB.S().craft.autoWatch then TS.Watch(recipes) end
  return prof
```
with:
```lua
  if DB.S().craft.autoWatch then TS.Watch(recipes) end
  TS.RefreshStrip(true)
  return prof
```

In `TS.OnEvent`, replace:
```lua
  if e == "TRADE_SKILL_SHOW" then
    TS.open, TS.dirty = true, true
    TS.Tick(now)
```
with:
```lua
  if e == "TRADE_SKILL_SHOW" then
    TS.open, TS.dirty = true, true
    TS.CreateStrip()
    TS.Tick(now)
    TS.RefreshStrip(true)
```

Append to the end of the file:
```lua
-- ---------- the profit strip under the tradeskill window ----------

-- Prices, every character's recipes and everything held, as of now.
function TS.Context()
  local realm = DB.Realm()
  return Craft.Context(realm, TaxTheFoolsDB.items, Inv.Held(realm), U.day(time()))
end

-- Made the first time a tradeskill window opens: TradeSkillFrame is
-- load-on-demand and does not exist before that.
function TS.CreateStrip()
  if TS.strip then return TS.strip end
  if not TradeSkillFrame then return nil end
  local s = CreateFrame("Frame", "TaxTheFoolsStrip", TradeSkillFrame)
  s:SetWidth(TS.STRIP_W)
  s:SetHeight(22)
  s:SetPoint("TOPLEFT", TradeSkillFrame, "BOTTOMLEFT", TS.STRIP_X, TS.STRIP_Y)
  Th.Panel(s, "header")
  s.text = Th.Text(s, "body", 11, "text")
  s.text:SetPoint("LEFT", s, "LEFT", 8, 0)
  s.text:SetPoint("RIGHT", s, "RIGHT", -8, 0)
  s.sel = false
  TS.strip = s
  return s
end

-- Text and colour token for one evaluation (nil: nothing selected).
-- Plain money, so the whole line takes the good or bad colour.
function TS.StripText(ev)
  if not ev then return "Select a recipe to see its profit.", "dim" end
  if not ev.profit then return "incomplete: " .. table.concat(ev.missing, ", "), "warn" end
  local value = U.money(ev.value, true)
  if ev.valueSource == "vendor" then value = value .. " (vendor)" end
  local text = "Cost " .. U.money(ev.cost, true) .. "   Value " .. value .. "   Profit " .. U.money(ev.profit, true)
  if ev.profit >= 0 then return text, "good" end
  return text, "bad"
end

-- The recipe the window has selected, from this character's captured list.
function TS.Selected()
  local i = GetTradeSkillSelectionIndex()
  if not i or i < 1 then return nil end
  local name, kind = GetTradeSkillInfo(i)
  if not name or kind == "header" then return nil end
  local profs = DB.Char().professions
  local prof = profs and profs[GetTradeSkillLine()]
  return prof and prof.recipes[name]
end

-- Selecting a recipe fires no event, so this runs on a poll as well; it only
-- repaints when the selection moved, unless forced (after a capture).
function TS.RefreshStrip(force)
  local s = TS.strip
  if not s or not s:IsVisible() then return end
  local i = GetTradeSkillSelectionIndex()
  if not force and i == s.sel then return end
  s.sel = i
  local recipe = TS.Selected()
  local ev = recipe and Craft.Evaluate(recipe, TS.Context())
  local text, token = TS.StripText(ev)
  s.text:SetText(text)
  Th.Color(s.text, token)
end

function TS.Poll(now) TS.RefreshStrip(false) end
```

In `TaxTheFools/core.lua`, inside `Core.Update`, replace:
```lua
    Core.Safe("interface", A.UI.Tick, now)
```
with:
```lua
    Core.Safe("interface", A.UI.Tick, now)
    Core.Safe("tradeskill", A.TradeSkill.Poll, now)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `make test`
Expected: `174 passed, 0 failed` (170 + 4 in `test_tradeskill.lua`).

- [ ] **Step 6: Commit**

```bash
git add TaxTheFools/tradeskill.lua TaxTheFools/core.lua tests/wow_stub.lua tests/test_tradeskill.lua
git commit -m "feat: profit strip under the tradeskill window for the selected recipe"
```

---

### Task 5: The Crafting page, its window and the AH Crafting tab

**Files:**
- Modify: `TaxTheFools/widgets.lua:156-200` (`W.Dropdown` gains `SetOptions`)
- Create: `TaxTheFools/ui_craft.lua`
- Modify: `TaxTheFools/ui_window.lua:7-8` (`UI.TABS`)
- Modify: `TaxTheFools/TaxTheFools.toc` (add `ui_craft.lua` after `ui_browse.lua`, line 26)
- Test: `tests/test_widgets.lua`, `tests/test_craft_ui.lua` (new)

**Interfaces:**
- Consumes: `TS.Context()` (Task 4), `Craft.Evaluate` (Task 1), `L.New(parent, columns, rowHeight, onClick)` with `list.data`, `list.selected`, `list.sortCol`, `list.sortDesc`, `list.rows[i].cells[c]`, `list:SetData`, `list:Paint`; `L.Sort` sinks nil values in both directions; `W.Window`, `W.Dropdown`; `UI.builders`, `UI.TABS`, `UI.ShowPage(key)`; `Scan.OnChange(fn)`; `DB.S().craft.staleDays`; `DB.charName`.
- Produces:
  - `dropdown:SetOptions(options)` where `options = { { value, label }, ... }`; `dropdown.options`.
  - `TaxTheFools.CraftUI`: `CraftUI.EMPTY`, `CraftUI.SKILL_COLOR`, `CraftUI.SOURCE`, `CraftUI.COLUMNS`, `CraftUI.Rows(prof, ctx, staleDays) -> rows`, `CraftUI.Characters(realm) -> names`, `CraftUI.Professions(char) -> names`, `CraftUI.DetailLines(row, today, staleDays) -> { { text, token } }`, `CraftUI.Build(parent) -> page` (fields `char`, `prof`, `charDD`, `profDD`, `list`, `detail` with `detail.lines[1..9]`, `empty`), `CraftUI.Paint(page)`, `CraftUI.ShowDetail(page, row)`, `CraftUI.SetChar(page, name)`, `CraftUI.SetProf(page, name)`, `CraftUI.RefreshAll()`, `CraftUI.Window() -> frame` (`TaxTheFoolsCraft`, field `page`), `CraftUI.Toggle()`.
  - `UI.builders.craft = CraftUI.Build`; `UI.TABS` gains `{ key = "craft", label = "Crafting" }`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_widgets.lua`:
```lua

T.test("a dropdown's choices can be replaced", function()
  local v = "b"
  local d = W.Dropdown(UIParent, 120, { { value = "a", label = "Alpha" } }, function() return v end, function(n) v = n end)
  T.eq(d.label:GetText(), "", "nothing matches yet")
  d:SetOptions({ { value = "b", label = "Beta" }, { value = "c", label = "Gamma" } })
  T.eq(d.label:GetText(), "Beta")
  T.eq(d.menu.items[2].text:GetText(), "Gamma")
  T.eq(d.menu:GetHeight(), 48, "8 + 2 x 20")
  d:SetOptions({ { value = "c", label = "Gamma" } })
  T.eq(d.menu.items[2]:IsShown(), false, "the spare item is hidden")
  WoW.runScript(d.menu.items[1], "OnClick")
  T.eq(v, "c") T.eq(d.label:GetText(), "Gamma")
end)
```

`tests/test_craft_ui.lua`:
```lua
local A = TaxTheFools
local CraftUI, DB, UI, AH, Th = A.CraftUI, A.DB, A.UI, A.AH, A.Theme

local function bolt()
  return { item = "4305:0", color = "medium", reagents = { { item = "4306:0", name = "Silk Cloth", count = 4 } } }
end

-- Tailor knows three recipes: one profitable, one at a loss, one with a material nobody has priced.
local function seed()
  local realm = DB.Realm()
  realm.market["4306:0"] = { v = 300, lowDay = 20366 }     -- Silk Cloth, last seen 9 days ago
  realm.market["4305:0"] = { v = 2000, lowDay = 20375 }    -- Bolt of Silk Cloth
  realm.market["9100:0"] = { v = 3000, lowDay = 20375 }    -- Silk Headband
  realm.market["9200:0"] = { v = 5000, lowDay = 20375 }    -- Spider Silk Robe
  A.Items.Remember(4306, "Silk Cloth")
  A.Items.Remember(4305, "Bolt of Silk Cloth")
  A.Items.Remember(2321, "Fine Thread").vb = 100
  realm.chars.Tailor = { bags = { ["4306:0"] = 3 }, professions = { Tailoring = { recipes = {
    ["Bolt of Silk Cloth"] = bolt(),
    ["Silk Headband"] = { item = "9100:0", color = "optimal", reagents = {
      { item = "4305:0", name = "Bolt of Silk Cloth", count = 3 }, { item = "2321:0", name = "Fine Thread", count = 1 } } },
    ["Spider Silk Robe"] = { item = "9200:0", color = "easy", reagents = { { item = "3182:0", name = "Spider's Silk", count = 1 } } },
  } } } }
end

-- The fake client has no layout engine: give the list a height so it draws rows.
local function open()
  local f = CraftUI.Window()
  f:Hide()
  f.page.char, f.page.prof = false, false
  f.page.list:SetHeight(200)
  f:Show()
  return f.page
end

local function names(list)
  local t = {}
  for _, r in ipairs(list.data) do table.insert(t, r.name) end
  return table.concat(t, ", ")
end

T.test("recipes sort by profit, highest first, with incomplete ones last", function()
  seed()
  local p = open()
  T.eq(p.char, "Tailor", "Bankalt has no recipes, so the first character that does")
  T.eq(p.prof, "Tailoring")
  -- Bolt: 2000 x 0.95 - 4 x 300 = 700. Headband: 3000 x 0.95 - (3 x 1200 crafted bolts + 100 thread) = -850.
  T.eq(names(p.list), "Bolt of Silk Cloth, Silk Headband, Spider Silk Robe")
  T.near(p.list.data[1].profit, 700, 0.001)
  T.near(p.list.data[2].profit, -850, 0.001)
  T.eq(p.list.data[3].profit, nil)
  T.eq(p.list.rows[3].cells[4]:GetText(), "incomplete")
end)

T.test("switching character and profession changes the list", function()
  seed()
  DB.Realm().chars.Zed = { professions = {
    Leatherworking = { recipes = { ["Light Armor Kit"] = { item = "2304:0", reagents = { { item = "2318:0", count = 1 } } } } },
    Tailoring = { recipes = { ["Bolt of Silk Cloth"] = bolt() } },
  } }
  local p = open()
  WoW.runScript(p.charDD.menu.items[2], "OnClick")       -- Tailor, Zed
  T.eq(p.char, "Zed")
  T.eq(p.prof, "Leatherworking", "the first of Zed's professions")
  T.eq(names(p.list), "Light Armor Kit")
  WoW.runScript(p.profDD.menu.items[2], "OnClick")       -- Leatherworking, Tailoring
  T.eq(p.prof, "Tailoring")
  T.eq(names(p.list), "Bolt of Silk Cloth")
  DB.Realm().chars.Bankalt = { professions = { Tailoring = { recipes = { ["Bolt of Silk Cloth"] = bolt() } } } }
  p = open()
  T.eq(p.char, "Bankalt", "this character, once it has recipes")
end)

T.test("with nothing captured the page says how to load recipes", function()
  local p = open()
  T.ok(p.empty:IsShown())
  T.eq(p.empty:GetText(), "Open your Tailoring window once on this character to load its recipes.")
  T.eq(p.list:IsShown(), false)
end)

T.test("the detail pane lists each material, dimming prices older than the setting", function()
  seed()
  local p = open()
  WoW.runScript(p.list.rows[1], "OnClick", "LeftButton")    -- Bolt of Silk Cloth
  local d = p.detail.lines
  -- profit 700; cash 1900 - (4 - 3 held) x 300 = 1600
  T.eq(d[1]:GetText(), "Bolt of Silk Cloth: profit 7s, cash 16s (deposit unknown)")
  T.eq(d[2]:GetText(), "4 x Silk Cloth   have 3   3s each   AH   9d ago")
  T.eq(d[2].color[1], Th.color.dim[1], "20375 - 20366 = 9 days > 7")
  DB.S().craft.staleDays = 10
  CraftUI.ShowDetail(p, p.list.selected)
  T.eq(d[2].color[1], Th.color.text[1], "9 days is within 10")
end)

T.test("materials show which source won: crafted, vendor, or nothing", function()
  seed()
  local p = open()
  WoW.runScript(p.list.rows[2], "OnClick", "LeftButton")    -- Silk Headband
  local d = p.detail.lines
  T.eq(d[2]:GetText(), "3 x Bolt of Silk Cloth   have 0   12s each   craft   9d ago", "4 x 300 = 1200 < 2000")
  T.eq(d[3]:GetText(), "1 x Fine Thread   have 0   1s each   vendor")
  WoW.runScript(p.list.rows[3], "OnClick", "LeftButton")    -- Spider Silk Robe
  T.eq(d[1]:GetText(), "Spider Silk Robe: incomplete: Spider's Silk")
  T.eq(d[2]:GetText(), "1 x Spider's Silk   have 0   -   no price")
  T.eq(d[3]:GetText(), "", "unused lines are cleared")
end)

T.test("the auction window's Crafting tab shows the same page", function()
  seed()
  UI.CreateAH()
  AH.switching = true UI.ah:Hide() AH.switching = false
  AH.open = true
  AH.ShowOurs()
  if UI.pages.craft then UI.pages.craft.char, UI.pages.craft.prof = false, false end
  UI.ah.tabs:Select("craft")
  T.ok(UI.pages.craft:IsShown())
  T.eq(UI.pages.browse:IsShown(), false)
  T.eq(names(UI.pages.craft.list), "Bolt of Silk Cloth, Silk Headband, Spider Silk Robe")
  UI.ah.tabs:Select("browse")
end)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `make test`
Expected: `174 passed, 7 failed`: the dropdown test (its label stays empty: on the fake client a missing `SetOptions` method reads as a no-op function) and all six `test_craft_ui.lua` tests (`TaxTheFools.CraftUI` is nil; the AH has no Crafting builder).

- [ ] **Step 3: Let a dropdown's choices change**

In `TaxTheFools/widgets.lua`, inside `W.Dropdown`, replace everything from `  menu:SetWidth(width)` to the end of the function:
```lua
  menu:SetWidth(width)
  menu:SetHeight(8 + table.getn(options) * 20)
  Th.Panel(menu, "header")
  menu.items = {}
  for i, o in ipairs(options) do
    menu.items[i] = W.MenuItem(menu, i, o, function(value)
      set(value)
      menu:Hide()
      b:Refresh()
    end)
  end
  menu:Hide()
  b.menu = menu
  b:SetScript("OnHide", function() menu:Hide() end)
  b.Refresh = function(self)
    local v = get()
    for _, o in ipairs(options) do
      if o.value == v then self:SetLabel(o.label) end
    end
  end
  b:Refresh()
  return b
end
```
with:
```lua
  menu:SetWidth(width)
  Th.Panel(menu, "header")
  menu.items = {}
  menu:Hide()
  b.menu = menu
  local function choose(value)
    set(value)
    menu:Hide()
    b:Refresh()
  end
  b:SetScript("OnHide", function() menu:Hide() end)
  -- Replaces the choices; menu items are reused, spare ones hidden.
  b.SetOptions = function(self, opts)
    self.options = opts
    for i, o in ipairs(opts) do
      local item = menu.items[i]
      if item then
        item.text:SetText(o.label)
        item.value = o.value
      else
        item = W.MenuItem(menu, i, o, choose)
        menu.items[i] = item
      end
      item:Show()
    end
    for i = table.getn(opts) + 1, table.getn(menu.items) do menu.items[i]:Hide() end
    menu:SetHeight(8 + table.getn(opts) * 20)
    self:Refresh()
  end
  b.Refresh = function(self)
    local v = get()
    self:SetLabel("")
    for _, o in ipairs(self.options) do
      if o.value == v then self:SetLabel(o.label) end
    end
  end
  b:SetOptions(options)
  return b
end
```

(`choose` is a named local, so no closure is made inside the loop.)

- [ ] **Step 4: Build the Crafting page**

`TaxTheFools/ui_craft.lua`:
```lua
TaxTheFools = TaxTheFools or {}
local U, Th, W, L, DB, Craft, TS, UI, Scan = TaxTheFools.Util, TaxTheFools.Theme, TaxTheFools.Widgets,
  TaxTheFools.List, TaxTheFools.DB, TaxTheFools.Craft, TaxTheFools.TradeSkill, TaxTheFools.UI, TaxTheFools.Scan
local CraftUI = { pages = {}, window = nil }
TaxTheFools.CraftUI = CraftUI

CraftUI.EMPTY = "Open your Tailoring window once on this character to load its recipes."
-- The client's own recipe colours (TradeSkillTypeColor).
CraftUI.SKILL_COLOR = { optimal = "|cffff8040", medium = "|cffffff00", easy = "|cff40bf40", trivial = "|cff808080" }
CraftUI.SOURCE = { ah = "AH", vendor = "vendor", craft = "craft" }
CraftUI.DETAIL_LINES = 9      -- a heading and up to eight materials, the most a 1.12 recipe has
CraftUI.DETAIL_H = 10 + 9 * 14

local function money(v)
  if v then return U.money(v) end
  return "-"
end

local function signed(v)
  if not v then return "-", "dim" end
  if v >= 0 then return U.money(v, true), "good" end
  return U.money(v, true), "bad"
end

CraftUI.COLUMNS = {
  { label = "Recipe", width = 220, sort = "name",
    fmt = function(r) return (CraftUI.SKILL_COLOR[r.color] or "|cffffffff") .. r.name .. "|r" end },
  { label = "Cost", width = 90, align = "RIGHT", sort = "cost", fmt = function(r) return money(r.cost) end },
  { label = "Value", width = 100, align = "RIGHT", sort = "value",
    fmt = function(r) return money(r.value) .. (r.vendorValue and " (v)" or "") end },
  { label = "Profit", width = 90, align = "RIGHT", sort = "profit", desc = true, fmt = function(r)
    if not r.profit then return "incomplete", "warn" end
    return signed(r.profit)
  end },
  { label = "Cash", width = 90, align = "RIGHT", sort = "cash", desc = true, fmt = function(r) return signed(r.cash) end },
  { label = "Age", width = 60, align = "RIGHT", sort = "age",
    fmt = function(r) return r.age and U.daysAgo(r.age) or "-", r.stale and "dim" or "text" end },
}

-- One row per recipe. A recipe with any price missing has profit nil, and
-- the list sorts nil last whichever way a column is sorted.
function CraftUI.Rows(prof, ctx, staleDays)
  local rows = {}
  for name, recipe in pairs(prof.recipes or {}) do
    local ev = Craft.Evaluate(recipe, ctx)
    local age = ev.oldest and (ctx.today - ev.oldest) or nil
    table.insert(rows, { name = name, color = recipe.color, recipe = recipe, ev = ev,
      cost = ev.cost, value = ev.value, profit = ev.profit, cash = ev.cash,
      vendorValue = (ev.valueSource == "vendor"), age = age, stale = (age ~= nil and age > staleDays) })
  end
  return rows
end

-- Characters on this realm with at least one captured profession, sorted.
function CraftUI.Characters(realm)
  local names = {}
  for name, c in pairs(realm.chars or {}) do
    if c.professions and next(c.professions) then table.insert(names, name) end
  end
  table.sort(names)
  return names
end

function CraftUI.Professions(c)
  local names = {}
  for name in pairs((c and c.professions) or {}) do table.insert(names, name) end
  table.sort(names)
  return names
end

local function options(names)
  local t = {}
  for _, n in ipairs(names) do table.insert(t, { value = n, label = n }) end
  return t
end

local function contains(list, v)
  for _, x in ipairs(list) do
    if x == v then return true end
  end
  return false
end

-- The detail pane's lines for one row, as { text, token } pairs.
function CraftUI.DetailLines(row, today, staleDays)
  if not row then return { { "Select a recipe to see its materials.", "dim" } } end
  local ev = row.ev
  local out = {}
  if ev.profit then
    local head = row.name .. ": profit " .. U.money(ev.profit, true) .. ", cash " .. U.money(ev.cash, true)
    if ev.valueSource == "vendor" then head = head .. " (valued at the vendor price)" end
    if ev.depositUnknown then head = head .. " (deposit unknown)" end
    local _, token = signed(ev.profit)
    table.insert(out, { head, token })
  else
    table.insert(out, { row.name .. ": incomplete: " .. table.concat(ev.missing, ", "), "warn" })
  end
  for _, l in ipairs(ev.lines) do
    local age = l.day and (today - l.day) or nil
    local src = (l.source and CraftUI.SOURCE[l.source]) or "no price"
    if l.limited then src = src .. ", limited stock" end
    local unit = l.unit and (U.money(l.unit, true) .. " each") or "-"
    local text = l.need .. " x " .. l.name .. "   have " .. l.have .. "   " .. unit .. "   " .. src
    if age then text = text .. "   " .. U.daysAgo(age) end
    table.insert(out, { text, (age and age > staleDays) and "dim" or "text" })
  end
  return out
end

function CraftUI.Detail(p)
  local d = CreateFrame("Frame", nil, p)
  d:SetHeight(CraftUI.DETAIL_H)
  d:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 0)
  d:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
  local bg = Th.Solid(d, "BACKGROUND", "panel3")
  bg:SetAllPoints(d)
  d.lines = {}
  for i = 1, CraftUI.DETAIL_LINES do
    local fs = Th.Text(d, "body", 11, "text")
    fs:SetPoint("TOPLEFT", d, "TOPLEFT", 8, -6 - (i - 1) * 14)
    fs:SetPoint("RIGHT", d, "RIGHT", -8, 0)
    d.lines[i] = fs
  end
  return d
end

function CraftUI.ShowDetail(p, row)
  local lines = CraftUI.DetailLines(row, U.day(time()), DB.S().craft.staleDays)
  for i, fs in ipairs(p.detail.lines) do
    local l = lines[i]
    if l then
      fs:SetText(l[1])
      Th.Color(fs, l[2])
    else
      fs:SetText("")
    end
  end
end

function CraftUI.SetChar(p, name)
  p.char, p.prof = name, false
  CraftUI.Paint(p)
end

function CraftUI.SetProf(p, name)
  p.prof = name
  CraftUI.Paint(p)
end

-- One builder for both places the page appears: the Crafting window and the AH tab.
function CraftUI.Build(parent)
  local p = CreateFrame("Frame", nil, parent)
  p.char, p.prof = false, false
  p.charDD = W.Dropdown(p, 150, {}, function() return p.char end, function(v) CraftUI.SetChar(p, v) end)
  p.charDD:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
  p.profDD = W.Dropdown(p, 150, {}, function() return p.prof end, function(v) CraftUI.SetProf(p, v) end)
  p.profDD:SetPoint("LEFT", p.charDD, "RIGHT", 6, 0)
  p.list = L.New(p, CraftUI.COLUMNS, 18, function(item) CraftUI.ShowDetail(p, item) end)
  p.list:SetPoint("TOPLEFT", p.charDD, "BOTTOMLEFT", 0, -8)
  p.list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, CraftUI.DETAIL_H + 6)
  p.list.sortCol, p.list.sortDesc = CraftUI.COLUMNS[4], true     -- Profit, highest first
  p.detail = CraftUI.Detail(p)
  p.empty = Th.Text(p, "body", 13, "dim")
  p.empty:SetPoint("CENTER", p, "CENTER", 0, 0)
  p.empty:SetText(CraftUI.EMPTY)
  p.empty:Hide()
  p.Refresh = function(self) CraftUI.Paint(self) end
  p.Layout = function(self) self.list:Paint() end
  table.insert(CraftUI.pages, p)
  return p
end

-- Starts on this character when it has recipes, else the first that does.
function CraftUI.Paint(p)
  local realm = DB.Realm()
  local names = CraftUI.Characters(realm)
  if not p.char or not contains(names, p.char) then
    if contains(names, DB.charName) then p.char = DB.charName else p.char = names[1] or false end
  end
  p.charDD:SetOptions(options(names))
  local c = p.char and realm.chars[p.char]
  local profs = CraftUI.Professions(c)
  if not p.prof or not contains(profs, p.prof) then p.prof = profs[1] or false end
  p.profDD:SetOptions(options(profs))
  local prof = p.prof and c.professions[p.prof]
  if not prof then
    p.empty:Show()
    p.list:Hide()
    p.detail:Hide()
    return
  end
  p.empty:Hide()
  p.list:Show()
  p.detail:Show()
  local keep = p.list.selected and p.list.selected.name
  p.list:SetData(CraftUI.Rows(prof, TS.Context(), DB.S().craft.staleDays))
  for _, r in ipairs(p.list.data) do
    if r.name == keep then p.list.selected = r end
  end
  p.list:Paint()
  CraftUI.ShowDetail(p, p.list.selected or nil)
end

function CraftUI.RefreshAll()
  for _, p in ipairs(CraftUI.pages) do
    if p:IsVisible() then CraftUI.Paint(p) end
  end
end

function CraftUI.Window()
  if CraftUI.window then return CraftUI.window end
  local f = W.Window("TaxTheFoolsCraft", 720, 480, "Tax the Fools  -  Crafting",
    { resizable = true, minW = 700, minH = 360 })
  f.body = CreateFrame("Frame", nil, f)
  f.body:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 10, -10)
  f.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 22)
  f.page = CraftUI.Build(f.body)
  f.page:SetAllPoints(f.body)
  f:SetScript("OnShow", function() CraftUI.Paint(f.page) end)
  f.onResize = function() f.page:Layout() end
  CraftUI.window = f
  return f
end

function CraftUI.Toggle()
  local f = CraftUI.Window()
  if f:IsShown() then f:Hide() else f:Show() end
end

UI.builders.craft = CraftUI.Build
-- New market values change every profit on the page.
Scan.OnChange(function() CraftUI.RefreshAll() end)
```

In `TaxTheFools/ui_window.lua`, replace:
```lua
-- Later phases add Deals, Sell, Auctions, Crafting and History here.
UI.TABS = { { key = "browse", label = "Browse" } }
```
with:
```lua
-- Later phases add Deals, Sell, Auctions and History here.
UI.TABS = { { key = "browse", label = "Browse" }, { key = "craft", label = "Crafting" } }
```

In `TaxTheFools/TaxTheFools.toc`, add the line `ui_craft.lua` directly after `ui_browse.lua` (line 26, before `options.lua`).

- [ ] **Step 5: Run tests to verify they pass**

Run: `make test`
Expected: `181 passed, 0 failed` (174 + 1 in `test_widgets.lua` + 6 in `test_craft_ui.lua`).

- [ ] **Step 6: Commit**

```bash
git add TaxTheFools/widgets.lua TaxTheFools/ui_craft.lua TaxTheFools/ui_window.lua TaxTheFools/TaxTheFools.toc tests/test_widgets.lua tests/test_craft_ui.lua
git commit -m "feat: Crafting page with cost, value, profit and cash per recipe, as a window and an AH tab"
```

---

### Task 6: Icons, Crafting options, `/ttf craft` and the automation guard

**Files:**
- Modify: `TaxTheFools/theme.lua:8-9` (`Th.TEXTURES`)
- Modify: `TaxTheFools/widgets.lua:374-376` (`W.Window` header, `opts.logo`)
- Modify: `TaxTheFools/ui_window.lua:97`, `TaxTheFools/ui_craft.lua` (`logo = true`)
- Modify: `TaxTheFools/minimap.lua:27-29`, `:35`, `:60-63`
- Modify: `TaxTheFools/options.lua:7`, `:14`, `:29-30`
- Modify: `TaxTheFools/core.lua` (`Core.HELP`, `Core.Command`)
- Test: `tests/test_options.lua`, `tests/test_craft_ui.lua`, `tests/test_core.lua`

**Interfaces:**
- Consumes: `CraftUI.Toggle()`, `CraftUI.Window()`, `CraftUI.RefreshAll()` (Task 5), `Opt.Get/Set` row paths, `W.Slider` (saves on `OnMouseUp`), `W.Switch`.
- Produces:
  - `W.Window(name, w, h, title, { logo = true })` → `frame.header.logo` (texture, or `false` without the option); the title anchors to the logo's right.
  - `Mini.button.icon` (texture `Th.MEDIA .. "minimap"`); `Mini.Click("RightButton")` opens options, any other button toggles the Crafting window.
  - Options category `crafting` with rows `{ "craft", "autoWatch" }` (switch) and `{ "craft", "staleDays" }` (slider 1..30, step 1, label `"N days"`).
  - `/ttf craft` toggles the Crafting window.

- [ ] **Step 1: Write the failing tests**

In `tests/test_options.lua`, replace the test:
```lua
T.test("clicking the minimap button opens options", function()
  Mini.Create()
  Opt.Create():Hide()
  WoW.runScript(Mini.button, "OnClick", "LeftButton")
  T.ok(Opt.frame:IsShown())
end)
```
with:
```lua
T.test("right-clicking the minimap button opens options", function()
  Mini.Create()
  Opt.Create():Hide()
  WoW.runScript(Mini.button, "OnClick", "RightButton")
  T.ok(Opt.frame:IsShown())
end)

T.test("left-clicking the minimap button opens the Crafting window", function()
  Mini.Create()
  local f = TaxTheFools.CraftUI.Window()
  f:Hide()
  WoW.runScript(Mini.button, "OnClick", "LeftButton")
  T.ok(f:IsShown())
  WoW.runScript(Mini.button, "OnClick", "LeftButton")
  T.eq(f:IsShown(), false, "and closes it again")
end)

T.test("the minimap button shows the goblin coin and says what each click does", function()
  Mini.Create()
  T.eq(Mini.button.icon:GetTexture(), TaxTheFools.Theme.MEDIA .. "minimap")
  T.ok(string.find(Mini.button.tip.body, "Left-click: crafting profit", 1, true), Mini.button.tip.body)
end)

T.test("the Crafting options switch auto-watch and set the stale-price days", function()
  local f = Opt.Create()
  Opt.Select("crafting")
  local c = f.pages.crafting.controls
  WoW.runScript(c[1], "OnClick")
  T.eq(DB.S().craft.autoWatch, false)
  c[2].slider:SetValue(12)
  T.eq(c[2].value:GetText(), "12 days")
  WoW.runScript(c[2].slider, "OnMouseUp")
  T.eq(DB.S().craft.staleDays, 12)
end)
```

Append to `tests/test_craft_ui.lua`:
```lua
T.test("the auction and Crafting windows show the logo before the title", function()
  UI.CreateAH()
  local logo = Th.MEDIA .. "logo"
  T.eq(UI.ah.header.logo:GetTexture(), logo)
  T.eq(UI.ah.header.logo:GetWidth(), 24)
  T.eq(UI.ah.header.title.points[1][2], UI.ah.header.logo, "the title starts after the logo")
  T.eq(CraftUI.Window().header.logo:GetTexture(), logo)
end)
```

In `tests/test_core.lua`:

In the test `"/ttf with no arguments lists the commands"`, after the line
```lua
  T.ok(T.calledWith("/ttf options")) T.ok(T.calledWith("/ttf watch")) T.ok(T.calledWith("/ttf probe"))
```
add:
```lua
  T.ok(T.calledWith("/ttf craft"))
```

Insert directly before `T.test("debug toggles", ...)`:
```lua
T.test("/ttf craft opens and closes the Crafting window", function()
  local f = A.CraftUI.Window()
  f:Hide()
  ttf("craft")
  T.ok(f:IsShown())
  ttf("craft")
  T.eq(f:IsShown(), false)
end)
```

Extend the automation test `"nothing is bought, bid on, posted or cancelled without a click"`: replace its ending
```lua
  T.ok(T.calledWith("QueryAuctionItems"), "it did scan")
  T.ok(not T.calledWith("PlaceAuctionBid"), "no bid or buyout")
  T.ok(not T.calledWith("StartAuction"), "no post")
  T.ok(not T.calledWith("CancelAuction"), "no cancel")
end)
```
with:
```lua
  T.ok(T.calledWith("QueryAuctionItems"), "it did scan")
  -- A merchant selling thread and a tradeskill window full of craftable recipes.
  WoW.bags[0] = { { id = 4306, name = "Silk Cloth", count = 40, vendor = 37 } }
  WoW.merchant = { { id = 2321, name = "Fine Thread", price = 100, quantity = 1, numAvailable = -1 } }
  WoW.merchantOpen = true
  WoW.fire("MERCHANT_SHOW")
  WoW.tradeskill = { name = "Tailoring", rank = 225, maxRank = 300, selected = 2, rows = {
    { header = true, name = "Cloth" },
    { name = "Bolt of Silk Cloth", type = "optimal", id = 4305, available = 10,
      reagents = { { id = 4306, name = "Silk Cloth", count = 4, have = 40 } } } } }
  WoW.openTradeSkill()
  WoW.fire("TRADE_SKILL_UPDATE")
  for _ = 1, 10 do
    WoW.clock = WoW.clock + 0.25
    WoW.runScript(TaxTheFoolsCore, "OnUpdate")
  end
  A.CraftUI.Toggle()
  T.ok(A.Items.Get(2321).vb, "the merchant was read")
  T.ok(DB.Char().professions.Tailoring.recipes["Bolt of Silk Cloth"], "the recipes were read")
  T.ok(not T.calledWith("PlaceAuctionBid"), "no bid or buyout")
  T.ok(not T.calledWith("StartAuction"), "no post")
  T.ok(not T.calledWith("CancelAuction"), "no cancel")
  T.ok(not T.calledWith("DoTradeSkill"), "nothing crafted")
  T.ok(not T.calledWith("BuyMerchantItem"), "nothing bought from the merchant")
  T.ok(not T.calledWith("UseContainerItem"), "nothing sold to the merchant")
  A.CraftUI.Toggle()
end)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `make test`
Expected: `180 passed, 6 failed`: left-click opens Crafting, the goblin coin icon, the Crafting options page, the logo, `/ttf craft`, and the help list (it does not name `/ttf craft` yet). The renamed right-click test and the extended automation test already pass: right-click still opens options, and nothing in Tasks 1–5 crafts, buys or sells. The automation test now guards that from here on.

- [ ] **Step 3: Logo in window headers**

In `TaxTheFools/theme.lua`, replace:
```lua
  "icon-close", "icon-check", "icon-caret-down", "icon-caret-up", "icon-arrow-left", "icon-arrow-right", "icon-grip" }
```
with:
```lua
  "icon-close", "icon-check", "icon-caret-down", "icon-caret-up", "icon-arrow-left", "icon-arrow-right", "icon-grip",
  "logo", "minimap" }
```
(Both files already exist in `TaxTheFools/media/`. Listing them here makes the existing theme test check they ship.)

In `TaxTheFools/widgets.lua`, inside `W.Window`, replace:
```lua
  h.title = Th.Text(h, "display", 14, "white")
  h.title:SetPoint("LEFT", h, "LEFT", 12, 0)
  h.title:SetText(string.upper(title))
```
with:
```lua
  h.title = Th.Text(h, "display", 14, "white")
  h.title:SetText(string.upper(title))
  -- The logo is full colour artwork, so it is never tinted.
  if opts and opts.logo then
    h.logo = h:CreateTexture(nil, "ARTWORK")
    h.logo:SetTexture(Th.MEDIA .. "logo")
    h.logo:SetWidth(24)
    h.logo:SetHeight(24)
    h.logo:SetPoint("LEFT", h, "LEFT", 8, 0)
    h.title:SetPoint("LEFT", h.logo, "RIGHT", 6, 0)
  else
    h.logo = false
    h.title:SetPoint("LEFT", h, "LEFT", 12, 0)
  end
```

In `TaxTheFools/ui_window.lua`, replace:
```lua
  local f = W.Window("TaxTheFoolsAH", 780, 500, "Tax the Fools", { resizable = true, minW = 660, minH = 380 })
```
with:
```lua
  local f = W.Window("TaxTheFoolsAH", 780, 500, "Tax the Fools", { resizable = true, minW = 660, minH = 380, logo = true })
```

In `TaxTheFools/ui_craft.lua`, inside `CraftUI.Window`, replace:
```lua
    { resizable = true, minW = 700, minH = 360 })
```
with:
```lua
    { resizable = true, minW = 700, minH = 360, logo = true })
```

- [ ] **Step 4: The minimap goblin coin and its clicks**

In `TaxTheFools/minimap.lua`, replace:
```lua
  b.text = Th.Text(b, "display", 14, "accent")
  b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.text:SetText("TF")
```
with:
```lua
  -- The goblin coin is full colour artwork, so it is never tinted.
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetTexture(Th.MEDIA .. "minimap")
  b.icon:SetWidth(24)
  b.icon:SetHeight(24)
  b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
```

Replace:
```lua
  W.Tip(b, "Tax the Fools", "Click: options. Drag: move this button.")
```
with:
```lua
  W.Tip(b, "Tax the Fools", "Left-click: crafting profit. Right-click: options. Drag: move this button.")
```

Replace:
```lua
-- Phase 2 gives left-click the Crafting window.
function Mini.Click(button)
  TaxTheFools.Options.Toggle()
end
```
with:
```lua
function Mini.Click(button)
  if button == "RightButton" then TaxTheFools.Options.Toggle() else TaxTheFools.CraftUI.Toggle() end
end
```

- [ ] **Step 5: The Crafting options category**

In `TaxTheFools/options.lua`, replace:
```lua
local function secs(v) return string.format("%.1fs", v) end
```
with:
```lua
local function secs(v) return string.format("%.1fs", v) end
local function days(v)
  if v == 1 then return "1 day" end
  return v .. " days"
end
```

Replace:
```lua
-- Phase 3 adds Deals and Selling pages; phase 2 adds Crafting.
```
with:
```lua
-- Phase 3 adds Deals and Selling pages.
```

Replace:
```lua
    { kind = "switch", key = "browseFeedsHistory", label = "Searches add to price history" },
  } },
```
with:
```lua
    { kind = "switch", key = "browseFeedsHistory", label = "Searches add to price history" },
  } },
  { key = "crafting", label = "Crafting", rows = {
    { kind = "switch", path = { "craft", "autoWatch" }, label = "Watch recipe materials automatically",
      hint = "Each time a tradeskill window opens, its products and materials join the Watchlist scan." },
    { kind = "slider", path = { "craft", "staleDays" }, label = "Dim prices older than", min = 1, max = 30, step = 1,
      fmt = days, after = function() TaxTheFools.CraftUI.RefreshAll() end },
  } },
```

- [ ] **Step 6: `/ttf craft`**

In `TaxTheFools/core.lua`, in `Core.HELP`, replace:
```lua
  "/ttf options - settings",
```
with:
```lua
  "/ttf options - settings",
  "/ttf craft - crafting profit for every recipe you have captured",
```

In `Core.Command`, replace:
```lua
  if cmd == "options" or cmd == "config" then A.Options.Toggle()
```
with:
```lua
  if cmd == "options" or cmd == "config" then A.Options.Toggle()
  elseif cmd == "craft" then A.CraftUI.Toggle()
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `make test`
Expected: `186 passed, 0 failed` (181 + 3 new in `test_options.lua` (one test renamed, not added) + 1 in `test_craft_ui.lua` + 1 in `test_core.lua`).

- [ ] **Step 8: Commit**

```bash
git add TaxTheFools/theme.lua TaxTheFools/widgets.lua TaxTheFools/ui_window.lua TaxTheFools/ui_craft.lua TaxTheFools/minimap.lua TaxTheFools/options.lua TaxTheFools/core.lua tests/test_options.lua tests/test_craft_ui.lua tests/test_core.lua
git commit -m "feat: goblin coin minimap button, window logo, Crafting options and /ttf craft"
```

---

### Task 7: In-game checklist, README and version 0.2.0

**Files:**
- Modify: `TaxTheFools/TaxTheFools.toc:5`, `TaxTheFools/data.lua:5`
- Modify: `docs/testing-checklist.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: everything above; the checklist exercises it on the real client.
- Produces: `D.VERSION = "0.2.0"`, `## Version: 0.2.0`.

- [ ] **Step 1: Bump the version**

In `TaxTheFools/TaxTheFools.toc` replace `## Version: 0.1.0` with `## Version: 0.2.0`. In `TaxTheFools/data.lua` replace `D.VERSION = "0.1.0"` with `D.VERSION = "0.2.0"`. (The upgrade test reads `D.VERSION`, so no test changes.)

- [ ] **Step 2: Extend the in-game checklist**

In `docs/testing-checklist.md`, replace:
```
1. Log in on the bank character. Chat shows `TTF: v0.1.0 loaded`.
```
with:
```
1. Log in on the bank character. Chat shows `TTF: v0.2.0 loaded`.
```

Replace:
```
18. Minimap **TF** button opens options. Drag it round the minimap; `/reload`; it stays.
```
with:
```
18. The minimap button shows the goblin coin. Right-click opens options. Drag it round the minimap; `/reload`; it stays.
```

Append to the end of the file:
```
## Crafting (phase 2)
25. The auction window and the Crafting window (`/ttf craft`) show the goblin logo
    before the title, 24px, not stretched or tinted.
26. On the tailor, open Tailoring. A dark strip appears just under the window's
    visible bottom edge, inside its width (not floating below empty space, not over
    the Create buttons). If it is off, note by how many pixels and adjust
    `TS.STRIP_X`, `TS.STRIP_Y` and `TS.STRIP_W` in `tradeskill.lua`.
27. Click Bolt of Silk Cloth. Within a quarter second the strip reads
    `Cost ...   Value ...   Profit ...`, green for a profit, red for a loss. Click a
    recipe whose materials were never scanned: `incomplete: <names>` in amber. Click
    a header: `Select a recipe to see its profit.`
28. Collapse a header (the minus beside it), close the window, `/ttf craft`: the
    recipes under that header are still listed.
29. `/ttf watchlist` lists the bolts, cloth and thread from the recipes (auto-watch).
    Options > Crafting, switch "Watch recipe materials automatically" off, unwatch one
    with `/ttf unwatch`, open Tailoring again: it stays unwatched.
30. Visit a trade goods vendor that sells Fine Thread. `/ttf craft`, select a recipe
    using it: the thread line says `vendor` with the vendor's price per thread, unless
    the AH is cheaper. A limited-stock item (some dyes) says `vendor, limited stock`.
31. Open the bank, deposit some Silk Cloth, close it. In `/ttf craft`, a recipe using
    Silk Cloth shows `have` counting bags and bank together.
32. Log over to the bank alt (no Tailoring). Left-click the minimap coin: the
    Crafting window opens on the tailor's recipes, priced from the bank alt's scans,
    and `have` includes what both characters hold.
33. In the AH, the **Crafting** tab shows the same page. Sort by Profit both ways:
    incomplete recipes stay at the bottom.
34. Options > Crafting, "Dim prices older than" 1 day: material lines priced from
    scans older than a day turn grey in the detail pane.
35. At no point above was anything crafted, bought or sold without your click.
```

- [ ] **Step 3: Update the README**

In `README.md`, replace:
```
Phase 1, this release: the auction window, scanning, price history and tooltips.
Crafting profit, deals with one-click buying, selling, and sales tracking follow
(see `docs/superpowers/specs/2026-10-14-tax-the-fools-design.md`).
```
with:
```
This release (0.2.0): the auction window, scanning, price history, tooltips, and
crafting profit for every recipe your characters know. Deals with one-click buying,
selling, and sales tracking follow (see `docs/superpowers/specs/2026-10-14-tax-the-fools-design.md`).
```

In the **Use** list, insert before the bullet that starts `- **Blizzard UI** switches to the stock window`:
```
- **Crafting profit.** Open your Tailoring window (or any tradeskill) once on each
  crafter; the addon remembers its recipes. A strip under the tradeskill window shows
  the selected recipe's cost, value and profit. `/ttf craft`, the minimap coin, or the
  AH **Crafting** tab lists every recipe with cost, value, profit and cash profit (which
  treats materials any of your characters already hold as free), on any character.
  Materials are priced at the cheaper of the AH and the vendor, or crafted when that
  is cheaper still. A recipe with a missing price says "incomplete" and names it; it
  never guesses.
- **Vendor and bank.** Visiting a vendor teaches the addon its buy prices (thread,
  dye); opening your bank records what is in it, so "have" counts bags and bank.
```

Replace:
```
Nothing is ever bought, bid on, posted or cancelled without your click. The only
thing that runs by itself is a scan turning pages.
```
with:
```
Nothing is ever bought, bid on, posted, cancelled, crafted or sold without your
click. The only thing that runs by itself is a scan turning pages.
```

In **Commands**, after the line `    /ttf options              settings` add:
```
    /ttf craft                crafting profit window
```

- [ ] **Step 4: Run the full suite one last time**

Run: `make test`
Expected: `186 passed, 0 failed`, no lint output.

- [ ] **Step 5: Commit**

```bash
git add TaxTheFools/TaxTheFools.toc TaxTheFools/data.lua docs/testing-checklist.md README.md
git commit -m "docs: phase 2 in-game checklist, README crafting section, version 0.2.0"
```

---

## Self-review

- **Spec coverage:** §2 decisions: vendor/AH min (Task 1 `BuyPrice`, Task 2 `vb`), craftable materials with `AH`/`vendor`/`craft` shown (Tasks 1, 5), held materials free only in cash profit (Tasks 1, 2), vendor-valued product (Task 1), learned recipes only (Task 3), icons (Task 6). §4 data: `vb`/`vbLimited` (Task 2), `professions`/`recipes` (Task 3), `bags`/`bank` and timestamps (Task 2), `settings.craft` (Task 3). Recipes replaced on capture, headers skipped, uncached reagent by name (Task 3). §5 costing, limits, memo, `Evaluate` fields (Task 1). §6 capture with 0.5 s throttle and auto-watch (Task 3), bags with 1 s throttle and at login, bank while open, `Inventory.Held` (Task 2), merchant `vb` (Task 2). §7 strip, lazy, 22 px, 0.25 s poll (Task 4); Crafting page, window, AH tab, columns, default sort, incomplete last, detail pane, stale dimming, empty state (Task 5); minimap, logo, options, `/ttf craft` (Task 6). §8 tests: every listed `craft.lua` case (Task 1; the two-character cash case in Task 2), capture tests (Task 3), inventory tests (Task 2), UI tests (Tasks 4–6), automation guard (Task 6), checklist (Task 7). §3: ClassicAPI sell price used via `Items.Vendor` at capture; `CalculateAuctionDeposit` and duration labels are phases 3–4.
- **Placeholders:** none; every code step has its full code.
- **Names:** `Craft.Context`/`Evaluate`/`UnitCost`, `Inv.Held`, `TS.Context`/`StripText`/`RefreshStrip`/`Poll`, `CraftUI.Build`/`Paint`/`Window`/`Toggle`/`RefreshAll`, `dropdown:SetOptions` are used with the same signatures everywhere.
- **Test counts:** 136 → 151 → 161 → 170 → 174 → 181 → 186 → 186, each step counted from the `T.test` calls it adds. Every task was run against a copy of the repository before this plan was written, with exactly these counts.
