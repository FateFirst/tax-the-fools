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

T.test("a product whose link is missing on a later capture keeps its stored key", function()
  tailoring()
  WoW.fire("TRADE_SKILL_SHOW")
  WoW.tradeskill.rows[2].noLink = true
  WoW.fire("TRADE_SKILL_UPDATE")
  WoW.clock = WoW.clock + 0.5
  tick()
  T.eq(tailoringRecipes()["Bolt of Silk Cloth"].item, "4305:0", "a product link not cached this time does not lose the key")
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

T.test("closing the window forgets the strip's selection memo, so a reopened window repaints", function()
  priced()
  tailoring()
  WoW.tradeskill.selected = 2
  WoW.openTradeSkill()
  T.eq(TS.strip.text:GetText(), "Cost 12s   Value 19s   Profit 7s", "session one: the bolt")
  T.eq(TS.strip.sel, 2)
  WoW.fire("TRADE_SKILL_CLOSE")
  TradeSkillFrame:Hide()
  T.eq(TS.strip.sel, false, "the memo is reset on close")
  -- Another profession, same index 2: a different recipe (the robe, whose bolts have no price).
  local rows = WoW.tradeskill.rows
  rows[2], rows[4] = rows[4], rows[2]
  TradeSkillFrame:Show()                           -- shown by the client; the strip polls before any event
  WoW.clock = WoW.clock + 0.25
  tick()
  T.eq(TS.strip.text:GetText(), "incomplete: Bolt of Linen Cloth, Coarse Thread", "session two: the robe, not the bolt")
end)

T.test("the strip is made by the poll when TradeSkillFrame appears after the first show", function()
  local savedFrame, savedStrip = TradeSkillFrame, TS.strip
  TradeSkillFrame, TS.strip = nil, nil
  tailoring()
  WoW.fire("TRADE_SKILL_SHOW")
  T.eq(TS.strip, nil, "no frame yet")
  TradeSkillFrame = CreateFrame("Frame", "TradeSkillFrame", UIParent)
  WoW.clock = WoW.clock + 0.25
  tick()
  T.ok(TS.strip, "the poll made it once the frame exists")
  T.eq(TS.strip:GetParent(), TradeSkillFrame)
  TradeSkillFrame, TS.strip = savedFrame, savedStrip
end)
