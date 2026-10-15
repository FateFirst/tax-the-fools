local Tip, DB, I = TaxTheFools.Tooltip, TaxTheFools.DB, TaxTheFools.Items

local function seed()
  I.Remember(14047, "Runecloth", 1, 20)
  TaxTheFoolsDB.items[14047].v = 100
  DB.Realm().market["14047:0"] = { v = 400, conf = 0.8, low = 380, lowDay = 20374, seen = 6 }
end

T.test("lines show market with confidence, the latest low and the vendor price", function()
  seed()
  local lines = Tip.Lines("14047:0", 1, WoW.now)
  T.eq(lines[1][1], "Market")
  T.ok(string.find(lines[1][2], "4s", 1, true), lines[1][2])
  T.ok(string.find(lines[1][2], "high", 1, true), "confidence named")
  T.eq(lines[2][1], "Low now")
  T.ok(string.find(lines[2][2], "1d ago", 1, true), lines[2][2])
  T.eq(lines[3][1], "Vendor")
end)

T.test("shift multiplies by the stack", function()
  seed()
  WoW.shift = true
  local lines = Tip.Lines("14047:0", 20, WoW.now)
  T.eq(lines[1][1], "Market x20")
  T.ok(string.find(lines[1][2], "80s", 1, true), lines[1][2])
end)

T.test("an item with no prices says so rather than failing", function()
  local lines = Tip.Lines("5000:0", 1, WoW.now)
  T.eq(lines[1][1], "Market")
  T.ok(string.find(lines[1][2], "no data", 1, true))
  T.eq(table.getn(lines), 1)
end)

T.test("lines switched off in options are left out", function()
  seed()
  DB.S().tooltip.vendor = false
  DB.S().tooltip.low = false
  T.eq(table.getn(Tip.Lines("14047:0", 1, WoW.now)), 1)
end)

T.test("hovering a bag item adds the prices and keeps the original return", function()
  seed()
  WoW.bags[0] = { { id = 14047, name = "Runecloth", count = 20 } }
  Tip.Hook()
  Tip.Hook()                                  -- hooking twice must not add lines twice
  local r = GameTooltip:SetBagItem(0, 1)
  T.eq(r, "orig-bag")
  T.eq(GameTooltip.lines[1][1], "Market")
  T.eq(table.getn(GameTooltip.lines), 3)
end)

T.test("hovering an item teaches the cache its name", function()
  WoW.items[4306] = { name = "Silk Cloth", stack = 20 }
  Tip.Hook()
  GameTooltip:SetHyperlink("item:4306:0:0:0")
  T.eq(TaxTheFoolsDB.items[4306].n, "Silk Cloth")
end)

local function sales(sold, expired)
  local c = DB.Char()
  c.sales = {}
  for _ = 1, sold do table.insert(c.sales, { key = "14047:0", outcome = "sold", money = 100, qty = 1, unit = 100, at = time() - 86400 }) end
  for _ = 1, expired do table.insert(c.sales, { key = "14047:0", outcome = "expired", at = time() - 86400 }) end
end

T.test("the Sells line shows the rate and the number of results", function()
  seed()
  sales(13, 5)
  local lines = Tip.Lines("14047:0", 1, WoW.now)
  local found
  for _, l in ipairs(lines) do if l[1] == "Sells" then found = l[2] end end
  T.eq(found, "72% (18)")
end)

T.test("the Sells line is left out with no results or when switched off", function()
  seed()
  sales(0, 0)
  for _, l in ipairs(Tip.Lines("14047:0", 1, WoW.now)) do T.ok(l[1] ~= "Sells") end
  sales(3, 1)
  DB.S().sales.tooltip = false
  for _, l in ipairs(Tip.Lines("14047:0", 1, WoW.now)) do T.ok(l[1] ~= "Sells") end
  DB.S().sales.tooltip = true
end)

T.test("the Sells line follows the sales window", function()
  seed()
  sales(3, 1)
  DB.Char().sales[1].at = time() - 20 * 86400
  DB.S().sales.days = 7
  local n
  for _, l in ipairs(Tip.Lines("14047:0", 1, WoW.now)) do if l[1] == "Sells" then n = l[2] end end
  T.eq(n, "67% (3)")
  DB.S().sales.days = 30
end)
