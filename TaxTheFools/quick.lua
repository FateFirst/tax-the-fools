TaxTheFools = TaxTheFools or {}
local Quick = {}
TaxTheFools.Quick = Quick

-- Pure: bag slots and the prices (Sell.Suggest results by item key) arrive as arguments.

local function order(a, b)
  if a.name ~= b.name then return a.name < b.name end
  if a.count ~= b.count then return a.count > b.count end
  if a.bag ~= b.bag then return a.bag < b.bag end
  return a.slot < b.slot
end

-- One row per slot, priced per unit from prices[key]. status: nil (postable), "noprice", "vendor", "notscanned".
function Quick.Rows(slots, prices)
  local rows = {}
  for _, s in ipairs(slots or {}) do
    local p = prices and prices[s.key]
    local r = { bag = s.bag, slot = s.slot, key = s.key, id = s.id, name = s.name, count = s.count,
      tex = s.tex, quality = s.quality }
    if not p then
      r.status = "notscanned"
    elseif not p.buyout then
      r.status = "noprice"
    else
      r.unit, r.bid, r.source, r.atFloor = p.buyout, p.bid, p.source, p.atFloor
      if p.source == "vendor" then r.status = "vendor" end
    end
    table.insert(rows, r)
  end
  table.sort(rows, order)
  return rows
end

-- Index of the first postable row after `from` (0 = from the start), or nil.
-- Rows already posted, failed or skipped are never chosen.
function Quick.Next(rows, from, includeVendor)
  for i = (from or 0) + 1, table.getn(rows or {}) do
    local r = rows[i]
    if not r.done and (r.status == nil or (r.status == "vendor" and includeVendor)) then return i end
  end
  return nil
end

-- ---------- the bag scan ----------
-- Game side. Quick.Scan prices the bags: one exact-name AH query per distinct item id, kind "quick".
-- State: "idle", "scanning" (also while paused or stalled) or "ready". The listings are kept per item key
-- in Quick.listings so Quick.Reprice can price again (a new vendor multiple, say) without rescanning.

Quick.state = "idle"
Quick.rows = {}
Quick.listings = {}
Quick.ids = {}
Quick.listeners = {}
Quick.hooked = false

function Quick.ResetState()
  Quick.state, Quick.rows, Quick.listings, Quick.ids = "idle", {}, {}, {}
  Quick.scannedAt, Quick.job, Quick.baseFinished = nil, nil, nil
end

function Quick.OnChange(fn) table.insert(Quick.listeners, fn) end
local function changed() for _, fn in ipairs(Quick.listeners) do fn() end end

-- One entry per auctionable bag slot: { bag, slot, key, id, name, count, tex, quality }.
function Quick.ReadSlots()
  local A = TaxTheFools
  local U, I, Sell = A.Util, A.Items, A.Sell
  local slots = {}
  for bag = 0, 4 do
    for slot = 1, GetContainerNumSlots(bag) do
      local link = GetContainerItemLink(bag, slot)
      local key, id = U.keyFromLink(link)
      if key and Sell.Auctionable(Sell.TipLines(bag, slot)) then
        local tex, n = GetContainerItemInfo(bag, slot)
        local rec = I.Resolve(id)
        table.insert(slots, { bag = bag, slot = slot, key = key, id = id,
          name = (rec and rec.n) or U.linkName(link) or key, count = n or 1,
          tex = tex or (rec and rec.t), quality = rec and rec.q })
      end
    end
  end
  return slots
end

-- Prices every slot whose item id was in the scan, from the kept listings and the current settings.
function Quick.Reprice()
  local A = TaxTheFools
  local DB, I, Sell = A.DB, A.Items, A.Sell
  local s = DB.S().sell
  local opts = { floorPct = s.floorPct, undercut = s.undercut, bidPct = s.bidPct, vendorMult = s.vendorMult, me = DB.charName }
  local slots = Quick.ReadSlots()
  local prices = {}
  for _, sl in ipairs(slots) do
    if Quick.ids[sl.id] and not prices[sl.key] then
      local m = DB.Realm().market[sl.key]
      prices[sl.key] = Sell.Suggest(Quick.listings[sl.key] or {}, m and m.v or nil, I.Vendor(sl.id), opts)
    end
  end
  Quick.rows = Quick.Rows(slots, prices)
  return Quick.rows
end

local function finish()
  local A = TaxTheFools
  local DB, P, U = A.DB, A.Price, A.Util
  local job = Quick.job
  Quick.listings = {}
  for _, l in ipairs(job and job.listings or {}) do
    Quick.listings[l.key] = Quick.listings[l.key] or {}
    table.insert(Quick.listings[l.key], l)
  end
  -- Market values are normally worked out a batch per frame after the scan; the prices need them now.
  local realm, today = DB.Realm(), U.day(time())
  for key in pairs(Quick.listings) do
    if realm.history[key] then realm.market[key] = P.Market(realm.history[key], today) end
  end
  Quick.Reprice()
  Quick.scannedAt, Quick.job, Quick.state = time(), nil, "ready"
  changed()
end

-- Follows the shared scanner. Only a scan Quick started (kind "quick", even once resumed) counts.
local function onScan()
  if Quick.state ~= "scanning" then return end
  local Scan = TaxTheFools.Scan
  local job = Scan.job
  if job then
    if job.kind == "quick" then Quick.job = job end
    return
  end
  local fin = Scan.lastFinished
  if fin and fin ~= Quick.baseFinished and fin.kind == "quick" then
    finish()
  else
    local saved = TaxTheFools.DB.Realm().scan.resume
    if saved and saved.kind == "quick" then return end
    -- Discarded, dropped by another scan finishing, or replaced by another paused scan: nothing of ours to resume.
    Quick.job, Quick.state = nil, "idle"
    changed()
  end
end

-- Returns true, or false and "busy" / "empty".
function Quick.Scan(now)
  local A = TaxTheFools
  local Scan, U, I = A.Scan, A.Util, A.Items
  if Scan.Busy() then return false, "busy" end
  local slots = Quick.ReadSlots()
  local ids, seen, names = {}, {}, {}
  for _, sl in ipairs(slots) do
    if not ids[sl.id] then
      ids[sl.id] = true
      local base = GetItemInfo(sl.id)
      if not base or base == "" then base = sl.name end
      if not seen[base] then
        seen[base] = true
        table.insert(names, base)
      end
    end
  end
  table.sort(names)
  local queries = {}
  for _, n in ipairs(names) do table.insert(queries, { name = n }) end
  if not Quick.hooked then
    Quick.hooked = true
    Scan.OnChange(onScan)
  end
  Quick.baseFinished = Scan.lastFinished
  local ok, why = Scan.Start("quick", queries, now)
  if not ok then return false, why end
  Quick.ids, Quick.listings, Quick.job = ids, {}, Scan.job
  Quick.state = "scanning"
  changed()
  return true
end
