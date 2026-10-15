local A = TaxTheFools
local RL, Tip = A.RecipesLearn, A.Tooltip

local function frame()
  WoW.clock = WoW.clock + 0.1
  WoW.runScript(TaxTheFoolsCore, "OnUpdate")
end
local function rec(prof) return TaxTheFoolsDB.recipes[prof] end

local ROWS = {
  { name = "Tailoring", category = "header" },
  { name = "Bolt of Linen Cloth", rank = "", category = "available", cost = 100, skill = "Tailoring", skillRank = 1 },
  { name = "Heavy Linen Gloves", category = "available", cost = 350, skill = "Tailoring", skillRank = 40 },
  { name = "Smelt Copper", category = "available", cost = 50, skill = "Mining", skillRank = 1 },
  { name = "Rend", category = "available", cost = 10 },
}

T.test("the module is loaded and the trainer events are registered", function()
  T.ok(RL)
  T.ok(TaxTheFoolsCore.events.TRAINER_SHOW) T.ok(TaxTheFoolsCore.events.TRAINER_UPDATE)
end)

T.test("a trainer burst gives one read per frame, headers and other skills skipped", function()
  WoW.trainer = ROWS
  WoW.fire("TRAINER_SHOW")
  for _ = 1, 30 do WoW.fire("TRAINER_UPDATE") end
  T.eq(TaxTheFoolsDB.recipes.Tailoring, nil, "nothing before the frame")
  local n = 0
  local orig = GetNumTrainerServices
  GetNumTrainerServices = function() n = n + 1 return orig() end
  frame() frame() frame()
  GetNumTrainerServices = orig
  T.eq(n, 1, "one read")
  local t = rec("Tailoring").trainer
  T.eq(t["Bolt of Linen Cloth"].c, 100) T.eq(t["Bolt of Linen Cloth"].s, 1)
  T.eq(t["Heavy Linen Gloves"].c, 350) T.eq(t["Heavy Linen Gloves"].s, 40) T.eq(t["Heavy Linen Gloves"].at, WoW.now)
  T.eq(t.Tailoring, nil, "header skipped")
  T.eq(rec("Mining").trainer["Smelt Copper"].c, 50, "any profession is kept")
  T.eq(rec("Rend"), nil, "a class spell is not a profession")
  T.eq(T.count("BuyTrainerService"), 0) T.eq(T.count("SetTrainerServiceTypeFilter"), 0)
end)

T.test("trainer reads are merge-only", function()
  WoW.trainer = ROWS
  WoW.fire("TRAINER_SHOW") frame()
  WoW.trainer = { { name = "Heavy Linen Gloves", category = "available", cost = 300, skill = "Tailoring", skillRank = 40 } }
  WoW.fire("TRAINER_UPDATE") frame()
  local t = rec("Tailoring").trainer
  T.eq(t["Heavy Linen Gloves"].c, 300, "updated")
  T.eq(t["Bolt of Linen Cloth"].c, 100, "not removed by a read that shows less")
end)

local TIP = { "Pattern: Green Woolen Bag", "Requires Tailoring (70)", "Teaches you how to make a Green Woolen Bag.",
              "Requires Bolt of Woolen Cloth (4), Fine Thread (2)" }

local function hover(id, lines)
  WoW.items[id] = { name = (lines and lines[1]) or "Thing", type = "Recipe" }
  GameTooltip:ClearLines()
  for _, l in ipairs(lines or {}) do GameTooltip:AddLine(l) end
  Tip.Add(GameTooltip, WoW.link(id, WoW.items[id].name), 1)
end

T.test("a pattern tooltip with no known recipe is stored once", function()
  hover(99001, TIP)
  local s = rec("Tailoring").seen[99001]
  T.eq(s.n, "Green Woolen Bag") T.eq(s.skill, 70) T.eq(s.at, WoW.now)
  T.eq(s.r[1].name, "Bolt of Woolen Cloth") T.eq(s.r[1].count, 4) T.eq(s.r[2].count, 2)
  s.n = "marker"
  hover(99001, TIP)
  T.eq(rec("Tailoring").seen[99001].n, "marker", "not read or stored again")
end)

T.test("built-in patterns, non-patterns and unparsable tooltips store nothing", function()
  local pat
  for _, d in pairs(TaxTheFools.RecipeData.Tailoring) do if d.pat and d.pat[1] then pat = d.pat[1] break end end
  hover(pat, TIP)
  T.eq(rec("Tailoring"), nil, "already in the built-in data")
  WoW.items[5000] = { name = "Linen Cloth", type = "Trade Goods" }
  GameTooltip:ClearLines() for _, l in ipairs(TIP) do GameTooltip:AddLine(l) end
  Tip.Add(GameTooltip, WoW.link(5000, "Linen Cloth"), 1)
  T.eq(rec("Tailoring"), nil, "not a pattern")
  hover(99002, { "Pattern: Mystery", "Soulbound" })
  T.eq(rec("Tailoring"), nil, "nothing parsed")
end)

T.test("a pattern by name prefix is learned even when the type is not Recipe", function()
  WoW.items[99003] = { name = "Pattern: Green Woolen Bag", type = "Miscellaneous" }
  GameTooltip:ClearLines() for _, l in ipairs(TIP) do GameTooltip:AddLine(l) end
  Tip.Add(GameTooltip, WoW.link(99003, "Pattern: Green Woolen Bag"), 1)
  T.ok(rec("Tailoring").seen[99003])
end)

T.test("an uncached item is skipped", function()
  GameTooltip:ClearLines() for _, l in ipairs(TIP) do GameTooltip:AddLine(l) end
  Tip.Add(GameTooltip, WoW.link(99004, "x"), 1)
  T.eq(rec("Tailoring"), nil)
end)

T.test("the probe lists the trainer functions and the pattern tooltip", function()
  local all = table.concat(A.Probe.Lines(), "\n")
  for _, n in ipairs({ "GetNumTrainerServices", "GetTrainerServiceInfo", "GetTrainerServiceCost", "GetTrainerServiceSkillReq" }) do
    T.ok(string.find(all, "fn " .. n .. " yes", 1, true), n)
  end
  T.ok(string.find(all, "item:4292 not cached", 1, true), all)
  WoW.items[4292] = { name = "Pattern: Green Woolen Bag", type = "Recipe" }
  WoW.tooltips[4292] = TIP
  all = table.concat(A.Probe.Lines(), "\n")
  T.ok(string.find(all, "Teaches you how to make a Green Woolen Bag.", 1, true), all)
  T.ok(string.find(all, "(4 lines)", 1, true), all)
end)
