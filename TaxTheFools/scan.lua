TaxTheFools = TaxTheFools or {}
local U, D, P, DB, I = TaxTheFools.Util, TaxTheFools.Data, TaxTheFools.Price, TaxTheFools.DB, TaxTheFools.Items
local Scan = { job = nil, listeners = {}, lastRows = {}, lastTotal = 0, lastPage = 0 }
TaxTheFools.Scan = Scan

function Scan.ResetState()
  Scan.job, Scan.lastRows, Scan.lastTotal, Scan.lastPage = nil, {}, 0, 0
  Scan.pendingMarket, Scan.lastFinished = nil, nil
end

function Scan.OnChange(fn) table.insert(Scan.listeners, fn) end
local function changed() for _, fn in ipairs(Scan.listeners) do fn() end end

-- fn(rows) runs once per processed page with that page's new listing entries
-- ({ key, unit, qty, owner, buyout, minBid }), for every kind of scan and Browse search.
Scan.rowListeners = {}
function Scan.OnRows(fn) table.insert(Scan.rowListeners, fn) end
local function fireRows(rows)
  for _, fn in ipairs(Scan.rowListeners) do fn(rows) end
end

function Scan.Busy() return Scan.job ~= nil end

local function delay(job)
  if job.safe or DB.S().safeMode then return D.SAFE_DELAY end
  return DB.S().scanDelay or 0.3
end

local function newJob(kind, queries, now)
  return { kind = kind, queries = queries, qi = 1, page = queries[1].page or 0, totalPages = nil,
           state = "wait", reason = nil, lastQueryAt = -1000, sentAt = 0, holdUntil = 0,
           retries = 0, dupes = 0, pageDupes = 0, safe = false, lastSig = nil, lastLooseSig = nil, incompleteSince = nil,
           listings = {}, pagesDone = 0, pagesRun = 0, firstSentAt = nil,
           startedAt = now, day = U.day(time()) }
end

function Scan.Start(kind, queries, now)
  if Scan.job then return false, "busy" end
  if table.getn(queries) == 0 then return false, "empty" end
  Scan.job = newJob(kind, queries, now)
  changed()
  return true
end

function Scan.StartFull(now) return Scan.Start("full", { { name = "" } }, now) end

-- One exact-name query per watched item whose name is known. An unknown name
-- is skipped, never sent as "": an empty name is a full scan.
function Scan.WatchQueries()
  local seen, names = {}, {}
  for key in pairs(DB.Realm().watch) do
    local rec = I.Get(U.keyId(key))
    local name = rec and rec.n
    if name and name ~= "" and not seen[name] then
      seen[name] = true
      table.insert(names, name)
    end
  end
  table.sort(names)
  local queries = {}
  for _, n in ipairs(names) do table.insert(queries, { name = n }) end
  return queries
end

function Scan.StartWatch(now) return Scan.Start("watch", Scan.WatchQueries(), now) end

local function namesToQueries(seen)
  local names = {}
  for n in pairs(seen) do table.insert(names, n) end
  table.sort(names)
  local queries = {}
  for _, n in ipairs(names) do table.insert(queries, { name = n }) end
  return queries
end

-- Every reagent of every captured recipe on the realm, plus the shopping plan's AH buy lines.
function Scan.MatsQueries()
  local seen = {}
  local function add(n) if n and n ~= "" then seen[n] = true end end
  for _, c in pairs(DB.Realm().chars or {}) do
    for _, prof in pairs(c.professions or {}) do
      for _, r in pairs(prof.recipes or {}) do
        for _, g in ipairs(r.reagents or {}) do
          local rec = g.item and I.Get(U.keyId(g.item))
          add((rec and rec.n) or g.name)
        end
      end
    end
  end
  local cu = TaxTheFools.CraftUI
  local plan = cu and cu.shopping
  if plan and plan.buys then
    for _, b in ipairs(plan.buys) do
      if b.source == "ah" or not b.source then add(b.name) end
    end
  end
  return namesToQueries(seen)
end

function Scan.SnipeQueries()
  local seen = {}
  for key, e in pairs(DB.Realm().snipe or {}) do
    local rec = I.Get(U.keyId(key))
    local n = (e and e.name) or (rec and rec.n)
    if n and n ~= "" then seen[n] = true end
  end
  return namesToQueries(seen)
end

function Scan.StartMats(now) return Scan.Start("mats", Scan.MatsQueries(), now) end
function Scan.StartSnipe(now) return Scan.Start("snipe", Scan.SnipeQueries(), now) end

function Scan.Browse(name, page, now)
  return Scan.Start("browse", { { name = name or "", page = page or 0 } }, now)
end

-- Pages through an exact-name search until a listing matching sig = { key, count,
-- buyout, owner } turns up, as an ordinary browse job: pacing, retries and the busy
-- lock all apply. Paging is a scan, never a buy. onDone(index, page) runs once, with
-- the row index on the page the list now shows (0-based page), or nil when the
-- results ran out; onDone(nil, page, "noreply") when the server stopped answering.
function Scan.Locate(name, sig, onDone, now)
  local ok, why = Scan.Browse(name, 0, now or GetTime())
  if not ok then return false, why end
  Scan.job.locate = { sig = sig, onDone = onDone }
  return true
end

-- Index of the row that is the listing sig describes, or nil. The owner is only
-- compared when both sides know it.
local function findRow(rows, sig)
  for _, r in ipairs(rows) do
    if r.key == sig.key and r.count == sig.count and r.buyout == sig.buyout
       and (not r.owner or not sig.owner or r.owner == sig.owner) then
      return r.index
    end
  end
  return nil
end

local function send(job, now)
  local q = job.queries[job.qi]
  QueryAuctionItems(q.name or "", "", "", nil, nil, nil, job.page, nil, nil)
  job.state, job.sentAt, job.lastQueryAt = "sent", now, now
  job.incompleteSince = nil
  if not job.firstSentAt then job.firstSentAt = now end
end

-- kind is "list" (the search page, the default) or "owner" (your own auctions).
function Scan.ReadRow(i, kind)
  kind = kind or "list"
  local name, texture, count, quality, _, _, minBid, minInc, buyout, bid, high, owner = GetAuctionItemInfo(kind, i)
  local link = GetAuctionItemLink(kind, i)
  local key, id = U.keyFromLink(link)
  if not name or not key then return nil end
  I.Remember(id, name, quality, nil, texture)
  if not count or count < 1 then count = 1 end
  local unit = nil
  if buyout and buyout > 0 then unit = buyout / count end
  return { key = key, id = id, name = name, link = link, texture = texture, quality = quality, count = count,
           minBid = minBid or 0, bid = bid or 0, minInc = minInc or 0, buyout = buyout or 0,
           unit = unit, owner = owner, index = i, high = high and true or false }
end

-- The loose form leaves the owner out: on 1.12 owner names arrive after the
-- rest, so one page can be read twice with different owners.
local function signature(rows, loose)
  local parts = { table.getn(rows) }
  for _, r in ipairs(rows) do
    local owner = loose and "" or (r.owner or "")
    table.insert(parts, r.key .. "/" .. r.count .. "/" .. r.buyout .. "/" .. owner
      .. "/" .. r.minBid .. "/" .. r.bid)
  end
  return table.concat(parts, ";")
end

-- Takes the page the server sent. Waits up to NAME_WAIT for rows whose item the
-- client has not cached yet (they arrive nameless); force accepts regardless.
function Scan.Accept(now, force)
  local job = Scan.job
  if not job or job.state ~= "sent" then return end
  local batch, total = GetNumAuctionItems("list")
  local rows, missing = {}, 0
  for i = 1, batch do
    local r = Scan.ReadRow(i)
    if r then table.insert(rows, r) else missing = missing + 1 end
  end
  if missing > 0 and not force then
    if not job.incompleteSince then job.incompleteSince = now end
    return
  end
  local sig, loose = signature(rows), signature(rows, true)
  -- The client fires the update again for the page it already showed when owner
  -- names arrive. If that lands after the next page was asked for it is a stale
  -- repeat, not the reply: ignore it and keep waiting. It still counts toward
  -- the page's re-ask cap so a genuinely identical page is taken in the end.
  if job.lastLooseSig and loose == job.lastLooseSig and sig ~= job.lastSig
      and job.pageDupes < D.MAX_DUPES then
    job.pageDupes = job.pageDupes + 1
    return
  end
  -- A repeat is held and asked for again. Identical listings can also be a
  -- genuine page (one seller, many identical stacks), so after MAX_DUPES
  -- re-asks of this page it is accepted rather than asked for forever.
  if job.lastSig and sig == job.lastSig and job.pageDupes < D.MAX_DUPES then
    -- Twice in the scan as a whole and the rest of it goes at safe pace.
    job.dupes = job.dupes + 1
    job.pageDupes = job.pageDupes + 1
    if job.dupes >= 2 then job.safe = true end
    job.state, job.holdUntil = "wait", now + D.SAFE_DELAY
    changed()
    return
  end
  job.lastSig, job.lastLooseSig, job.retries, job.pageDupes = sig, loose, 0, 0
  local fresh = {}
  for _, r in ipairs(rows) do
    local l = { key = r.key, unit = r.unit, qty = r.count, owner = r.owner,
                buyout = r.buyout, minBid = r.minBid }
    table.insert(job.listings, l)
    table.insert(fresh, l)
  end
  fireRows(fresh)
  job.pagesDone, job.pagesRun = job.pagesDone + 1, job.pagesRun + 1
  job.totalPages = math.ceil(total / D.PAGE_SIZE)
  if job.kind == "browse" then
    Scan.lastRows, Scan.lastTotal, Scan.lastPage = rows, total, job.page
    local loc = job.locate
    if loc then
      local index = findRow(rows, loc.sig)
      if not index and batch > 0 and (job.page + 1) * D.PAGE_SIZE < total then
        job.page = job.page + 1
        job.state = "wait"
        changed()
        return
      end
      local page = job.page
      Scan.Finish(now)
      loc.onDone(index, page)
      return
    end
    return Scan.Finish(now)
  end
  if batch == 0 or (job.page + 1) * D.PAGE_SIZE >= total then
    job.qi, job.page, job.lastSig, job.lastLooseSig, job.totalPages = job.qi + 1, 0, nil, nil, nil
    if job.qi > table.getn(job.queries) then return Scan.Finish(now) end
  else
    job.page = job.page + 1
  end
  job.state = "wait"
  changed()
end

function Scan.OnListUpdate(now) Scan.Accept(now, false) end

function Scan.Tick(now)
  local job = Scan.job
  if job then
    if job.state == "wait" then
      if now >= job.holdUntil and now - job.lastQueryAt >= delay(job) and CanSendAuctionQuery() then
        send(job, now)
      end
    elseif job.state == "sent" then
      if job.incompleteSince and now - job.incompleteSince >= D.NAME_WAIT then
        Scan.Accept(now, true)
      elseif now - job.sentAt > D.QUERY_TIMEOUT then
        job.retries = job.retries + 1
        if job.retries > D.MAX_RETRIES then
          if job.kind == "browse" then
            -- Nothing to resume and no strip button for it: drop it so searches work again.
            Scan.job = nil
            U.msg("Search got no reply from the auction house. Try again.")
            if job.locate then job.locate.onDone(nil, job.page, "noreply") end
          else
            job.state, job.reason = "stalled", "server not responding"
          end
        else
          job.state = "wait"
        end
        changed()
      end
    end
  end
  Scan.MarketStep()
end

function Scan.Finish(now)
  local job = Scan.job
  Scan.job = nil
  local realm = DB.Realm()
  if job.kind ~= "browse" or DB.S().browseFeedsHistory then
    local touched = P.Record(realm.history, P.Summarize(job.listings), job.day, job.kind)
    Scan.QueueMarket(touched)
  end
  if job.kind == "full" then realm.scan.lastFull = time() end
  if job.kind ~= "browse" then
    realm.scan.resume = nil
    Scan.SaveSnapshot(job)
  end
  Scan.lastFinished = { kind = job.kind, pages = job.pagesDone, listings = table.getn(job.listings),
                        secs = now - job.startedAt }
  changed()
end

function Scan.QueueMarket(keys)
  Scan.pendingMarket = Scan.pendingMarket or {}
  for _, k in ipairs(keys) do table.insert(Scan.pendingMarket, k) end
end

function Scan.MarketStep()
  local q = Scan.pendingMarket
  if not q then return end
  local realm, today = DB.Realm(), U.day(time())
  for _ = 1, D.MARKET_PER_FRAME do
    local key = table.remove(q)
    if not key then
      Scan.pendingMarket = nil
      changed()
      return
    end
    realm.market[key] = P.Market(realm.history[key], today)
  end
end

-- Stops the scan and keeps what it has, so the next visit can carry on. The
-- page in flight was never accepted, so resuming asks for it again.
function Scan.Pause(reason)
  local job = Scan.job
  if not job then return end
  Scan.job = nil
  -- A Find in flight would otherwise never hear back.
  if job.locate then job.locate.onDone(nil, job.page, "paused") end
  if job.kind ~= "browse" then
    local saved = { kind = job.kind, queries = job.queries, qi = job.qi, page = job.page, day = job.day,
                    pagesDone = job.pagesDone, rows = {} }
    for _, l in ipairs(job.listings) do
      table.insert(saved.rows, l.key .. "|" .. (l.unit or "") .. "|" .. l.qty .. "|" .. (l.owner or "")
        .. "|" .. (l.buyout or 0) .. "|" .. (l.minBid or 0))
    end
    DB.Realm().scan.resume = saved
  end
  changed()
end

-- Retry after "server not responding".
function Scan.Continue()
  local job = Scan.job
  if not job or job.state ~= "stalled" then return end
  job.state, job.retries, job.reason = "wait", 0, nil
  changed()
end

-- A saved scan, or nil. One from an earlier day is dropped: a day row never
-- mixes listings from two days.
function Scan.Resumable()
  local saved = DB.Realm().scan.resume
  if not saved then return nil end
  if saved.day ~= U.day(time()) then
    DB.Realm().scan.resume = nil
    return nil
  end
  return saved
end

-- A paused listing: key|unit|qty|owner|buyout|minBid. Rows saved by 0.2.0
-- stop after the owner; their buyout is unit x qty and their minimum bid unknown.
function Scan.ParseSaved(s)
  local _, _, key, unit, qty, owner, buyout, minBid = string.find(s, "^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
  if not key then
    _, _, key, unit, qty, owner = string.find(s, "^([^|]*)|([^|]*)|([^|]*)|(.*)$")
  end
  if not key then return nil end
  if owner == "" then owner = nil end
  local l = { key = key, unit = tonumber(unit), qty = tonumber(qty) or 1, owner = owner,
              buyout = tonumber(buyout), minBid = tonumber(minBid) or 0 }
  if not l.buyout then l.buyout = l.unit and math.floor(l.unit * l.qty + 0.5) or 0 end
  return l
end

function Scan.Resume(now)
  if Scan.job then return false end
  local saved = Scan.Resumable()
  if not saved then return false end
  local job = newJob(saved.kind, saved.queries, now)
  job.qi, job.page, job.pagesDone, job.day = saved.qi, saved.page, saved.pagesDone, saved.day
  for _, s in ipairs(saved.rows) do
    local l = Scan.ParseSaved(s)
    if l then table.insert(job.listings, l) end
  end
  DB.Realm().scan.resume = nil
  Scan.job = job
  changed()
  return true
end

function Scan.Discard()
  DB.Realm().scan.resume = nil
  changed()
end

function Scan.Progress(now)
  local job = Scan.job
  if not job then return nil end
  local p = { kind = job.kind, state = job.state, reason = job.reason, page = job.page, totalPages = job.totalPages,
              qi = job.qi, nq = table.getn(job.queries), listings = table.getn(job.listings), safe = job.safe }
  if job.firstSentAt and job.pagesRun > 0 then
    p.secsPerPage = (now - job.firstSentAt) / job.pagesRun
    local left
    if job.kind == "full" and job.totalPages then left = job.totalPages - job.page
    else left = p.nq - job.qi + 1 end
    p.eta = left * p.secsPerPage
  end
  return p
end

-- ---------- the listing snapshot (phase 3a spec section 3) ----------
-- realm.snapshot = { at = time(), day = day, rows = { [key] = { "count|buyout|minBid|owner", ... } } }.
-- Deals are read from it, so only listings with a buyout are kept.

function Scan.SnapRow(l)
  return l.qty .. "|" .. l.buyout .. "|" .. (l.minBid or 0) .. "|" .. (l.owner or "")
end

-- count, buyout, minBid, owner (nil when the server had not sent it).
function Scan.ParseSnapRow(s)
  local _, _, count, buyout, minBid, owner = string.find(s or "", "^(%d+)|(%d+)|(%d*)|(.*)$")
  if not count then return nil end
  if owner == "" then owner = nil end
  return tonumber(count), tonumber(buyout), tonumber(minBid) or 0, owner
end

local function snapRows(listings)
  local rows = {}
  for _, l in ipairs(listings) do
    if l.buyout and l.buyout > 0 then
      local list = rows[l.key]
      if not list then
        list = {}
        rows[l.key] = list
      end
      table.insert(list, Scan.SnapRow(l))
    end
  end
  return rows
end

-- A full scan replaces the snapshot. A watchlist scan replaces the rows of every
-- item it saw, and empties the rows of a watched item it searched for and did
-- not find: that item has sold out. A browse never comes here.
function Scan.SaveSnapshot(job)
  local realm = DB.Realm()
  local fresh = snapRows(job.listings)
  if job.kind == "full" then
    realm.snapshot = { at = time(), day = job.day, rows = fresh }
    return
  end
  local snap = realm.snapshot
  if not snap then
    snap = { at = time(), day = job.day, rows = {} }
    realm.snapshot = snap
  end
  local asked = {}
  for _, q in ipairs(job.queries) do asked[q.name] = true end
  for key in pairs(realm.watch) do
    local rec = I.Get(U.keyId(key))
    if rec and rec.n and asked[rec.n] then snap.rows[key] = nil end
  end
  for key, list in pairs(fresh) do snap.rows[key] = list end
end

-- Takes one listing out: sig = { key, count, buyout, owner }. The owner is only
-- compared when both sides know it. True when a row was removed.
function Scan.SnapshotRemove(sig)
  local snap = DB.Realm().snapshot
  local list = snap and snap.rows[sig.key]
  if not list then return false end
  for i, s in ipairs(list) do
    local count, buyout, _, owner = Scan.ParseSnapRow(s)
    if count == sig.count and buyout == sig.buyout and (not owner or not sig.owner or owner == sig.owner) then
      table.remove(list, i)
      if table.getn(list) == 0 then snap.rows[sig.key] = nil end
      return true
    end
  end
  return false
end

-- Whole days since the snapshot's scan, or nil without one.
function Scan.SnapshotAge(today)
  local snap = DB.Realm().snapshot
  if not snap or not snap.day then return nil end
  return today - snap.day
end
