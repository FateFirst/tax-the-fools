local C, S = TaxTheFools.Craft, TaxTheFools.Shopping
local TODAY = 20375

local function ctxOf(market, items, recipes, held)
  local chars = { Tailor = { professions = { Tailoring = { recipes = recipes or {} } } } }
  return C.Context({ market = market or {}, chars = chars }, items or {}, held or {}, TODAY)
end

local function bolt()
  return { item = "4305:0", yieldMin = 1, yieldMax = 1,
           reagents = { { item = "4306:0", name = "Silk Cloth", count = 4 } } }
end

-- A robe: 2 bolts and 1 thread.
local function robe()
  return { item = "9000:0", yieldMin = 1, yieldMax = 1, reagents = {
    { item = "4305:0", name = "Bolt of Silk Cloth", count = 2 },
    { item = "2321:0", name = "Fine Thread", count = 1 } } }
end

local ITEMS = { [4306] = { n = "Silk Cloth" }, [4305] = { n = "Bolt of Silk Cloth" },
                [2321] = { n = "Fine Thread", vb = 100 } }

T.test("buy only: every material is bought at its price", function()
  local ctx = ctxOf({ ["4306:0"] = { v = 300 }, ["4305:0"] = { v = 900 } }, ITEMS, { B = bolt() })
  local p = S.Plan(robe(), 3, ctx, {})
  T.eq(p.buys[1].key, "4305:0") T.eq(p.buys[1].qty, 6) T.eq(p.buys[1].unit, 900)
  T.eq(p.buys[1].source, "ah") T.eq(p.buys[1].total, 5400)
  T.eq(p.buys[2].key, "2321:0") T.eq(p.buys[2].qty, 3) T.eq(p.buys[2].source, "vendor")
  T.eq(p.buys[2].total, 300)
  T.eq(p.total, 5700)
  T.eq(table.getn(p.crafts), 0)
end)

T.test("crafting cheaper expands into its materials", function()
  local ctx = ctxOf({ ["4306:0"] = { v = 300 }, ["4305:0"] = { v = 2000 } }, ITEMS, { B = bolt() })
  local p = S.Plan(robe(), 2, ctx, {})
  T.eq(table.getn(p.crafts), 1)
  T.eq(p.crafts[1].key, "4305:0") T.eq(p.crafts[1].qty, 4) T.eq(p.crafts[1].name, "Bolt of Silk Cloth")
  T.eq(p.buys[1].key, "4306:0") T.eq(p.buys[1].qty, 16) T.eq(p.buys[1].total, 4800)
  T.eq(p.total, 4800 + 200)
end)

T.test("a bolt you already hold is used before crafting another", function()
  local ctx = ctxOf({ ["4306:0"] = { v = 300 }, ["4305:0"] = { v = 2000 } }, ITEMS, { B = bolt() })
  local held = { ["4305:0"] = 3 }
  local p = S.Plan(robe(), 2, ctx, held)   -- needs 4 bolts, holds 3
  T.eq(p.crafts[1].qty, 1)
  T.eq(p.buys[1].key, "4306:0") T.eq(p.buys[1].qty, 4, "silk for one bolt only")
  T.eq(held["4305:0"], 3, "the caller's holdings are untouched")
  p = S.Plan(robe(), 1, ctx, held)          -- 2 bolts, all held
  T.eq(table.getn(p.crafts), 0)
  T.eq(p.buys[1].key, "2321:0", "only the thread is left")
  T.eq(table.getn(p.buys), 1)
end)

T.test("holdings of raw materials reduce the buy, and are not counted twice", function()
  local ctx = ctxOf({ ["4306:0"] = { v = 300 }, ["4305:0"] = { v = 2000 } }, ITEMS, { B = bolt() })
  -- 5 silk held (summed across characters by the caller); 2 bolts need 8
  local p = S.Plan(robe(), 1, ctx, { ["4306:0"] = 5 })
  T.eq(p.buys[1].key, "4306:0") T.eq(p.buys[1].qty, 3)
  -- the same silk must not also cover a second line
  local two = { item = "9001:0", reagents = {
    { item = "4305:0", count = 1 }, { item = "4306:0", count = 2 } } }
  p = S.Plan(two, 1, ctx, { ["4306:0"] = 5 })   -- bolt takes 4 silk, then 2 more: 1 short of 6
  T.eq(p.buys[1].key, "4306:0") T.eq(p.buys[1].qty, 1)
  T.eq(table.getn(p.buys), 1)
end)

T.test("intermediate crafts round up on the smallest yield", function()
  local two = { item = "4305:0", yieldMin = 2, yieldMax = 3, reagents = { { item = "4306:0", count = 3 } } }
  local ctx = ctxOf({ ["4306:0"] = { v = 100 }, ["4305:0"] = { v = 5000 } }, ITEMS, { B = two })
  local r = { item = "9100:0", reagents = { { item = "4305:0", count = 5 } } }
  local p = S.Plan(r, 1, ctx, {})
  T.eq(p.crafts[1].qty, 3, "ceil(5 / 2)")
  T.eq(p.buys[1].qty, 9)
end)

T.test("a material with no price goes to missing", function()
  local ctx = ctxOf({ ["4306:0"] = { v = 300 } }, ITEMS, {})
  local r = { item = "9100:0", reagents = {
    { item = "4306:0", count = 1 }, { item = "7777:0", name = "Mystery", count = 1 } } }
  local p = S.Plan(r, 1, ctx, {})
  T.eq(table.getn(p.missing), 1) T.eq(p.missing[1], "Mystery")
  T.eq(table.getn(p.buys), 1) T.eq(p.total, 300)
end)

T.test("lines for the same material merge", function()
  local ctx = ctxOf({ ["4306:0"] = { v = 300 }, ["4305:0"] = { v = 2000 } }, ITEMS, { B = bolt() })
  local r = { item = "9100:0", reagents = {
    { item = "4305:0", count = 1 }, { item = "4306:0", count = 2 }, { item = "4305:0", count = 1 } } }
  local p = S.Plan(r, 1, ctx, {})
  T.eq(table.getn(p.buys), 1)
  T.eq(p.buys[1].qty, 2 + 8)
  T.eq(table.getn(p.crafts), 1) T.eq(p.crafts[1].qty, 2)
end)

T.test("a recipe cycle terminates", function()
  local a = { item = "9101:0", reagents = { { item = "9102:0", count = 2 } } }
  local b = { item = "9102:0", reagents = { { item = "9101:0", count = 1 } } }
  local ctx = ctxOf({ ["9102:0"] = { v = 30 } }, {}, { A = a, B = b })
  local p = S.Plan({ item = "9000:0", reagents = { { item = "9101:0", count = 1 } } }, 1, ctx, {})
  T.eq(type(p.total), "number")
  local p2 = S.Plan(b, 1, ctx, {})
  T.eq(type(p2.total), "number")
end)
