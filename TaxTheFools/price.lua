TaxTheFools = TaxTheFools or {}
local S, D = TaxTheFools.Stats, TaxTheFools.Data
local P = {}
TaxTheFools.Price = P

local function round(x) return math.floor(x + 0.5) end

-- One day's facts per item from raw listings { key, unit, qty, owner }.
-- unit is nil for a listing with no buyout: it still counts as supply.
function P.Summarize(listings)
  local by = {}
  for _, l in ipairs(listings) do
    local b = by[l.key]
    if not b then
      b = { units = {}, qtys = {}, n = 0, qty = 0, owners = {}, nOwners = 0 }
      by[l.key] = b
    end
    b.n = b.n + 1
    b.qty = b.qty + (l.qty or 1)
    if l.unit then
      table.insert(b.units, l.unit)
      table.insert(b.qtys, l.qty or 1)
    end
    if l.owner and not b.owners[l.owner] then
      b.owners[l.owner] = true
      b.nOwners = b.nOwners + 1
    end
  end
  local rows = {}
  for key, b in pairs(by) do
    local row = { n = b.n, qty = b.qty }
    if table.getn(b.units) > 0 then
      row.min = round(S.weightedPercentile(b.units, nil, 0))
      row.p25 = round(S.weightedPercentile(b.units, b.qtys, 0.25))
      row.med = round(S.weightedPercentile(b.units, b.qtys, 0.5))
    end
    if b.nOwners > 0 then row.sellers = b.nOwners end
    rows[key] = row
  end
  return rows
end

-- Writes day rows. A browse sees a sliver of the market, so it never replaces
-- a full or watchlist row written the same day.
function P.Record(history, rows, day, src)
  local touched = {}
  for key, row in pairs(rows) do
    local entry = history[key]
    if not entry then
      entry = { days = {}, months = {} }
      history[key] = entry
    end
    entry.days = entry.days or {}
    entry.months = entry.months or {}
    local old = entry.days[day]
    if src ~= "browse" or not old or old.src == "browse" then
      row.src = src
      entry.days[day] = row
      table.insert(touched, key)
    end
  end
  return touched
end

function P.ConfLabel(conf)
  if conf >= 0.7 then return "high" end
  if conf >= 0.4 then return "medium" end
  return "low"
end

-- Market value: weighted median of daily p25 over 30 days, recent days counting
-- more. Confidence: how many days, discounted by how much the price moves.
function P.Market(entry, today)
  if not entry then return nil end
  local vals, ws, ns = {}, {}, {}
  local low, lowDay
  for day, row in pairs(entry.days or {}) do
    local age = today - day
    if age >= 0 and age < D.MARKET_DAYS and row.p25 then
      table.insert(vals, row.p25)
      table.insert(ws, math.pow(D.DECAY, age))
      table.insert(ns, row.n or 0)
    end
    if row.min and (not lowDay or day > lowDay) then low, lowDay = row.min, day end
  end
  local seen = table.getn(vals)
  if seen == 0 then
    local mv = {}
    for _, m in pairs(entry.months or {}) do
      if m.p25 then table.insert(mv, m.p25) end
    end
    if table.getn(mv) == 0 then return nil end
    return { v = round(S.median(mv)), conf = 0.1, low = low, lowDay = lowDay, seen = 0 }
  end
  local cv = S.cv(vals)
  if cv > 0.6 then cv = 0.6 end
  local conf = math.min(1, seen / 5) * (1 - cv / 0.6 * 0.5)
  return { v = round(S.weightedPercentile(vals, ws, 0.5)), conf = conf, low = low, lowDay = lowDay,
           seen = seen, n = S.median(ns) }
end

-- Trend: median daily p25 of days 0-6 against days 7-13, each side needing 3 days.
-- Returns { pct (rounded percent), dir, recent, prior } or nil.
local function sideMedian(entry, today, from, to)
  local vals = {}
  for day, row in pairs(entry.days or {}) do
    local age = today - day
    if age >= from and age <= to and row.p25 then table.insert(vals, row.p25) end
  end
  if table.getn(vals) < 3 then return nil end
  return S.median(vals)
end

function P.Trend(entry, today)
  if not entry then return nil end
  local recent = sideMedian(entry, today, 0, 6)
  local prior = sideMedian(entry, today, 7, 13)
  if not recent or not prior or prior <= 0 then return nil end
  local ratio = (recent - prior) / prior
  local pct = round(ratio * 100)
  local dir = "steady"
  if pct >= 5 then dir = "rising" elseif pct <= -5 then dir = "falling" end   -- the displayed percent decides
  return { pct = pct, dir = dir, recent = recent, prior = prior }
end

-- Theme token for a trend direction, shared by the tooltip and Browse.
function P.TrendToken(dir)
  if dir == "rising" then return "good" end
  if dir == "falling" then return "bad" end
  return "dim"
end

-- The p25 of each day in the last `days` days, oldest first, gaps left out.
function P.Series(entry, today, days)
  local out = {}
  if not entry then return out end
  for day, row in pairs(entry.days or {}) do
    local age = today - day
    if age >= 0 and age < days and row.p25 then table.insert(out, { day = day, p25 = row.p25 }) end
  end
  table.sort(out, function(a, b) return a.day < b.day end)
  return out
end

local function monthOf(day) return tonumber(date("!%Y%m", day * 86400)) end

-- Days past KEEP_DAYS become monthly averages; months past about a year go.
-- Returns true when nothing is left, so the caller can drop the entry.
function P.Compact(entry, today)
  entry.days = entry.days or {}
  entry.months = entry.months or {}
  for day, row in pairs(entry.days) do
    if today - day >= D.KEEP_DAYS then
      if row.p25 then
        local mk = monthOf(day)
        local m = entry.months[mk]
        if not m then
          m = { p25 = 0, n = 0, d = 0 }
          entry.months[mk] = m
        end
        m.p25 = round((m.p25 * m.d + row.p25) / (m.d + 1))
        m.n = round((m.n * m.d + (row.n or 0)) / (m.d + 1))
        m.d = m.d + 1
      end
      entry.days[day] = nil
    end
  end
  local oldest = monthOf(today - D.KEEP_MONTHS * 31)
  for mk in pairs(entry.months) do
    if mk < oldest then entry.months[mk] = nil end
  end
  return next(entry.days) == nil and next(entry.months) == nil
end
