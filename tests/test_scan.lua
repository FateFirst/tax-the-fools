local Scan, DB, I = TaxTheFools.Scan, TaxTheFools.DB, TaxTheFools.Items

local function fill(n, id, name, base)
  for i = 1, n do
    table.insert(WoW.ah.listings, { id = id or 14047, name = name or "Runecloth", count = 20,
      buyout = (base or 8000) + i, owner = "S" .. math.mod(i, 7) })
  end
end

-- Advance the clock half a second at a time, answering every query the scan sends.
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

-- One step at time t, sharing WoW.clock with pump(); answer=true replies to any query.
local function at(t, answer)
  WoW.clock = t
  Scan.Tick(t)
  if answer and WoW.ah.pending then
    WoW.ahRespond()
    Scan.OnListUpdate(t)
  end
end

local function day(key) return DB.Realm().history[key].days[20375] end

T.test("a full scan pages through everything and records one day row", function()
  fill(120)
  T.ok(Scan.StartFull(WoW.clock))
  pump()
  -- name and levels go as "" (never nil): Ravencraft ignores the query otherwise
  T.ok(T.calledWith("QueryAuctionItems [] [] [] 0"), "page 0")
  T.ok(T.calledWith("QueryAuctionItems [] [] [] 2"), "page 2")
  T.ok(not T.calledWith("QueryAuctionItems [] [] [] 3"), "stops after the last page")
  local r = day("14047:0")
  T.eq(r.n, 120) T.eq(r.qty, 2400) T.eq(r.src, "full")
  T.eq(r.min, 400) T.eq(r.p25, 402) T.eq(r.med, 403) T.eq(r.sellers, 7)
  T.eq(DB.Realm().scan.lastFull, WoW.now)
  T.eq(Scan.lastFinished.pages, 3)
end)

T.test("market values are worked out after the scan, a batch per frame", function()
  fill(10)
  Scan.StartFull(WoW.clock)
  pump()
  Scan.Tick(WoW.clock)
  T.eq(DB.Realm().market["14047:0"].v, day("14047:0").p25)
end)

T.test("nothing is sent while the client's query gate is shut", function()
  fill(10)
  WoW.ah.canQuery = false
  Scan.StartFull(WoW.clock)
  Scan.Tick(WoW.clock + 5)
  T.eq(T.count("QueryAuctionItems"), 0)
  WoW.ah.canQuery = true
  Scan.Tick(WoW.clock + 6)
  T.eq(T.count("QueryAuctionItems"), 1)
end)

T.test("pages are spaced by the minimum delay", function()
  fill(120)
  Scan.StartFull(0)
  at(10, true)
  at(10.1)
  T.eq(T.count("QueryAuctionItems"), 1, "too soon")
  at(10.4)
  T.eq(T.count("QueryAuctionItems"), 2)
end)

T.test("an unanswered page is asked for again, then the scan stalls", function()
  fill(10)
  Scan.StartFull(0)
  local t = 0
  for _ = 1, 5 do
    t = t + 1 Scan.Tick(t)        -- sends (or resends)
    t = t + 16 Scan.Tick(t)       -- times out
  end
  T.eq(T.count("QueryAuctionItems"), 4, "first try plus three resends")
  local p = Scan.Progress(t)
  T.eq(p.state, "stalled") T.eq(p.reason, "server not responding")
  Scan.Continue()
  Scan.Tick(t + 1)
  T.eq(T.count("QueryAuctionItems"), 5, "continue tries again")
end)

T.test("a repeated page is not counted twice and is asked for again after a pause", function()
  fill(120)
  Scan.StartFull(0)
  at(1, true)
  WoW.ah.duplicateNext = 1
  at(2, true)                                   -- page 1 asked for, page 0 sent again
  at(3)
  T.eq(T.count("QueryAuctionItems [] [] [] 1"), 1, "waits the safe delay before re-asking")
  at(6.5)
  T.eq(T.count("QueryAuctionItems [] [] [] 1"), 2)
  pump()
  T.eq(day("14047:0").n, 120, "no duplicates recorded")
end)

T.test("two repeated pages switch the rest of the scan to safe pace", function()
  fill(120)
  Scan.StartFull(0)
  at(1, true)
  WoW.ah.duplicateNext = 2
  at(2, true)
  at(7, true)
  T.ok(Scan.Progress(7).safe)
end)

T.test("a page with uncached names waits for them, briefly", function()
  fill(3)
  WoW.ah.listings[2].noName = true
  Scan.StartFull(0)
  at(1, true)
  T.eq(Scan.Progress(1).state, "sent", "still waiting for names")
  WoW.ah.listings[2].noName = false
  Scan.OnListUpdate(1.2)
  T.eq(Scan.job, nil, "complete page accepted")
  T.eq(day("14047:0").n, 3)
end)

T.test("names that never arrive don't hold the scan up", function()
  fill(3)
  WoW.ah.listings[2].noName = true
  Scan.StartFull(0)
  at(1, true)
  at(2.1)
  T.eq(Scan.job, nil)
  T.eq(day("14047:0").n, 2, "the nameless row is skipped")
end)

T.test("closing the AH mid-scan keeps progress, re-asking the unanswered page", function()
  fill(120)
  Scan.StartFull(0)
  at(1, true)
  at(2)                                 -- page 1 requested, never answered
  Scan.Pause("closed")
  T.eq(Scan.job, nil)
  local saved = Scan.Resumable()
  T.eq(saved.page, 1) T.eq(table.getn(saved.rows), 50)
  WoW.ah.pending = false                -- that request died with the session
  WoW.clock = 10
  T.ok(Scan.Resume(10))
  pump()
  T.eq(day("14047:0").n, 120)
  T.eq(DB.Realm().scan.resume, nil)
end)

T.test("a paused scan from yesterday is discarded, not mixed into today", function()
  fill(120)
  Scan.StartFull(0)
  at(1, true)
  Scan.Pause("closed")
  WoW.now = WoW.now + 86400
  T.eq(Scan.Resumable(), nil)
  T.eq(Scan.Resume(5), false)
end)

T.test("watchlist scan asks for each known name and skips unknown ones", function()
  I.Remember(14047, "Runecloth") I.Remember(4306, "Silk Cloth")
  local w = DB.Realm().watch
  w["14047:0"] = true w["4306:0"] = true w["99999:0"] = true
  fill(5) fill(5, 4306, "Silk Cloth", 600)
  T.ok(Scan.StartWatch(0))
  pump()
  T.ok(T.calledWith("QueryAuctionItems [Runecloth]"))
  T.ok(T.calledWith("QueryAuctionItems [Silk Cloth]"))
  T.ok(not T.calledWith("QueryAuctionItems []"), "never an empty name: that would be a full scan")
  T.eq(day("4306:0").src, "watch")
end)

T.test("an empty watchlist doesn't start", function()
  local ok, why = Scan.StartWatch(0)
  T.eq(ok, false) T.eq(why, "empty")
end)

T.test("browse shows one page and feeds history without trumping a full scan", function()
  fill(60, 4306, "Silk Cloth", 600)
  Scan.StartFull(0) pump()
  local full = day("4306:0").p25
  T.ok(Scan.Browse("Silk", 1, WoW.clock))
  pump()
  T.eq(table.getn(Scan.lastRows), 10, "second page")
  T.eq(Scan.lastTotal, 60)
  T.eq(Scan.lastPage, 1)
  T.eq(Scan.lastRows[1].name, "Silk Cloth")
  T.eq(day("4306:0").p25, full)
end)

T.test("browse can be kept out of history", function()
  DB.S().browseFeedsHistory = false
  fill(5)
  Scan.Browse("Rune", 0, 0) pump()
  T.eq(DB.Realm().history["14047:0"], nil)
end)

T.test("searching during a full scan is refused and the scan carries on", function()
  fill(120)
  Scan.StartFull(0)
  at(1)
  local ok, why = Scan.Browse("Rune", 0, 1)
  T.eq(ok, false) T.eq(why, "busy")
  T.eq(Scan.job.kind, "full")
  pump()
  T.eq(day("14047:0").n, 120)
end)

T.test("progress estimates time left from the measured page rate", function()
  fill(500)
  Scan.StartFull(0)
  at(0, true)
  at(5, true)
  local p = Scan.Progress(10)
  T.eq(p.totalPages, 10) T.eq(p.page, 2)
  T.near(p.secsPerPage, 5, 0.01)
  T.near(p.eta, 40, 0.01)
end)

T.test("listeners hear about changes", function()
  local heard = 0
  Scan.OnChange(function() heard = heard + 1 end)
  fill(5)
  Scan.StartFull(0) pump()
  T.ok(heard >= 2)
end)

T.test("genuinely identical pages are accepted once re-asks are exhausted", function()
  for _ = 1, 120 do
    table.insert(WoW.ah.listings, { id = 14047, name = "Runecloth", count = 20,
      buyout = 8000, owner = "S1", minBid = 7000, bid = 0 })
  end
  T.ok(Scan.StartFull(WoW.clock))
  pump()
  T.eq(Scan.job, nil, "scan finished")
  T.eq(day("14047:0").n, 120)
end)
