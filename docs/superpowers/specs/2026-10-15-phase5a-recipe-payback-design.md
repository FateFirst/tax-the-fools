# Tax The Fools: Phase 5a, recipe database and payback

Date: 2026-10-15
Status: approved in conversation, written for review
Parent spec: `docs/superpowers/specs/2026-10-14-tax-the-fools-design.md` (§2 phase 5). This phase builds on phase 2's recipe capture and costing (`tradeskill.lua`, `craft.lua`, `ui_craft.lua`), phase 3a's Deals Find → Buy, and phase 4's sales stats. Where this document and the parent disagree, this one wins. The mailbox tab (send to alt) is phase 5b and is not covered here.

## 1. Decisions

| Topic | Decision |
|---|---|
| Recipe source | Both. A built-in list of every Tailoring recipe, generated from LibCrafts-1.0 (MIT), including its Turtle-only block. It is corrected and extended in game by recipes you have learned (the tradeskill capture), trainer windows, vendor windows and pattern tooltips. |
| What "not learned" means | Per character and profession: a built-in or seen recipe whose name, or product item, is not among that character's captured recipes. |
| Cost to get a recipe | The cheapest known of: the trainer cost (learned at the trainer), the pattern's vendor price (learned at the vendor), and the pattern's AH price (the cheapest snapshot listing, else its market value). Drop or quest patterns with no AH price have no cost. |
| Payback | `ceil(cost / profit per craft)` crafts, where profit per craft is `Craft.Evaluate(recipe, ctx).profit` (phase 2: market value after cut and deposit, minus material cost). No profit, or a loss, means "never". No cost means unknown. |
| Yield | 1 for built-in recipes (the data has no yield, and Tailoring recipes make one). A learned recipe's captured yield wins. |
| Where it shows | A "Not learned" view on the Crafting page, a payback line on pattern tooltips, and a new "Recipe" deal type for patterns on the AH that pay back quickly. |
| Buying a pattern | The usual Deals Find → Buy, one click each. Trainer and vendor purchases are left to the game: the addon never calls `BuyTrainerService` or `BuyMerchantItem`. |
| Other professions | The generator takes a profession name, but only Tailoring ships. A profession with no built-in data shows what has been seen in game, or "No recipe list for X yet." |

## 2. Built-in data (`tools/make-recipes.py`, `recipedata.lua`)

- **Source:** `https://raw.githubusercontent.com/refaim/LibCrafts-1.0/<sha>/Professions/<Profession>.lua`, pinned to commit `e0cc17e13307ac0fc4bfd469b1e4d145b9eb6194`. Its MIT licence text is copied to `TaxTheFools/licenses/LibCrafts-1.0.txt`, and the README credits it.
- **Parsing:** each `module:NewCraft(spellId, "Name", minSkill, {SpellSource...})` chain up to `:Save()`:
  - `:SetResult(itemId)` gives the product.
  - `:AddRecipe(patternId, Quality.X, {RecipeSource...})` gives a pattern and its sources (there may be more than one call).
  - `:AddReagent(itemId, count)` gives a reagent.
  - Crafts inside the `if lib.env.is_turtle_wow then` block are marked `turtle = true`. They are all included, since Ravencraft is a Turtle copy.
  - A craft with no `SetResult` (an enchant-like spell) is skipped.
  - The parser fails loudly, naming the line, when a chain doesn't match. It never silently drops a craft.
- **Output:** `TaxTheFools/recipedata.lua`, generated and committed, never edited by hand. It starts with a header naming the source URL, commit and licence. Shape:

  ```lua
  TaxTheFools.RecipeData = TaxTheFools.RecipeData or {}
  TaxTheFools.RecipeData["Tailoring"] = {
    [3854] = { n = "Azure Silk Gloves", skill = 145, item = 4319, pat = { 7114 }, src = { "vendor" },
               r = { 2321, 2, 4234, 2 } },
    ...
  }
  ```

  - `src` maps spell and recipe sources to `"trainer"`, `"auto"` (learned automatically), `"vendor"`, `"drop"`, `"quest"`, and `"other"` for the rest (chest, fishing, pickpocket, world object). Duplicates are removed and the order is fixed.
  - `r` is a flat id/count list, which keeps the file small.
  - `turtle = true` appears only on Turtle crafts.
  - Keys are sorted, so regenerating with no upstream change gives an identical file.
- **Load order:** `recipedata.lua` loads in the .toc after `data.lua`.

## 3. Learning in game (`recipes_learn.lua`)

All of this only reads. It is merge-only: nothing seen is ever removed by a later read that shows less.

- **Trainer:** `TRAINER_SHOW` and `TRAINER_UPDATE` set a dirty flag, handled at most once per frame (like mail).
  - For `i = 1..GetNumTrainerServices()`, read `GetTrainerServiceInfo(i)` (name, rank, category). Skip `"header"` rows.
  - `GetTrainerServiceSkillReq(i)` gives `skillName, skillRank`. Only rows whose `skillName` is a profession are kept.
  - `GetTrainerServiceCost(i)` gives the cost.
  - Each is stored as `TaxTheFoolsDB.recipes[skillName].trainer[name] = { c = cost, s = skillRank, at = time() }`.
  - The trainer's filters are never changed (no `SetTrainerServiceTypeFilter`). Whatever the window shows is read.
- **Vendor:** phase 2's `I.LearnMerchantPrices` already stores `vb` and `vbLimited` on each pattern item. No change is needed.
- **Pattern tooltips:** when `Tip.Add` runs on an item that has no recipe in the built-in data or in what has been seen, and the item is a pattern, the tooltip's text lines are passed to `Recipes.ParseTip(lines)`.
  - The item is a pattern when its `GetItemInfo` type is `"Recipe"`, or its name starts with `"Pattern: "`, `"Recipe: "`, `"Plans: "`, `"Schematic: "`, `"Formula: "` or `"Manual: "`.
  - `ParseTip` is pure and returns `{ prof, skill, name, reagents = { { name, count } } }` or nil:
    - `prof` and `skill` come from a line `Requires <Profession> (<n>)`.
    - `name` comes from `Teaches you how to <verb> <a/an> <Name>.`, dropping a leading "a " or "an ".
    - `reagents` come from the last line starting `Requires ` that isn't the profession line, split on `, ` into `Name (n)` (or `Name` alone, meaning 1).
  - A result with `prof`, `name` and at least one reagent is stored as `TaxTheFoolsDB.recipes[prof].seen[patternId] = { n, skill, r = { { name, count } }, at }`.
  - The format is the 1.12 recipe tooltip. The probe (§7) dumps one, so the parser can be checked in game.
- **Learned recipes:** phase 2's capture is unchanged. It already holds each character's recipes, rank and maxRank.

## 4. Pure rules (`recipes.lua`)

- **`Recipes.Catalogue(prof, data, learnedDb, realmChars)`** returns one entry per recipe name. It merges three sources:
  1. built-in `data[prof]` entries
  2. `learnedDb[prof].seen` entries whose name is not already built in
  3. a recipe that any realm character has captured, whose reagents and yield replace the built-in ones (the game's own figures win).

  Each entry looks like `{ name, skill, item = key, yieldMin, yieldMax, reagents = { { item = key or nil, name, count } }, pats = { id... }, src = { ... }, turtle, trainer = { c, s } or nil }`. Built-in ids become keys with `U.key(id, 0)`. Seen reagents resolve names through `items` (as in `I.FindByName`); one that doesn't resolve stays as a name with no key, and `Craft.Evaluate` reports it as missing.
- **`Recipes.Unlearned(catalogue, char, prof)`:** entries where neither the name nor the product key is among `char.professions[prof].recipes` (by name, or by any recipe's `item`).
- **`Recipes.Cost(entry, ctx, snapshot)`** returns `cost, source`, where `source` is `"trainer"`, `"vendor"`, `"ah"` or nil. It takes the cheapest of:
  - `entry.trainer.c`
  - each pattern's `items[id].vb`
  - each pattern's cheapest snapshot listing `buyout/count` (key `U.key(id, 0)`), else `ctx.market[key].v`.

  A `"vendor"` result whose item has `vbLimited` sets a third return value `limited = true`.
- **`Recipes.Payback(cost, profit)`** returns `crafts` (an integer ≥ 1), or `0` when `cost` is 0, or `"never"` when profit is nil or ≤ 0 (with cost known), or nil when cost is nil.
- **`Recipes.PatternIndex(catalogue)`** maps a pattern key to its entry.
- **`Recipes.Crafters(realmChars, prof, entry, skillAhead)`** lists the names of realm characters that have captured `prof`, haven't learned `entry`, and have `rank + skillAhead >= entry.skill`. The list is sorted.

## 5. Where it shows

- **Crafting page "Not learned" view** (`ui_craft.lua`):
  - A two-state toggle, **Learned | Not learned**, sits beside the character and profession dropdowns. Learned is the phase 2 view, unchanged.
  - **Columns:** Recipe (white when `skill <= rank`, otherwise the warning colour, with a "T" suffix tag for Turtle recipes), Skill, Get (cost plus source: "AH", "vendor", "vendor (limited)", "trainer", "trainer ?" when the cost is unknown, "drop" or "quest"), Profit (per craft, as phase 2), Payback ("4 crafts", "free", "never", "-"), and Sells (phase 4 `Sales.Stats(...).rate` for the product, "-" with no results).
  - **Default sort:** Payback ascending, with "never" and "-" last.
  - **Filter:** a "Learnable soon" checkbox (default on) keeps only `skill <= rank + skillAhead`.
  - **Detail pane:** sources, the pattern name(s), the material lines (as phase 2), and "Pays back after N crafts at +X each".
  - A profession with nothing in the catalogue shows "No recipe list for X yet."
- **Tooltip line** on pattern items, toggled by `settings.recipes.tooltip`:
  - "Pays back in 4 crafts (+1g 20s each)", "Learned by Name", "No profit per craft", or nothing when no price is known.
  - The crafter used is the first entry of `Recipes.Crafters`. With nobody to learn it, the line reads "Learned by Name" when someone has learned it, and is otherwise omitted.
- **Recipe deals** (`deals.lua`, `Deals.FindRecipes(snapshot, ctx, s, me, src)`):
  - **When:** the snapshot listing is a pattern from `PatternIndex`; it isn't yours; `count == 1`; `Recipes.Crafters` is non-empty; its payback from `buyout` is a number ≤ `paybackCrafts` (default 10); and the pattern's vendor price (if known and not limited) is not below the buyout.
  - **Deal:** `{ type = "recipe", key, count = 1, buyout, unit = buyout, crafter, recipe = name, perCraft, payback, profit = perCraft × paybackCrafts − buyout }`. It is kept only when `profit >= minProfit`.
  - **Deals tab:** type "Recipe". The detail reads "Pays back in N crafts for Name". The action is the normal Find → Buy.

## 6. Options

- **Crafting:** "Pattern payback tooltip line" (`settings.recipes.tooltip`, default on) and "Learnable soon: skill ahead" (`settings.recipes.skillAhead`, 0–75, step 5, default 25).
- **Deals:** "Recipe" switch (`settings.deals.recipe`, default on) and "Pays back within" (`settings.deals.paybackCrafts`, 1–50, default 10). Both are on the Options page only; the rail gets just the switch, matching phase 4.

## 7. Testing

- **Generator:**
  - `make recipes` runs it.
  - A Python unittest feeds a small fixture covering a trainer craft, a vendor pattern, a multi-source drop, two `AddRecipe` calls, a Turtle block, a craft with no result and a malformed chain (which must fail).
  - A Lua test loads the real `recipedata.lua` and checks: more than 200 Tailoring entries; every entry has `n`, `skill`, `item` and an even-length non-empty `r`; 3854 matches the excerpt in §2; and at least one `turtle` entry exists.
- **Fake client:**
  - `GetNumTrainerServices`, `GetTrainerServiceInfo`, `GetTrainerServiceCost`, `GetTrainerServiceSkillReq`, and the `TRAINER_SHOW` / `TRAINER_UPDATE` events.
  - `BuyTrainerService`, `SetTrainerServiceTypeFilter` and `BuyMerchantItem` logged as forbidden.
- **`recipes.lua` units:**
  - the catalogue merge order (captured beats built in, built in beats seen)
  - unlearned by name and by product
  - cost choosing the cheapest of the three sources, plus limited vendor
  - payback (rounding up, free, never, unknown)
  - crafters with skill ahead
  - `ParseTip` on the 1.12 format, a reagent without a count, "an" names, and a non-pattern tooltip (nil).
- **Learning:**
  - a trainer burst gives one read per frame
  - header rows are skipped
  - other skills are ignored
  - merge-only
  - a pattern tooltip stored once.
- **UI:**
  - the Not learned rows, columns, sort and filter
  - the toggle back to Learned showing phase 2 unchanged
  - the tooltip line in each of its forms
  - a recipe deal shown with Find and bought through the existing flow
  - the automation guard extended with the three forbidden calls.
- **Probe:** `Probe.Lines` adds presence checks for the four trainer functions and dumps the scan tooltip's lines for `item:4292` (Pattern: Green Woolen Bag) when that item is cached.
- **In-game checklist:**
  - open the Not learned view
  - visit a Tailoring trainer and see trainer costs fill in
  - visit a pattern vendor
  - hover a pattern on the AH and in the bags
  - find a Recipe deal and buy it
  - check `/ttf probe` shows the pattern tooltip lines.
