local St = TaxTheFools.Stock
local DAY = 86400
local NOW = 100 * DAY
local items = { [100] = { n = "Linen Cloth" }, [200] = { n = "Bolt of Silk" }, [300] = { n = "Aardvark" } }
local K1, K2, K3 = "100:0", "200:0", "300:0"
local market = { [K1] = { v = 50 }, [K2] = { v = 400 } }

T.test("repostDays default", function() T.eq(TaxTheFools.Data.DEFAULTS.settings.sell.repostDays, 7) end)

T.test("Repost lists expired and cancelled inside the window, sorted by name", function()
  local c = { sales = {
    { key = K1, outcome = "expired", at = NOW - DAY },
    { key = K2, outcome = "cancelled", at = NOW - 6 * DAY },
    { key = K3, outcome = "sold", at = NOW - DAY },
  } }
  local r = St.Repost(c, { [K1] = 5, [K2] = 2, [K3] = 9 }, items, market, 7, NOW)
  T.eq(table.getn(r), 2)
  T.eq(r[1].name, "Bolt of Silk") T.eq(r[1].outcome, "cancelled") T.eq(r[1].have, 2) T.eq(r[1].suggest, 400)
  T.eq(r[2].name, "Linen Cloth") T.eq(r[2].outcome, "expired") T.eq(r[2].suggest, 50)
end)

T.test("Repost drops results outside the window and keys not in bags (sold or moved out)", function()
  local c = { sales = {
    { key = K1, outcome = "expired", at = NOW - 8 * DAY },
    { key = K2, outcome = "expired", at = NOW - DAY },
    { key = K3, outcome = "expired", at = NOW - DAY },
    { outcome = "expired", at = NOW - DAY, name = "Unknown" },
  } }
  local r = St.Repost(c, { [K1] = 5, [K3] = 0 }, items, market, 7, NOW)
  T.eq(table.getn(r), 0)
  r = St.Repost(c, { [K1] = 5 }, items, market, 9, NOW)
  T.eq(table.getn(r), 1, "a longer window brings K1 back")
end)

T.test("Repost takes the last stack and per-unit price from the newest posting, done or not", function()
  local c = { sales = { { key = K1, outcome = "expired", at = NOW - DAY } },
    postings = {
      { key = K1, stack = 10, buyout = 1000, at = NOW - 5 * DAY, done = "expired" },
      { key = K1, stack = 20, buyout = 1500, at = NOW - 2 * DAY, done = "expired" },
      { key = K1, stack = 5, buyout = 900, at = NOW - 4 * DAY },
    } }
  local r = St.Repost(c, { [K1] = 30 }, items, nil, 7, NOW)
  T.eq(r[1].lastStack, 20) T.eq(r[1].lastBuyout, 75) T.eq(r[1].suggest, nil)
  T.eq(r[1].lastAt, NOW - DAY)
  c.postings = nil
  r = St.Repost(c, { [K1] = 30 }, items, market, 7, NOW)
  T.eq(r[1].lastStack, nil) T.eq(r[1].lastBuyout, nil)
end)

T.test("Repost uses the newest expired/cancelled result per key", function()
  local c = { sales = { { key = K1, outcome = "expired", at = NOW - 3 * DAY }, { key = K1, outcome = "cancelled", at = NOW - DAY } } }
  local r = St.Repost(c, { [K1] = 1 }, items, market, 7, NOW)
  T.eq(table.getn(r), 1) T.eq(r[1].outcome, "cancelled")
end)

local chars = {
  Anna = { bags = { [K1] = 10, [K2] = 1 }, bank = { [K1] = 5 },
    postings = { { key = K1, stack = 20 }, { key = K1, stack = 20, done = "sold" }, { key = K2, stack = 2 } } },
  Bob = { bags = { [K1] = 3 }, bank = { [K3] = 4 }, postings = { { key = K1, stack = 7, done = "expired" } } },
}

T.test("Rows sums bags, bank and open postings across characters", function()
  local rows = St.Rows(chars, market, {}, nil, items)
  local by = {}
  for _, r in ipairs(rows) do by[r.key] = r end
  T.eq(by[K1].bags, 13) T.eq(by[K1].bank, 5) T.eq(by[K1].onAH, 20, "done postings excluded") T.eq(by[K1].total, 38)
  T.eq(by[K2].onAH, 2) T.eq(by[K2].total, 3)
  T.eq(by[K3].total, 4) T.eq(by[K1].name, "Linen Cloth")
  T.eq(by[K1].unit, 50) T.eq(by[K1].value, 1900)
end)

T.test("Rows sorts by value with unvalued last, and keeps the per-character breakdown", function()
  local rows = St.Rows(chars, market, {}, nil, items)
  T.eq(table.getn(rows), 3)
  T.eq(rows[1].key, K1) T.eq(rows[2].key, K2) T.eq(rows[3].key, K3)
  T.eq(rows[3].unit, nil) T.eq(rows[3].value, nil)
  local pc = rows[1].perChar
  T.eq(table.getn(pc), 2)
  T.eq(pc[1].name, "Anna") T.eq(pc[1].bags, 10) T.eq(pc[1].bank, 5) T.eq(pc[1].onAH, 20)
  T.eq(pc[2].name, "Bob") T.eq(pc[2].bags, 3) T.eq(pc[2].bank, 0) T.eq(pc[2].onAH, 0)
end)

T.test("Rows passes rate and trend through", function()
  local rows = St.Rows(chars, market, { [K1] = { rate = 0.5 } }, function(k) if k == K1 then return 12 end end, items)
  T.eq(rows[1].rate, 0.5) T.eq(rows[1].trend, 12)
  T.eq(rows[2].rate, nil) T.eq(rows[2].trend, nil)
end)

T.test("Rows with no characters is empty", function() T.eq(table.getn(St.Rows({}, market, {}, nil, items)), 0) end)

T.test("Total counts keys and units, and only valued rows add value", function()
  local t = St.Total(St.Rows(chars, market, {}, nil, items))
  T.eq(t.items, 3) T.eq(t.units, 45) T.eq(t.value, 38 * 50 + 3 * 400)
  local z = St.Total({}) T.eq(z.items, 0) T.eq(z.units, 0) T.eq(z.value, 0)
end)

T.test("a zero count in bags or bank makes no row", function()
  local rows = TaxTheFools.Stock.Rows({ A = { bags = { ["1:0"] = 0 }, bank = { ["2:0"] = 0 } } }, {}, {}, nil, {})
  T.eq(table.getn(rows), 0)
end)
