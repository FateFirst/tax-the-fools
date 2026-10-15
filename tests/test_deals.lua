local Dl = TaxTheFools.Deals
local C = TaxTheFools.Craft
local TODAY = 20375

local function ctxOf(market, items, recipes)
  local chars = { Me = { professions = { Tailoring = { recipes = recipes or {} } } } }
  return C.Context({ market = market, chars = chars }, items or {}, {}, TODAY)
end
local function S(o)
  local s = { market = true, vendor = true, mats = true, belowMarketPct = 70, minProfit = 1, matPct = 85, minConfidence = 0.4 }
  for k, v in pairs(o or {}) do s[k] = v end
  return s
end
local function snap(key, ...)
  local rows = {}
  for i = 1, arg.n do rows[i] = arg[i] end
  return { rows = { [key] = rows } }
end

-- Item A: market 1000 (conf 0.8), vendor sell 100, stack 20.
local function ctxA(conf)
  return ctxOf({ ["100:0"] = { v = 1000, conf = conf or 0.8 } }, { [100] = { n = "A", v = 100, st = 20 } })
end

T.test("below market triggers at exactly 70% and includes the cut and the deposit", function()
  -- 1 at 700 = 70%. deposit = floor(100*1*4*(1+19*0.05)*0.025) = floor(19.5) = 19.
  -- profit = 1000*0.95 - 700 - 19 = 231.
  local d = Dl.ListingProfit("100:0", 1, 700, ctxA(), S())
  T.eq(d.type, "market") T.eq(d.profit, 231) T.eq(d.depositUnknown, false) T.eq(d.market, 1000)
  T.near(d.pct, 70, 0.001)
  -- 5 at 3500 = 700 each. deposit = floor(100*5*4*(1+15*0.05)*0.025) = floor(87.5) = 87.
  -- profit = 5*1000*0.95 - 3500 - 87 = 1163.
  T.eq(Dl.ListingProfit("100:0", 5, 3500, ctxA(), S()).profit, 1163)
end)

T.test("below market does not trigger at 71%, low confidence, or without a market value", function()
  T.eq(Dl.ListingProfit("100:0", 1, 710, ctxA(), S({ vendor = false })), nil, "71% of 1000")
  T.eq(Dl.ListingProfit("100:0", 1, 700, ctxA(0.39), S({ vendor = false })), nil, "confidence 0.39 < 0.4")
  T.ok(Dl.ListingProfit("100:0", 1, 700, ctxA(0.4), S()), "confidence exactly 0.4 is enough")
  T.eq(Dl.ListingProfit("999:0", 1, 1, ctxOf({}, {}), S()), nil, "no market value")
  T.eq(Dl.ListingProfit("100:0", 1, 700, ctxA(), S({ market = false, vendor = false })), nil)
end)

T.test("below market needs the minimum profit", function()
  T.eq(Dl.ListingProfit("100:0", 1, 700, ctxA(), S({ minProfit = 232, vendor = false })), nil, "231 < 232")
  T.ok(Dl.ListingProfit("100:0", 1, 700, ctxA(), S({ minProfit = 231, vendor = false })))
end)

T.test("an unknown vendor price makes the deposit 0 and flags the deal", function()
  -- no vendor price: profit = 1000*0.95 - 700 = 250.
  local ctx = ctxOf({ ["100:0"] = { v = 1000, conf = 0.8 } }, {})
  local d = Dl.ListingProfit("100:0", 1, 700, ctx, S())
  T.eq(d.type, "market") T.eq(d.profit, 250) T.eq(d.depositUnknown, true)
end)

T.test("below vendor triggers under count x vendor price and not without a vendor price", function()
  local ctx = ctxOf({}, { [200] = { n = "B", v = 500 } })
  -- 1 at 400: 500 - 400 = 100.
  local d = Dl.ListingProfit("200:0", 1, 400, ctx, S())
  T.eq(d.type, "vendor") T.eq(d.profit, 100) T.eq(d.owner, nil)
  -- 2 at 999: 1000 - 999 = 1.
  T.eq(Dl.ListingProfit("200:0", 2, 999, ctx, S()).profit, 1)
  T.eq(Dl.ListingProfit("200:0", 2, 1000, ctx, S()), nil, "at the vendor price is not a deal")
  T.eq(Dl.ListingProfit("201:0", 1, 1, ctxOf({}, {}), S()), nil, "vendor price unknown")
end)

T.test("a listing that is both below market and below vendor is typed by the higher profit", function()
  -- C: market 1000, vendor 900, stack 1. deposit = floor(900*1*4*1*0.025) = 90.
  -- at 500: market = 950 - 500 - 90 = 360; vendor = 900 - 500 = 400. Vendor wins.
  local ctx = ctxOf({ ["300:0"] = { v = 1000, conf = 0.8 } }, { [300] = { n = "C", v = 900, st = 1 } })
  local d = Dl.ListingProfit("300:0", 1, 500, ctx, S())
  T.eq(d.type, "vendor") T.eq(d.profit, 400)
  -- D: market 2000, vendor 900. at 800: market = 1900 - 800 - 90 = 1010; vendor = 100. Market wins.
  ctx = ctxOf({ ["301:0"] = { v = 2000, conf = 0.8 } }, { [301] = { n = "D", v = 900, st = 1 } })
  d = Dl.ListingProfit("301:0", 1, 800, ctx, S())
  T.eq(d.type, "market") T.eq(d.profit, 1010)
  local found = Dl.Find(snap("301:0", "1|800||Bob"), ctx, S(), "Me")
  T.eq(table.getn(found), 1, "listed once")
end)

-- Reagent R (market 100) makes P (market 1000, no vendor price): 2 R -> 1 P costs 200, profit 950 - 200 = 750.
local function matsCtx(recipes)
  return ctxOf({ ["400:0"] = { v = 100, conf = 0.8 }, ["500:0"] = { v = 1000, conf = 0.8 } }, {}, recipes)
end
local function recipeOf(name, n) return { name = name, item = "500:0", reagents = { { item = "400:0", count = n } } } end

T.test("cheap materials: profit is the gain per craft times the crafts covered", function()
  local ctx = matsCtx({ Cloak = recipeOf("Cloak", 2) })
  -- 10 R at 700 = 70 each. New cost 2*70 = 140, profit 810; old 750; gain 60 per craft.
  -- crafts = floor(10/2) = 5, so 300. (belowMarketPct 60 keeps the market rule out of it.)
  local d = Dl.ListingProfit("400:0", 10, 700, ctx, S({ belowMarketPct = 60 }))
  T.eq(d.type, "mats") T.eq(d.profit, 300) T.eq(d.recipe, "Cloak")
  -- 11 at 770 = 70 each: crafts floor(11/2) = 5, still 300.
  T.eq(Dl.ListingProfit("400:0", 11, 770, ctx, S({ belowMarketPct = 60 })).profit, 300)
  T.eq(ctx.override, nil, "the what-if leaves the context clean")
end)

T.test("cheap materials: with two recipes the larger profit wins", function()
  -- 4-reagent recipe: gain 4*30 = 120, crafts floor(10/4) = 2, so 240 < 300 from the 2-reagent one.
  for _, order in ipairs({ 1, 2 }) do
    local recipes = order == 1 and { A = recipeOf("Cloak", 2), B = recipeOf("Robe", 4) }
                                or { A = recipeOf("Robe", 4), B = recipeOf("Cloak", 2) }
    local d = Dl.ListingProfit("400:0", 10, 700, matsCtx(recipes), S({ belowMarketPct = 60 }))
    T.eq(d.recipe, "Cloak") T.eq(d.profit, 300)
  end
end)

T.test("cheap materials do not trigger above matPct or below the minimum profit", function()
  local ctx = matsCtx({ Cloak = recipeOf("Cloak", 2) })
  -- 86 each is 86% > 85%.
  T.eq(Dl.ListingProfit("400:0", 10, 860, ctx, S({ belowMarketPct = 60 })), nil)
  -- exactly 85 each: gain 2*15 = 30 per craft x 5 = 150 profit.
  T.eq(Dl.ListingProfit("400:0", 10, 850, ctx, S({ belowMarketPct = 60 })).profit, 150)
  T.eq(Dl.ListingProfit("400:0", 10, 850, ctx, S({ belowMarketPct = 60, minProfit = 151 })), nil)
  -- fewer than one craft's worth of reagent
  T.eq(Dl.ListingProfit("400:0", 1, 50, ctx, S({ belowMarketPct = 60, market = false })), nil)
end)

T.test("your own listings are excluded, switched-off types are excluded, results sort by profit", function()
  local ctx = ctxOf({ ["200:0"] = {}, ["201:0"] = {} }, { [200] = { n = "B", v = 500 }, [201] = { n = "E", v = 900 } })
  local sn = { rows = { ["200:0"] = { "1|400||Me", "1|450||Bob" }, ["201:0"] = { "1|500||Al", "1|800||Cy" } } }
  local r = Dl.Find(sn, ctx, S(), "Me")
  -- 201 at 500 = 400 profit; 201 at 800 = 100; 200 at 450 = 50; 200 at 400 by Me is dropped.
  T.eq(table.getn(r), 3)
  T.eq(r[1].profit, 400) T.eq(r[2].profit, 100) T.eq(r[3].profit, 50)
  T.eq(r[1].owner, "Al") T.eq(r[3].key, "200:0")
  T.eq(table.getn(Dl.Find(sn, ctx, S({ vendor = false }), "Me")), 0, "vendor off")
end)
