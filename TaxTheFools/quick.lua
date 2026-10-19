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
