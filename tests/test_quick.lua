local Q = TaxTheFools.Quick
local K1, K2 = "100:0", "200:0"
local function slot(bag, sl, key, name, count)
  return { bag = bag, slot = sl, key = key, id = tonumber(string.sub(key, 1, 3)), name = name, count = count, tex = "t", quality = 1 }
end
local P = { [K1] = { buyout = 50, bid = 45, source = "undercut", atFloor = true }, [K2] = { buyout = 400, bid = 360, source = "market" } }

T.test("Quick.Rows gives one row per slot, same unit for one key", function()
  local r = Q.Rows({ slot(0, 1, K1, "Linen", 5), slot(0, 2, K1, "Linen", 5) }, P)
  T.eq(table.getn(r), 2)
  T.eq(r[1].unit, 50) T.eq(r[2].unit, 50) T.eq(r[1].bid, 45) T.eq(r[1].source, "undercut")
  T.ok(r[1].atFloor) T.eq(r[1].status, nil) T.eq(r[1].count, 5) T.eq(r[1].tex, "t")
end)

T.test("Quick.Rows sorts by name, bigger stack first, ties keep bag and slot order", function()
  local r = Q.Rows({ slot(0, 1, K1, "Linen", 5), slot(1, 1, K2, "Bolt", 1), slot(0, 2, K1, "Linen", 20),
    slot(0, 3, K1, "Linen", 5), slot(0, 4, K1, "Linen", 5) }, P)
  T.eq(r[1].name, "Bolt") T.eq(r[2].count, 20)
  T.eq(r[3].slot, 1) T.eq(r[4].slot, 3) T.eq(r[5].slot, 4)
end)

T.test("Quick.Rows statuses", function()
  local pr = { [K1] = {}, [K2] = { buyout = 9, bid = 8, source = "vendor" } }
  local r = Q.Rows({ slot(0, 1, K1, "A", 1), slot(0, 2, K2, "B", 1), slot(0, 3, "300:0", "C", 1) }, pr)
  T.eq(r[1].status, "noprice") T.eq(r[2].status, "vendor") T.eq(r[3].status, "notscanned")
  T.eq(r[3].unit, nil)
end)

T.test("Quick.Next skips done rows and non-postable, respects includeVendor", function()
  local rows = { { status = "noprice" }, {}, { done = "posted" }, { status = "vendor" }, { done = "failed" },
    { done = "skipped" }, { status = "notscanned" }, {} }
  T.eq(Q.Next(rows, 0, false), 2)
  T.eq(Q.Next(rows, 2, false), 8)
  T.eq(Q.Next(rows, 2, true), 4)
  T.eq(Q.Next(rows, 4, true), 8)
  T.eq(Q.Next(rows, 8, true), nil)
  rows[4].done = "skipped"
  T.eq(Q.Next(rows, 2, true), 8)
end)

T.test("vendor and quickVendor settings defaults", function()
  local d = TaxTheFools.Data.DEFAULTS.settings.sell
  T.eq(d.vendorMult, 3) T.eq(d.quickVendor, false)
end)
