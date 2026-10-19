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

-- ---------- the bag scan ----------

local Scan, DB = TaxTheFools.Scan, TaxTheFools.DB

local function seedBags(bags)
  WoW.items[14047] = { name = "Runecloth", stack = 20, quality = 1, tex = "rune" }
  WoW.items[2589] = { name = "Linen Cloth", stack = 20, quality = 1, tex = "linen" }
  WoW.items[14156] = { name = "Runecloth Bag", stack = 1, quality = 1, tex = "bag" }
  WoW.bags[0] = bags or { { id = 14047, name = "Runecloth", count = 20 }, { id = 14047, name = "Runecloth", count = 7 },
    { id = 2589, name = "Linen Cloth", count = 5 }, {} }
  WoW.bags[1], WoW.bags[2], WoW.bags[3], WoW.bags[4] = nil, nil, nil, nil
end

local function list(id, name, n, base, count)
  for i = 1, n do
    table.insert(WoW.ah.listings, { id = id, name = name, count = count or 20, buyout = (base or 8000) + i, owner = "S" .. i })
  end
end

local function pump(limit)
  for i = 1, limit or 200 do
    WoW.clock = WoW.clock + 0.5
    Scan.Tick(WoW.clock)
    if WoW.ah.pending then
      WoW.ahRespond()
      Scan.OnListUpdate(WoW.clock)
    end
    if not Scan.job then return i end
  end
end

local function find(rows, id)
  for _, r in ipairs(rows) do if r.id == id then return r end end
end

T.test("Quick.Scan sends one query per distinct item and prices by key, ignoring Runecloth Bag", function()
  seedBags()
  list(14047, "Runecloth", 3, 8000)
  list(14156, "Runecloth Bag", 3, 20, 1)
  list(2589, "Linen Cloth", 3, 200)
  T.eq(Q.state, "idle")
  T.ok(Q.Scan(WoW.clock))
  T.eq(Q.state, "scanning")
  pump()
  T.eq(T.count("QueryAuctionItems [Runecloth] [] [] 0"), 1)
  T.eq(T.count("QueryAuctionItems [Linen Cloth] [] [] 0"), 1)
  T.eq(Scan.lastFinished.kind, "quick")
  T.eq(Q.state, "ready")
  T.eq(table.getn(Q.rows), 3)
  local rune = find(Q.rows, 14047)
  T.eq(rune.status, nil)
  T.ok(rune.unit >= 300 and rune.unit <= 401, "priced from Runecloth listings only, got " .. tostring(rune.unit))
  T.eq(rune.source, "undercut")
  T.ok(find(Q.rows, 2589).unit < 11, "linen priced from its own listings")
  T.eq(table.getn(Q.listings["14047:0"]), 3)
  T.ok(Q.scannedAt)
end)

T.test("Quick.Scan records history like a watch scan", function()
  seedBags()
  list(14047, "Runecloth", 3, 8000)
  Q.Scan(WoW.clock) pump()
  T.eq(DB.Realm().history["14047:0"].days[20375].src, "quick")
  T.eq(DB.Realm().scan.resume, nil)
end)

T.test("Quick.Scan with a busy scanner is refused", function()
  seedBags()
  Scan.StartFull(WoW.clock)
  local ok, why = Q.Scan(WoW.clock)
  T.eq(ok, false) T.eq(why, "busy") T.eq(Q.state, "idle")
end)

T.test("Quick.Scan with nothing sellable is refused as empty", function()
  seedBags({ {}, {} })
  local ok, why = Q.Scan(WoW.clock)
  T.eq(ok, false) T.eq(why, "empty") T.eq(Q.state, "idle")
end)

T.test("a full scan finishing does not change Quick.rows", function()
  seedBags()
  list(14047, "Runecloth", 3, 8000)
  Q.Scan(WoW.clock) pump()
  local rows = Q.rows
  local n = table.getn(rows)
  WoW.ah.listings = {}
  list(14047, "Runecloth", 3, 100)
  Scan.StartFull(WoW.clock) pump()
  T.ok(Q.rows == rows, "same table")
  T.eq(table.getn(Q.rows), n) T.eq(Q.state, "ready")
  T.ok(find(Q.rows, 14047).unit > 300)
end)

T.test("a slot added after the scan started shows notscanned", function()
  seedBags()
  list(14047, "Runecloth", 3, 8000)
  Q.Scan(WoW.clock)
  WoW.items[4306] = { name = "Silk Cloth", stack = 20, quality = 1, tex = "silk" }
  WoW.bags[0][4] = { id = 4306, name = "Silk Cloth", count = 3 }
  pump()
  T.eq(find(Q.rows, 4306).status, "notscanned")
  T.eq(find(Q.rows, 14047).status, nil)
end)

T.test("a paused scan stays scanning, resumes and finishes; a discarded one goes idle", function()
  seedBags()
  list(14047, "Runecloth", 3, 8000)
  Q.Scan(WoW.clock)
  Scan.Pause()
  T.eq(Q.state, "scanning")
  T.ok(Scan.Resume(WoW.clock))
  pump()
  T.eq(Q.state, "ready")
  T.eq(table.getn(Q.listings["14047:0"]), 3)
  Q.ResetState()
  Q.Scan(WoW.clock)
  Scan.Pause()
  Scan.Discard()
  T.eq(Q.state, "idle")
end)

T.test("a paused quick scan replaced by another paused scan returns Quick to idle", function()
  seedBags()
  list(14047, "Runecloth", 3, 8000)
  Q.Scan(WoW.clock)
  Scan.Pause()
  T.eq(Q.state, "scanning")
  DB.Realm().scan.resume = nil
  T.ok(Scan.Start("watch", { { name = "Runecloth" } }, WoW.clock))
  Scan.Pause()
  T.eq(DB.Realm().scan.resume.kind, "watch")
  T.eq(Q.state, "idle")
end)

T.test("Quick.Reprice rebuilds the rows from the kept listings and the current settings", function()
  seedBags({ { id = 2589, name = "Linen Cloth", count = 5 } })
  Q.Scan(WoW.clock) pump()
  local r = find(Q.rows, 2589)
  T.eq(r.status, "noprice")
  WoW.items[2589].vendor = nil
  TaxTheFoolsDB.items[2589] = { n = "Linen Cloth", v = 10, st = 20 }
  Q.Reprice()
  r = find(Q.rows, 2589)
  T.eq(r.source, "vendor") T.eq(r.unit, 30) T.eq(r.status, "vendor")
  DB.S().sell.vendorMult = 5
  Q.Reprice()
  T.eq(find(Q.rows, 2589).unit, 50)
end)

T.test("Quick.OnChange fires as the state changes", function()
  seedBags()
  list(14047, "Runecloth", 3, 8000)
  local seen = {}
  Q.OnChange(function() table.insert(seen, Q.state) end)
  Q.Scan(WoW.clock) pump()
  T.eq(seen[1], "scanning")
  T.eq(seen[table.getn(seen)], "ready")
end)
