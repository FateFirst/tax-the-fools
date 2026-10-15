local R = TaxTheFools.Recipes
local K = TaxTheFools.Util.key
local items = { [2589] = { n = "Linen Cloth" }, [2996] = { n = "Bolt of Linen Cloth" }, [2320] = { n = "Coarse Thread" } }
local data = { Tailoring = {
  [1] = { n = "Bolt of Linen Cloth", skill = 1, item = 2996, pat = {}, src = { "trainer" }, r = { 2589, 2 } },
  [2] = { n = "Green Woolen Bag", skill = 70, item = 4241, pat = { 4292 }, src = { "vendor" }, r = { 2996, 4, 2320, 2 } },
  [3] = { n = "Fancy Cape", skill = 200, item = 9999, pat = { 5001, 5002 }, src = { "drop" }, r = { 2589, 1 }, turtle = true },
} }
local function find(cat, name) for _, e in ipairs(cat) do if e.name == name then return e end end end

T.test("catalogue builds built-in entries with keys, names and yield 1", function()
  local cat = R.Catalogue("Tailoring", data, nil, nil, items)
  T.eq(table.getn(cat), 3)
  T.eq(cat[1].name, "Bolt of Linen Cloth")
  local e = find(cat, "Green Woolen Bag")
  T.eq(e.item, "4241:0") T.eq(e.yieldMin, 1) T.eq(e.yieldMax, 1) T.eq(e.skill, 70)
  T.eq(e.reagents[1].item, "2996:0") T.eq(e.reagents[1].name, "Bolt of Linen Cloth") T.eq(e.reagents[1].count, 4)
  T.eq(e.pats[1], 4292) T.eq(e.src[1], "vendor")
  T.eq(find(cat, "Fancy Cape").turtle, true)
end)

T.test("catalogue: seen entries are added unless built in, with names resolved", function()
  local db = { Tailoring = { seen = {
    [7777] = { n = "Mystery Hat", skill = 50, r = { { "x" } } },
    [4292] = { n = "Green Woolen Bag", skill = 1, r = {} } } } }
  db.Tailoring.seen[7777].r = { { name = "Linen Cloth", count = 3 }, { name = "Unknown Dust", count = 1 } }
  local cat = R.Catalogue("Tailoring", data, db, nil, items)
  T.eq(table.getn(cat), 4)
  local e = find(cat, "Mystery Hat")
  T.eq(e.skill, 50) T.eq(e.pats[1], 7777)
  T.eq(e.reagents[1].item, "2589:0") T.eq(e.reagents[2].item, nil) T.eq(e.reagents[2].name, "Unknown Dust")
  T.eq(find(cat, "Green Woolen Bag").skill, 70)  -- built in beats seen
end)

T.test("catalogue: captured beats built in, and trainer costs attach", function()
  local chars = { Al = { professions = { Tailoring = { rank = 100, recipes = {
    ["Green Woolen Bag"] = { item = "4241:0", yieldMin = 2, yieldMax = 3, reagents = { { item = "2589:0", name = "Linen Cloth", count = 9 } } } } } } } }
  local db = { Tailoring = { trainer = { ["Bolt of Linen Cloth"] = { c = 100, s = 1 } } } }
  local cat = R.Catalogue("Tailoring", data, db, chars, items)
  local e = find(cat, "Green Woolen Bag")
  T.eq(e.yieldMin, 2) T.eq(e.yieldMax, 3) T.eq(table.getn(e.reagents), 1) T.eq(e.reagents[1].count, 9)
  T.eq(e.pats[1], 4292)
  T.eq(find(cat, "Bolt of Linen Cloth").trainer.c, 100)
  T.eq(find(cat, "Bolt of Linen Cloth").trainer.s, 1)
end)

T.test("unlearned by name and by product, including a renamed recipe (focus 1)", function()
  local chars = { Al = { professions = { Tailoring = { rank = 100, recipes = {
    ["Bolt of Linen Cloth"] = { item = "2996:0" },
    ["Turtle Woolen Satchel"] = { item = "4241:0", reagents = {} } } } } } }
  local cat = R.Catalogue("Tailoring", data, nil, chars, items)
  T.eq(table.getn(cat), 3)  -- the rename merges into the built-in entry, no duplicate
  local un = R.Unlearned(cat, chars.Al, "Tailoring")
  T.eq(table.getn(un), 1) T.eq(un[1].name, "Fancy Cape")
  local un2 = R.Unlearned(cat, { professions = {} }, "Tailoring")
  T.eq(table.getn(un2), 3)
  T.eq(table.getn(R.Unlearned(cat, nil, "Tailoring")), 3)
end)

local function snap(id, rows) local s = { rows = {} } s.rows[K(id, 0)] = rows return s end

T.test("cost takes the cheapest of trainer, vendor and AH", function()
  local e = { name = "x", pats = { 10 }, trainer = { c = 500 } }
  local ctx = { items = { [10] = { vb = 300 } }, market = {} }
  local c, src, lim = R.Cost(e, ctx, nil)
  T.eq(c, 300) T.eq(src, "vendor") T.eq(lim, nil)
  c, src = R.Cost(e, ctx, snap(10, { "2|400||bob" }))  -- 200 each
  T.eq(c, 200) T.eq(src, "ah")
  c, src = R.Cost(e, { items = {}, market = {} }, nil)
  T.eq(c, 500) T.eq(src, "trainer")
  c, src = R.Cost(e, { items = {}, market = { [K(10, 0)] = { v = 450 } } }, nil)
  T.eq(c, 450) T.eq(src, "ah")
  c, src = R.Cost({ name = "y", pats = { 10 } }, { items = {}, market = {} }, nil)
  T.eq(c, nil) T.eq(src, nil)
  T.eq(R.Cost({ name = "z", pats = {} }, { items = {}, market = {} }, nil), nil)
end)

T.test("cost: a snapshot listing beats the market value, and the cheapest listing wins", function()
  local e = { name = "x", pats = { 10 } }
  local ctx = { items = {}, market = { [K(10, 0)] = { v = 900 } } }
  local c = R.Cost(e, ctx, snap(10, { "1|700||a", "1|600||b" }))
  T.eq(c, 600)
end)

T.test("cost: limited vendor is labelled, and a cheaper AH price is still used (focus 2)", function()
  local e = { name = "x", pats = { 10 } }
  local ctx = { items = { [10] = { vb = 300, vbLimited = true } }, market = {} }
  local c, src, lim = R.Cost(e, ctx, nil)
  T.eq(c, 300) T.eq(src, "vendor") T.eq(lim, true)
  c, src, lim = R.Cost(e, ctx, snap(10, { "1|250||a" }))
  T.eq(c, 250) T.eq(src, "ah") T.eq(lim, nil)
  c, src, lim = R.Cost(e, ctx, snap(10, { "1|350||a" }))
  T.eq(c, 300) T.eq(lim, true)
end)

T.test("payback rounds up, free, never, unknown", function()
  T.eq(R.Payback(1000, 300), 4)
  T.eq(R.Payback(900, 300), 3)
  T.eq(R.Payback(1, 300), 1)
  T.eq(R.Payback(0, 300), 0)
  T.eq(R.Payback(0, nil), 0)
  T.eq(R.Payback(1000, 0), "never")
  T.eq(R.Payback(1000, -5), "never")
  T.eq(R.Payback(1000, nil), "never")
  T.eq(R.Payback(nil, 300), nil)
end)

T.test("pattern index maps each pattern key to its entry", function()
  local cat = R.Catalogue("Tailoring", data, nil, nil, items)
  local idx = R.PatternIndex(cat)
  T.eq(idx["4292:0"].name, "Green Woolen Bag")
  T.eq(idx["5001:0"].name, "Fancy Cape") T.eq(idx["5002:0"].name, "Fancy Cape")
  T.eq(idx["1:0"], nil)
end)

T.test("crafters: realm characters who can learn it, sorted, with skill ahead", function()
  local chars = {
    Zed = { professions = { Tailoring = { rank = 60, recipes = {} } } },
    Amy = { professions = { Tailoring = { rank = 40, recipes = {} } } },
    Bob = { professions = { Tailoring = { rank = 200, recipes = { ["Green Woolen Bag"] = {} } } } },
    Cat = { professions = { Mining = { rank = 300, recipes = {} } } },
    Dan = { professions = {} } }
  local e = { name = "Green Woolen Bag", skill = 70 }
  local l = R.Crafters(chars, "Tailoring", e, 0)
  T.eq(table.getn(l), 0)
  l = R.Crafters(chars, "Tailoring", e, 10)
  T.eq(table.getn(l), 1) T.eq(l[1], "Zed")
  l = R.Crafters(chars, "Tailoring", e, 30)
  T.eq(table.getn(l), 2) T.eq(l[1], "Amy") T.eq(l[2], "Zed")
  T.eq(table.getn(R.Crafters(chars, "Tailoring", e)), 0)
end)

local TIP = { "Pattern: Green Woolen Bag", "Requires Tailoring (70)", "Use: Teaches you how to make a Green Woolen Bag.",
  "Requires Bolt of Woolen Cloth (4), Coarse Thread (2)" }

T.test("parsetip reads the 1.12 recipe tooltip", function()
  local r = R.ParseTip(TIP)
  T.eq(r.prof, "Tailoring") T.eq(r.skill, 70) T.eq(r.name, "Green Woolen Bag")
  T.eq(table.getn(r.reagents), 2)
  T.eq(r.reagents[1].name, "Bolt of Woolen Cloth") T.eq(r.reagents[1].count, 4)
  T.eq(r.reagents[2].name, "Coarse Thread") T.eq(r.reagents[2].count, 2)
end)

T.test("parsetip: a reagent without a count, an single reagent, and 'an' names", function()
  local r = R.ParseTip({ "Requires Tailoring (10)", "Teaches you how to sew an Embroidered Hat.", "Requires Fine Thread, Linen Cloth (2)" })
  T.eq(r.name, "Embroidered Hat")
  T.eq(r.reagents[1].name, "Fine Thread") T.eq(r.reagents[1].count, 1) T.eq(r.reagents[2].count, 2)
  r = R.ParseTip({ "Requires Tailoring (10)", "Teaches you how to make a Hat.", "Requires Linen Cloth (2)" })
  T.eq(r.prof, "Tailoring") T.eq(table.getn(r.reagents), 1) T.eq(r.reagents[1].name, "Linen Cloth")
  r = R.ParseTip({ "Requires Tailoring (10)", "Teaches you how to make a Hat.", "Requires Linen Cloth" })
  T.eq(r.reagents[1].count, 1)
end)

T.test("parsetip returns nil for non-patterns and incomplete tooltips", function()
  T.eq(R.ParseTip({ "Linen Cloth", "Vendor Price: 1c" }), nil)
  T.eq(R.ParseTip({}), nil)
  T.eq(R.ParseTip(nil), nil)
  T.eq(R.ParseTip({ "Requires Level 10", "Binds when picked up" }), nil)
  T.eq(R.ParseTip({ "Requires Tailoring (70)", "Teaches you how to make a Hat." }), nil)
end)

T.test("ispattern: recipe type or a pattern prefix", function()
  T.ok(R.IsPattern("Anything", "Recipe"))
  for _, p in ipairs({ "Pattern: ", "Recipe: ", "Plans: ", "Schematic: ", "Formula: ", "Manual: " }) do
    T.ok(R.IsPattern(p .. "Thing", "Misc"), p)
  end
  T.ok(not R.IsPattern("Linen Cloth", "Trade Goods"))
  T.ok(not R.IsPattern("The Pattern: x", nil))
  T.ok(not R.IsPattern(nil, nil))
end)

T.test("recipes settings and db defaults", function()
  local s = TaxTheFools.Data.DEFAULTS.settings
  T.eq(s.recipes.tooltip, true) T.eq(s.recipes.skillAhead, 25)
  T.eq(s.deals.recipe, true) T.eq(s.deals.paybackCrafts, 10)
  TaxTheFools.DB.Init()
  T.eq(type(TaxTheFoolsDB.recipes), "table")
end)
