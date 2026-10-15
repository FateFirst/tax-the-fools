TaxTheFools = TaxTheFools or {}
local U = TaxTheFools.Util
local Stock = {}
TaxTheFools.Stock = Stock

-- Pure: characters, counts, items, market and the clock arrive as arguments.

local DAY = 86400

local function nameOf(items, key)
  local it = items and items[U.keyId(key)]
  return (it and it.n) or key
end

local function byName(a, b)
  if a.name ~= b.name then return a.name < b.name end
  return a.key < b.key
end

-- Rows for the items in bagCounts that came back unsold (expired or cancelled) within `days`, by name.
function Stock.Repost(char, bagCounts, items, market, days, now)
  local since = now - (days or 7) * DAY
  local back = {}
  for _, s in ipairs((char and char.sales) or {}) do
    if s.key and (s.outcome == "expired" or s.outcome == "cancelled") and (s.at or 0) >= since then
      local prev = back[s.key]
      if not prev or s.at >= prev.at then back[s.key] = s end
    end
  end
  local rows = {}
  for key, s in pairs(back) do
    local have = (bagCounts and bagCounts[key]) or 0
    if have > 0 then
      local row = { key = key, name = nameOf(items, key), have = have, lastAt = s.at, outcome = s.outcome }
      local last
      for _, p in ipairs((char and char.postings) or {}) do
        if p.key == key and (not last or (p.at or 0) >= (last.at or 0)) then last = p end
      end
      if last then
        row.lastStack = last.stack
        if last.buyout and last.stack and last.stack > 0 then row.lastBuyout = math.floor(last.buyout / last.stack) end
      end
      local m = market and market[key]
      row.suggest = m and m.v or nil
      table.insert(rows, row)
    end
  end
  table.sort(rows, byName)
  return rows
end

local function entryFor(byKey, key, items, market, statsByKey, trendFn)
  local e = byKey[key]
  if not e then
    local m = market and market[key]
    e = { key = key, name = nameOf(items, key), bags = 0, bank = 0, onAH = 0, total = 0, perChar = {},
      unit = m and m.v or nil }
    byKey[key] = e
  end
  return e
end

-- One row per key held anywhere (bags, bank, open postings), by value descending, unvalued last.
-- `items` (optional) supplies names; without it the name is the key.
function Stock.Rows(chars, market, statsByKey, trendFn, items)
  local byKey, per = {}, {}
  local function slot(key, cname)
    local e = entryFor(byKey, key, items, market, statsByKey, trendFn)
    local pk = key .. "|" .. cname
    local pc = per[pk]
    if not pc then
      pc = { name = cname, bags = 0, bank = 0, onAH = 0 }
      per[pk] = pc
      table.insert(e.perChar, pc)
    end
    return e, pc
  end
  for cname, c in pairs(chars or {}) do
    for key, n in pairs(c.bags or {}) do
      if n > 0 then
        local e, pc = slot(key, cname)
        e.bags, pc.bags = e.bags + n, pc.bags + n
      end
    end
    for key, n in pairs(c.bank or {}) do
      if n > 0 then
        local e, pc = slot(key, cname)
        e.bank, pc.bank = e.bank + n, pc.bank + n
      end
    end
    for _, p in ipairs(c.postings or {}) do
      if p.key and not p.done then
        local e, pc = slot(p.key, cname)
        local n = p.stack or 1
        e.onAH, pc.onAH = e.onAH + n, pc.onAH + n
      end
    end
  end
  local rows = {}
  for key, e in pairs(byKey) do
    e.total = e.bags + e.bank + e.onAH
    e.value = e.unit and e.unit * e.total or nil
    local st = statsByKey and statsByKey[key]
    e.rate = st and st.rate or nil
    e.trend = trendFn and trendFn(key) or nil
    table.sort(e.perChar, function(a, b) return a.name < b.name end)
    table.insert(rows, e)
  end
  table.sort(rows, function(a, b)
    if (a.value ~= nil) ~= (b.value ~= nil) then return a.value ~= nil end
    if a.value and a.value ~= b.value then return a.value > b.value end
    return byName(a, b)
  end)
  return rows
end

-- { items = keys, units, value } over rows; unvalued rows add no value.
function Stock.Total(rows)
  local t = { items = 0, units = 0, value = 0 }
  for _, r in ipairs(rows or {}) do
    t.items = t.items + 1
    t.units = t.units + (r.total or 0)
    t.value = t.value + (r.value or 0)
  end
  return t
end
