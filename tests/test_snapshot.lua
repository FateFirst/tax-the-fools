local Scan, DB, I = TaxTheFools.Scan, TaxTheFools.DB, TaxTheFools.Items

-- Advance the clock half a second at a time, answering every query the scan sends.
local function pump()
  for _ = 1, 200 do
    WoW.clock = WoW.clock + 0.5
    Scan.Tick(WoW.clock)
    if WoW.ah.pending then
      WoW.ahRespond()
      Scan.OnListUpdate(WoW.clock)
    end
    if not Scan.job then return end
  end
end

local function list(id, name, count, buyout, owner, minBid)
  table.insert(WoW.ah.listings, { id = id, name = name, count = count, buyout = buyout, owner = owner,
    minBid = minBid or 100 })
end

local function rows(key) return DB.Realm().snapshot.rows[key] end

T.test("a full scan saves its buyout listings as the snapshot", function()
  list(14047, "Runecloth", 20, 8001, "Sel", 7000)
  list(14047, "Runecloth", 5, 0, "Bidonly", 900)             -- no buyout: not a deal, not kept
  list(4306, "Silk Cloth", 20, 6000)                        -- owner not sent yet
  T.ok(Scan.StartFull(WoW.clock))
  pump()
  local snap = DB.Realm().snapshot
  T.eq(snap.at, WoW.now) T.eq(snap.day, 20375)
  T.eq(table.getn(rows("14047:0")), 1)
  T.eq(rows("14047:0")[1], "20|8001|7000|Sel")
  T.eq(rows("4306:0")[1], "20|6000|100|")
end)

T.test("a snapshot row reads back as count, buyout, minimum bid and owner", function()
  local count, buyout, minBid, owner = Scan.ParseSnapRow("20|8001|7000|Sel")
  T.eq(count, 20) T.eq(buyout, 8001) T.eq(minBid, 7000) T.eq(owner, "Sel")
  count, buyout, minBid, owner = Scan.ParseSnapRow("1|130|100|")
  T.eq(count, 1) T.eq(owner, nil, "unknown owner")
  T.eq(Scan.ParseSnapRow("rubbish"), nil)
end)

T.test("the stored format stays small", function()
  local row = Scan.SnapRow({ qty = 20, buyout = 8001, minBid = 7000, owner = "Sellername" })
  T.eq(row, "20|8001|7000|Sellername")
  T.eq(string.len(row), 23, "2 + 1 + 4 + 1 + 4 + 1 + 10")
  -- 8.5k listings of about 25 bytes: 8500 x 25 = 212500 bytes, about 200 KB (spec section 3).
  T.ok(8500 * string.len(row) < 250000)
end)

T.test("a watchlist scan replaces the rows of what it saw and leaves the rest", function()
  list(14047, "Runecloth", 20, 8001, "A")
  list(4306, "Silk Cloth", 20, 6000, "B")
  Scan.StartFull(WoW.clock) pump()
  I.Remember(4306, "Silk Cloth")
  DB.Realm().watch["4306:0"] = true
  WoW.ah.listings = {}
  list(14047, "Runecloth", 20, 7000, "C")                    -- not watched: the watch scan never asks
  list(4306, "Silk Cloth", 10, 2500, "D")
  list(4306, "Silk Cloth", 20, 5900, "E")
  T.ok(Scan.StartWatch(WoW.clock))
  pump()
  T.eq(table.getn(rows("4306:0")), 2, "both new silk listings, the old one gone")
  T.eq(rows("4306:0")[1], "10|2500|100|D")
  T.eq(rows("14047:0")[1], "20|8001|100|A", "runecloth untouched")
end)

T.test("a watched item that has sold out loses its rows", function()
  list(4306, "Silk Cloth", 20, 6000, "B")
  Scan.StartFull(WoW.clock) pump()
  I.Remember(4306, "Silk Cloth")
  DB.Realm().watch["4306:0"] = true
  WoW.ah.listings = {}
  Scan.StartWatch(WoW.clock) pump()
  T.eq(rows("4306:0"), nil)
end)

T.test("a search never touches the snapshot", function()
  list(14047, "Runecloth", 20, 8001, "A")
  Scan.StartFull(WoW.clock) pump()
  list(14047, "Runecloth", 20, 100, "Cheap")
  T.ok(Scan.Browse("Rune", 0, WoW.clock))
  pump()
  T.eq(table.getn(Scan.lastRows), 2, "the search saw both")
  T.eq(table.getn(rows("14047:0")), 1, "the snapshot did not change")
end)

T.test("a paused and resumed full scan keeps buyouts and minimum bids", function()
  for i = 1, 60 do list(14047, "Runecloth", 20, 8000 + i, "S", 7000) end
  Scan.StartFull(WoW.clock)
  WoW.clock = WoW.clock + 1 Scan.Tick(WoW.clock) WoW.ahRespond() Scan.OnListUpdate(WoW.clock)
  Scan.Pause("closed")
  T.eq(DB.Realm().scan.resume.rows[1], "14047:0|400.05|20|S|8001|7000", "8001 / 20 = 400.05")
  T.ok(Scan.Resume(WoW.clock))
  pump()
  T.eq(table.getn(rows("14047:0")), 60)
  T.eq(rows("14047:0")[1], "20|8001|7000|S")
end)

T.test("a scan paused by 0.2.0 still resumes, its buyout worked out from the unit price", function()
  local l = Scan.ParseSaved("14047:0|400.05|20|S")
  T.eq(l.buyout, 8001, "400.05 x 20 = 8001") T.eq(l.minBid, 0) T.eq(l.owner, "S")
  l = Scan.ParseSaved("14047:0||5|")
  T.eq(l.buyout, 0, "no buyout") T.eq(l.owner, nil)
end)

T.test("a bought or vanished listing leaves the snapshot", function()
  DB.Realm().snapshot = { at = WoW.now, day = 20375, rows = { ["14047:0"] = { "20|8001|100|A", "20|8001|100|B" } } }
  T.eq(Scan.SnapshotRemove({ key = "14047:0", count = 20, buyout = 8001, owner = "B" }), true)
  T.eq(table.getn(rows("14047:0")), 1)
  T.eq(rows("14047:0")[1], "20|8001|100|A", "B's listing went, A's stayed")
  T.eq(Scan.SnapshotRemove({ key = "14047:0", count = 20, buyout = 9999 }), false, "different buyout")
  T.eq(Scan.SnapshotRemove({ key = "14047:0", count = 20, buyout = 8001 }), true, "owner unknown on our side")
  T.eq(rows("14047:0"), nil, "an empty item is dropped")
end)

T.test("the snapshot's age is counted in whole days", function()
  T.eq(Scan.SnapshotAge(20375), nil, "no snapshot yet")
  DB.Realm().snapshot = { at = WoW.now - 3 * 86400, day = 20372, rows = {} }
  T.eq(Scan.SnapshotAge(20375), 3, "20375 - 20372")
end)
