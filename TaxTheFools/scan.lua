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

function Scan.Busy() return Scan.job ~= nil end

local function delay(job)
  if job.safe or DB.S().safeMode then return D.SAFE_DELAY end
  return DB.S().scanDelay or 0.3
end

local function newJob(kind, queries, now)
  return { kind = kind, queries = queries, qi = 1, page = queries[1].page or 0, totalPages = nil,
           state = "wait", reason = nil, lastQueryAt = -1000, sentAt = 0, holdUntil = 0,
           retries = 0, dupes = 0, safe = false, lastSig = nil, incompleteSince = nil,
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

function Scan.Browse(name, page, now)
  return Scan.Start("browse", { { name = name or "", page = page or 0 } }, now)
end

local function send(job, now)
  local q = job.queries[job.qi]
  QueryAuctionItems(q.name or "", "", "", nil, nil, nil, job.page, nil, nil)
  job.state, job.sentAt, job.lastQueryAt = "sent", now, now
  job.incompleteSince = nil
  if not job.firstSentAt then job.firstSentAt = now end
end

function Scan.ReadRow(i)
  local name, texture, count, quality, _, _, minBid, minInc, buyout, bid, _, owner = GetAuctionItemInfo("list", i)
  local link = GetAuctionItemLink("list", i)
  local key, id = U.keyFromLink(link)
  if not name or not key then return nil end
  I.Remember(id, name, quality, nil, texture)
  if not count or count < 1 then count = 1 end
  local unit = nil
  if buyout and buyout > 0 then unit = buyout / count end
  return { key = key, id = id, name = name, link = link, texture = texture, quality = quality, count = count,
           minBid = minBid or 0, bid = bid or 0, minInc = minInc or 0, buyout = buyout or 0,
           unit = unit, owner = owner, index = i }
end

local function signature(rows)
  local parts = { table.getn(rows) }
  for _, r in ipairs(rows) do table.insert(parts, r.key .. "/" .. r.count .. "/" .. r.buyout) end
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
  local sig = signature(rows)
  if job.lastSig and sig == job.lastSig then
    -- The server repeated the previous page. Ask again after a pause; twice
    -- and the rest of this scan goes at safe pace.
    job.dupes = job.dupes + 1
    if job.dupes >= 2 then job.safe = true end
    job.state, job.holdUntil = "wait", now + D.SAFE_DELAY
    changed()
    return
  end
  job.lastSig, job.retries = sig, 0
  for _, r in ipairs(rows) do
    table.insert(job.listings, { key = r.key, unit = r.unit, qty = r.count, owner = r.owner })
  end
  job.pagesDone, job.pagesRun = job.pagesDone + 1, job.pagesRun + 1
  job.totalPages = math.ceil(total / D.PAGE_SIZE)
  if job.kind == "browse" then
    Scan.lastRows, Scan.lastTotal, Scan.lastPage = rows, total, job.page
    return Scan.Finish(now)
  end
  if batch == 0 or (job.page + 1) * D.PAGE_SIZE >= total then
    job.qi, job.page, job.lastSig, job.totalPages = job.qi + 1, 0, nil, nil
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
          job.state, job.reason = "stalled", "server not responding"
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
  if job.kind ~= "browse" then realm.scan.resume = nil end
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
  if job.kind ~= "browse" then
    local saved = { kind = job.kind, queries = job.queries, qi = job.qi, page = job.page, day = job.day,
                    pagesDone = job.pagesDone, rows = {} }
    for _, l in ipairs(job.listings) do
      table.insert(saved.rows, l.key .. "|" .. (l.unit or "") .. "|" .. l.qty .. "|" .. (l.owner or ""))
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

function Scan.Resume(now)
  if Scan.job then return false end
  local saved = Scan.Resumable()
  if not saved then return false end
  local job = newJob(saved.kind, saved.queries, now)
  job.qi, job.page, job.pagesDone, job.day = saved.qi, saved.page, saved.pagesDone, saved.day
  for _, s in ipairs(saved.rows) do
    local _, _, key, unit, qty, owner = string.find(s, "^([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if key then
      if owner == "" then owner = nil end
      table.insert(job.listings, { key = key, unit = tonumber(unit), qty = tonumber(qty) or 1, owner = owner })
    end
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
