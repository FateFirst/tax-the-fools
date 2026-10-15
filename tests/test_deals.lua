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

-- ---------- undersupplied (phase 4) ----------
-- One key, 100:0. Defaults: rate >= 0.5, n >= 3, listings today <= 33% of the median, held >= 1.
local function U(o)
  local i = { stats = { rate = 0.6, n = 4 }, count = 1, median = 6, held = 5, market = 1000, lowest = 900 }
  for k, v in pairs(o or {}) do i[k] = v end
  return i
end
local function US(o)
  local s = { under = true, underPct = 33, premiumPct = 110 }
  for k, v in pairs(o or {}) do s[k] = v end
  return s
end

T.test("undersupplied: suggest is max(market, lowest) x premium, profit is held x suggest x 0.95", function()
  -- market 1000 beats lowest 900: suggest = floor(1000*110/100) = 1100; profit = 5*1100*0.95 = 5225.
  local d = Dl.Under("100:0", U(), US())
  T.eq(d.type, "under") T.eq(d.key, "100:0") T.eq(d.held, 5) T.eq(d.suggest, 1100)
  T.near(d.profit, 5225, 0.001)
  -- lowest 1500 beats market 1000: suggest = floor(1500*1.1) = 1650; held 3: 3*1650*0.95 = 4702.5.
  d = Dl.Under("100:0", U({ lowest = 1500, held = 3 }), US())
  T.eq(d.suggest, 1650) T.near(d.profit, 4702.5, 0.001)
  -- floor: market 1001 * 1.10 = 1101.1 -> 1101; held 2: 2*1101*0.95 = 2091.9.
  d = Dl.Under("100:0", U({ market = 1001, lowest = false, held = 2 }), US())
  T.eq(d.suggest, 1101) T.near(d.profit, 2091.9, 0.001)
  -- premium 125 on market 1000 = 1250; nobody listed (lowest nil) still works from the market alone.
  T.eq(Dl.Under("100:0", U({ lowest = false }), US({ premiumPct = 125 })).suggest, 1250)
end)

T.test("undersupplied: the sell rate must be at least 0.5", function()
  T.ok(Dl.Under("100:0", U({ stats = { rate = 0.5, n = 4 } }), US()), "exactly 0.5 counts")
  T.eq(Dl.Under("100:0", U({ stats = { rate = 0.49, n = 4 } }), US()), nil)
  T.eq(Dl.Under("100:0", U({ stats = { n = 0 } }), US()), nil, "no rate at all")
  T.eq(Dl.Under("100:0", U({ stats = false }), US()), nil)
end)

T.test("undersupplied: at least 3 results", function()
  T.ok(Dl.Under("100:0", U({ stats = { rate = 1, n = 3 } }), US()), "exactly 3 counts")
  T.eq(Dl.Under("100:0", U({ stats = { rate = 1, n = 2 } }), US()), nil)
end)

T.test("undersupplied: listings today at most underPct of the median, compared exactly", function()
  -- 2 of 4 is 50%: 2*100 <= 50*4 holds, 3 of 4 does not.
  T.ok(Dl.Under("100:0", U({ count = 2, median = 4 }), US({ underPct = 50 })), "exactly at the limit")
  T.eq(Dl.Under("100:0", U({ count = 3, median = 4 }), US({ underPct = 50 })), nil)
  -- default 33%: 2 of 6 = 33.3% is over, 1 of 6 is under, 0 listed is under.
  T.eq(Dl.Under("100:0", U({ count = 2, median = 6 }), US()), nil)
  T.ok(Dl.Under("100:0", U({ count = 0, median = 6 }), US()))
  T.eq(Dl.Under("100:0", U({ median = false }), US()), nil, "no median, no deal")
  T.eq(Dl.Under("100:0", U({ median = 0 }), US()), nil)
end)

T.test("undersupplied: you must hold at least one, and the switch must be on", function()
  T.ok(Dl.Under("100:0", U({ held = 1 }), US()))
  T.eq(Dl.Under("100:0", U({ held = 0 }), US()), nil)
  T.eq(Dl.Under("100:0", U({ held = false }), US()), nil)
  T.eq(Dl.Under("100:0", U(), US({ under = false })), nil)
  T.eq(Dl.Under("100:0", U({ market = false, lowest = false }), US()), nil, "no price to suggest from")
end)

T.test("FindUnder walks the holdings, reads the snapshot count and lowest, sorts by profit", function()
  -- 100:0 held 5, 2 listings (lowest 800/2 = 400 each, 900 -> 900); median 8 so 2 of 8 = 25%.
  -- 200:0 held 1, no listings, median 3; market 500: suggest 550, profit 522.5.
  -- 300:0 held 4 but sells badly; 400:0 held 2 but 5 of 6 listed.
  local sn = { rows = { ["100:0"] = { "2|800|0|A", "1|900|0|B" },
                        ["400:0"] = { "1|10|0|A", "1|10|0|A", "1|10|0|A", "1|10|0|A", "1|10|0|A" } } }
  local ctx = ctxOf({ ["100:0"] = { v = 1000 }, ["200:0"] = { v = 500 }, ["300:0"] = { v = 500 }, ["400:0"] = { v = 500 } })
  local src = {
    held = { ["100:0"] = 5, ["200:0"] = 1, ["300:0"] = 4, ["400:0"] = 2 },
    stats = function(key)
      if key == "300:0" then return { rate = 0.2, n = 9 } end
      return { rate = 0.8, n = 5 }
    end,
    median = function(key)
      if key == "100:0" then return 8 elseif key == "200:0" then return 3 end
      return 6
    end,
  }
  local r = Dl.FindUnder(sn, ctx, US(), src)
  -- 100:0: lowest unit = 400, market 1000 wins: suggest 1100, profit 5*1100*0.95 = 5225.
  T.eq(table.getn(r), 2)
  T.eq(r[1].key, "100:0") T.near(r[1].profit, 5225, 0.001) T.eq(r[1].suggest, 1100)
  T.eq(r[2].key, "200:0") T.near(r[2].profit, 522.5, 0.001)
  T.eq(table.getn(Dl.FindUnder(sn, ctx, US({ under = false }), src)), 0)
  T.eq(table.getn(Dl.FindUnder(nil, ctx, US(), src)), 0, "no snapshot")
end)

-- ---------- recipe deals (phase 5a) ----------
-- Pattern 600 teaches Robe (product 500, skill 40): value 1000*0.95 = 950, material 300 costs 200,
-- so 750 a craft. A listing at 3000 pays back in ceil(3000/750) = 4 crafts.
local function rctx()
  return ctxOf({ ["500:0"] = { v = 1000, conf = 0.8 }, ["300:0"] = { v = 200, conf = 0.8 } }, {})
end
local function rsrc(learnedBy, rank)
  local entry = { name = "Robe", skill = 40, item = "500:0", yieldMin = 1, yieldMax = 1,
                  reagents = { { item = "300:0", name = "Thread", count = 1 } }, pats = { 600 } }
  local recipes = {}
  if learnedBy then recipes.Robe = { item = "500:0" } end
  local chars = { Alt = { professions = { Tailoring = { rank = rank or 50, recipes = recipes } } } }
  return { indexes = { { prof = "Tailoring", index = TaxTheFools.Recipes.PatternIndex({ entry }) } }, chars = chars, skillAhead = 25 }
end
local function RS(o)
  local s = S({ recipe = true, paybackCrafts = 10, minProfit = 0 })
  for k, v in pairs(o or {}) do s[k] = v end
  return s
end
local function rsnap(...)
  return snap("600:0", unpack(arg))
end

T.test("a pattern deal: payback, crafter and the profit arithmetic", function()
  local r = Dl.FindRecipes(rsnap("1|3000|0|Seller"), rctx(), RS(), "Me", rsrc())
  T.eq(table.getn(r), 1)
  local d = r[1]
  T.eq(d.type, "recipe") T.eq(d.key, "600:0") T.eq(d.count, 1) T.eq(d.buyout, 3000) T.eq(d.unit, 3000)
  T.eq(d.crafter, "Alt") T.eq(d.recipe, "Robe") T.eq(d.perCraft, 750) T.eq(d.payback, 4)
  T.eq(d.profit, 750 * 10 - 3000)
end)

T.test("recipe deals: the payback threshold is inclusive", function()
  -- 7500 / 750 = exactly 10 crafts; 7501 is 11.
  T.eq(table.getn(Dl.FindRecipes(rsnap("1|7500|0|X"), rctx(), RS({ minProfit = -1 }), "Me", rsrc())), 1)
  T.eq(table.getn(Dl.FindRecipes(rsnap("1|7501|0|X"), rctx(), RS({ minProfit = -10000 }), "Me", rsrc())), 0)
end)

T.test("recipe deals: minProfit and the switch", function()
  -- profit 4500 at 3000
  T.eq(table.getn(Dl.FindRecipes(rsnap("1|3000|0|X"), rctx(), RS({ minProfit = 4500 }), "Me", rsrc())), 1)
  T.eq(table.getn(Dl.FindRecipes(rsnap("1|3000|0|X"), rctx(), RS({ minProfit = 4501 }), "Me", rsrc())), 0)
  T.eq(table.getn(Dl.FindRecipes(rsnap("1|3000|0|X"), rctx(), RS({ recipe = false }), "Me", rsrc())), 0)
end)

T.test("recipe deals: not your own listing, and only a single pattern", function()
  T.eq(table.getn(Dl.FindRecipes(rsnap("1|3000|0|Me"), rctx(), RS(), "Me", rsrc())), 0)
  T.eq(table.getn(Dl.FindRecipes(rsnap("2|6000|0|X"), rctx(), RS(), "Me", rsrc())), 0)
end)

T.test("recipe deals: a listing that is not a pattern in the index is ignored", function()
  T.eq(table.getn(Dl.FindRecipes(snap("999:0", "1|1|0|X"), rctx(), RS(), "Me", rsrc())), 0)
  T.eq(table.getn(Dl.FindRecipes(rsnap("1|3000|0|X"), rctx(), RS(), "Me", { indexes = {}, chars = {} })), 0)
end)

T.test("recipe deals need a crafter: nobody, one who knows it, or one too low", function()
  T.eq(table.getn(Dl.FindRecipes(rsnap("1|3000|0|X"), rctx(), RS(), "Me", { indexes = rsrc().indexes, chars = {} })), 0)
  -- Review Focus 4: every tailor on the realm already knows it
  T.eq(table.getn(Dl.FindRecipes(rsnap("1|3000|0|X"), rctx(), RS(), "Me", rsrc(true))), 0)
  -- skill 40, rank 10 + 25 ahead = 35 < 40; rank 15 + 25 = 40 is enough
  T.eq(table.getn(Dl.FindRecipes(rsnap("1|3000|0|X"), rctx(), RS(), "Me", rsrc(false, 10))), 0)
  T.eq(table.getn(Dl.FindRecipes(rsnap("1|3000|0|X"), rctx(), RS(), "Me", rsrc(false, 15))), 1)
end)

T.test("recipe deals: no profit per craft means no deal", function()
  local ctx = ctxOf({ ["500:0"] = { v = 100, conf = 0.8 }, ["300:0"] = { v = 200, conf = 0.8 } }, {})
  T.eq(table.getn(Dl.FindRecipes(rsnap("1|1|0|X"), ctx, RS({ minProfit = -10000 }), "Me", rsrc())), 0)
  local unpriced = ctxOf({ ["500:0"] = { v = 1000, conf = 0.8 } }, {})
  T.eq(table.getn(Dl.FindRecipes(rsnap("1|1|0|X"), unpriced, RS(), "Me", rsrc())), 0, "a material with no price")
end)

T.test("recipe deals: a vendor that sells the pattern cheaper beats the listing, unless limited", function()
  local function withVendor(vb, limited)
    local c = rctx()
    c.items[600] = { n = "Pattern: Robe", vb = vb, vbLimited = limited }
    return c
  end
  T.eq(table.getn(Dl.FindRecipes(rsnap("1|3000|0|X"), withVendor(2999), RS(), "Me", rsrc())), 0)
  T.eq(table.getn(Dl.FindRecipes(rsnap("1|3000|0|X"), withVendor(3000), RS(), "Me", rsrc())), 1, "equal is fine")
  T.eq(table.getn(Dl.FindRecipes(rsnap("1|3000|0|X"), withVendor(1000, true), RS(), "Me", rsrc())), 1, "limited stock")
end)

T.test("recipe deals come best profit first", function()
  local r = Dl.FindRecipes(rsnap("1|3000|0|X", "1|2000|0|Y"), rctx(), RS(), "Me", rsrc())
  T.eq(table.getn(r), 2) T.eq(r[1].buyout, 2000) T.eq(r[2].buyout, 3000)
end)
