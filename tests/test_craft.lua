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

-- ---------- Craft.Options and the sub-lines ----------

T.test("Options: buy only, craft only", function()
  local ctx = ctxOf({ ["4305:0"] = { v = 2000, lowDay = 20370 } }, {}, {})
  local o = C.Options("4305:0", ctx)
  T.eq(o.buy, 2000) T.eq(o.buySource, "ah") T.eq(o.buyDay, 20370)
  T.eq(o.craft, nil) T.eq(o.recipe, nil)
  ctx = ctxOf({ ["4306:0"] = { v = 300, lowDay = 20374 } }, {}, { B = bolt() })
  o = C.Options("4305:0", ctx)
  T.eq(o.buy, nil) T.eq(o.buySource, nil)
  T.eq(o.craft, 1200) T.eq(o.craftDay, 20374)
  T.eq(o.recipe, ctx.recipes["4305:0"][1])
end)

T.test("Options: both known, craft cheaper and buy cheaper", function()
  local ctx = ctxOf({ ["4306:0"] = { v = 300 }, ["4305:0"] = { v = 2000 } }, {}, { B = bolt() })
  local o = C.Options("4305:0", ctx)
  T.eq(o.buy, 2000) T.eq(o.craft, 1200)
  ctx = ctxOf({ ["4306:0"] = { v = 300 }, ["4305:0"] = { v = 1000 } }, {}, { B = bolt() })
  o = C.Options("4305:0", ctx)
  T.eq(o.buy, 1000, "buy is reported even when crafting costs more") T.eq(o.craft, 1200)
  T.eq(C.UnitCost("4305:0", ctx, 0), 1000, "costing is unchanged")
end)

T.test("Options: the cheapest of several recipes; a cycle does not loop", function()
  local dear = { item = "4305:0", yieldMin = 1, yieldMax = 1, reagents = { { item = "4306:0", count = 9 } } }
  local ctx = ctxOf({ ["4306:0"] = { v = 300 } }, {}, { A = dear, B = bolt() })
  local o = C.Options("4305:0", ctx)
  T.eq(o.craft, 1200)
  T.eq(o.recipe.reagents[1].count, 4)
  local cyc = ctxOf({ ["9102:0"] = { v = 30 } }, {}, { A = link("9102:0", "9101:0", 2), B = link("9101:0", "9102:0", 1) })
  o = C.Options("9101:0", cyc)
  T.eq(o.craft, 60) T.eq(o.buy, nil)
  cyc.busy["9101:0"] = true
  o = C.Options("9101:0", cyc)
  T.eq(o.craft, nil, "a busy item is not crafted again")
end)

T.test("Evaluate attaches options and scaled sub-lines to a craftable material", function()
  local ctx = ctxOf({ ["4306:0"] = { v = 300 }, ["4305:0"] = { v = 2000 }, ["9100:0"] = { v = 9000 } },
    { [4306] = { n = "Silk Cloth" }, [4305] = { n = "Bolt of Silk Cloth" } }, { B = bolt() })
  local r = { item = "9100:0", reagents = { { item = "4305:0", name = "Bolt of Silk Cloth", count = 3 },
    { item = "4306:0", name = "Silk Cloth", count = 1 } } }
  local ev = C.Evaluate(r, ctx, true)
  local l = ev.lines[1]
  T.eq(l.options.craft, 1200) T.eq(l.options.buy, 2000)
  T.eq(table.getn(l.sub), 1)
  T.eq(l.sub[1].need, 12, "3 bolts x 4 silk, yield 1")
  T.eq(C.Evaluate(r, ctx).lines[1].options, nil, "not computed unless asked")
  T.eq(C.Evaluate(r, ctx).lines[1].sub, nil)
  T.eq(l.sub[1].name, "Silk Cloth") T.eq(l.sub[1].unit, 300) T.eq(l.sub[1].source, "ah")
  T.eq(ev.lines[2].options, nil, "silk has no recipe")
  T.eq(ev.lines[2].sub, nil)
  T.eq(ev.cost, 3 * 1200 + 300, "costing still uses the cheaper option")
end)

T.test("sub-line counts use the smallest yield: whole crafts' worth", function()
  local two = { item = "4305:0", yieldMin = 1, yieldMax = 2, reagents = { { item = "4306:0", count = 3 } } }
  local ctx = ctxOf({ ["4306:0"] = { v = 300 } }, { [4306] = { n = "Silk Cloth" } }, { B = two })
  local r = { item = "9100:0", reagents = { { item = "4305:0", name = "Bolt", count = 1 } } }
  T.eq(C.Evaluate(r, ctx, true).lines[1].sub[1].need, 3, "one craft uses 3, not 2")
end)
