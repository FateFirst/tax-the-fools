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

T.test("a recipe the window stops listing is kept: capture only merges", function()
  tailoring()
  WoW.fire("TRADE_SKILL_SHOW")
  table.remove(WoW.tradeskill.rows, 4)     -- a filter hides the robe
  WoW.fire("TRADE_SKILL_UPDATE")
  WoW.clock = WoW.clock + 0.5
  tick()
  T.ok(tailoringRecipes()["Brown Linen Robe"], "still stored after a later capture without it")
  T.ok(tailoringRecipes()["Bolt of Silk Cloth"])
end)

T.test("a recapture updates the fields of the recipes it lists", function()
  tailoring()
  WoW.fire("TRADE_SKILL_SHOW")
  local rows = WoW.tradeskill.rows
  rows[2].type, rows[2].made = "easy", { 2, 3 }        -- colour and yields change
  rows[2].reagents[1].count = 5
  WoW.fire("TRADE_SKILL_UPDATE")
  WoW.clock = WoW.clock + 0.5
  tick()
  local bolt = tailoringRecipes()["Bolt of Silk Cloth"]
  T.eq(bolt.color, "easy") T.eq(bolt.yieldMin, 2) T.eq(bolt.yieldMax, 3)
  T.eq(bolt.reagents[1].count, 5)
  T.eq(bolt.reagents[1].item, "4306:0", "the reagent's key is still there")
  T.eq(DB.Char().professions.Tailoring.recipes["Brown Linen Robe"].color, "trivial", "the robe is untouched")
end)

T.test("a reagent whose link is missing on a later capture keeps its stored key", function()
  tailoring()
  WoW.fire("TRADE_SKILL_SHOW")
  WoW.tradeskill.rows[2].reagents[1].noLink = true
  WoW.fire("TRADE_SKILL_UPDATE")
  WoW.clock = WoW.clock + 0.5
  tick()
  T.eq(tailoringRecipes()["Bolt of Silk Cloth"].reagents[1].item, "4306:0", "a link not cached this time does not lose the key")
  T.eq(tailoringRecipes()["Bolt of Silk Cloth"].reagents[1].name, "Silk Cloth")
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
