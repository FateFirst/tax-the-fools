TaxTheFools = TaxTheFools or {}
local U, D = TaxTheFools.Util, TaxTheFools.Data
local Sell = {}
TaxTheFools.Sell = Sell

-- Pure: listings, prices, tooltip lines and the character record arrive as arguments.
-- The one game-side helper is Sell.TipLines.

Sell.LOG_MAX = 500
Sell.LOG_DAYS = 35
Sell.DURATIONS = { 120, 480, 1440 }        -- minutes, shown on Turtle as 6h, 24h and 72h
Sell.DURATION_LABELS = { [120] = "6h", [480] = "24h", [1440] = "72h" }

local function setting(s, k)
  if s and s[k] ~= nil then return s[k] end
  return D.DEFAULTS.settings.sell[k]
end

-- Suggested price per unit from competing listings { unit, count, owner }.
-- Your own listings (l.own, or owner == s.me) are ignored. s = { floorPct, undercut, bidPct, me }.
-- floor is floorPct% of market, rounded up to whole copper; with no market value there is no floor,
-- so the cheapest competing listing counts. Prices are whole copper (StartAuction takes no fractions).
function Sell.Suggest(listings, market, vendorSell, s)
  local floorPct, undercut, bidPct = setting(s, "floorPct"), setting(s, "undercut"), setting(s, "bidPct")
  local me = s and s.me
  local floor = nil
  if market then floor = math.ceil(market * floorPct / 100) end
  local cheapest = nil
  for _, l in ipairs(listings or {}) do
    local own = l.own or (me and l.owner and l.owner == me)
    if not own and l.unit and (not floor or l.unit >= floor) then
      if not cheapest or l.unit < cheapest then cheapest = l.unit end
    end
  end
  local out = { floor = floor }
  if cheapest then
    out.buyout, out.source = math.floor(cheapest - undercut), "undercut"
    if floor and out.buyout < floor then out.buyout = floor end
  elseif market then
    out.buyout, out.source = math.floor(market), "market"
  elseif vendorSell then
    out.buyout, out.source = math.floor(vendorSell * 3), "vendor"
  end
  if out.buyout then
    if out.buyout < 1 then out.buyout = 1 end
    out.bid = math.floor(out.buyout * bidPct / 100)
    if out.bid < 1 then out.bid = 1 end
  end
  return out
end

-- How many stacks of stackSize the units held make (a stack above maxStack is clamped).
function Sell.Stacks(have, stackSize, maxStack)
  if not stackSize or stackSize < 1 or not have or have < 1 then return 0 end
  if maxStack and stackSize > maxStack then stackSize = maxStack end
  return math.floor(have / stackSize)
end

-- What you receive: the buyout less the house cut, less the deposit.
function Sell.Net(total, deposit)
  return total * (1 - D.AH_CUT) - (deposit or 0)
end

-- lines: the item tooltip's text lines. False when one says soulbound, quest item or conjured.
-- Each check runs only where the client defines its global.
function Sell.Auctionable(lines)
  for _, name in ipairs({ "ITEM_SOULBOUND", "ITEM_BIND_QUEST", "ITEM_CONJURED" }) do
    local text = getglobal(name)
    if text then
      for _, l in ipairs(lines or {}) do
        if l and string.find(l, text, 1, true) then return false end
      end
    end
  end
  return true
end

-- Game side: the text lines of the item in a bag slot, read through the scan tooltip.
function Sell.TipLines(bag, slot)
  local tip = U.scanTip()
  tip:SetBagItem(bag, slot)
  local lines = {}
  local name = tip:GetName()
  for i = 1, tip:NumLines() do
    local fs = name and getglobal(name .. "TextLeft" .. i)
    local text = fs and fs.GetText and fs:GetText()
    if text then table.insert(lines, text) end
  end
  return lines
end

-- Drops entries older than LOG_DAYS (at is time() seconds).
function Sell.Prune(char, now)
  local list = char.postings
  if not list then return end
  local cutoff = now - Sell.LOG_DAYS * 86400
  local kept = {}
  for _, e in ipairs(list) do
    if (e.at or 0) >= cutoff then table.insert(kept, e) end
  end
  char.postings = kept
end

-- Appends a posting { key, stack, bid, buyout, minutes, deposit, at }, then caps and prunes.
function Sell.Log(char, entry, now)
  char.postings = char.postings or {}
  entry.at = entry.at or now
  table.insert(char.postings, entry)
  Sell.Prune(char, now)
  while table.getn(char.postings) > Sell.LOG_MAX do table.remove(char.postings, 1) end
end

-- items[id].dep = { [minutes] = per-unit deposit } as learned from money lost on a post.
function Sell.LearnDeposit(items, id, minutes, perUnit)
  items[id] = items[id] or {}
  local rec = items[id]
  rec.dep = rec.dep or {}
  rec.dep[minutes] = perUnit
end

-- The learned deposit for a stack, or nil when none is known for this item and duration.
function Sell.Deposit(items, id, minutes, stack)
  local rec = items and items[id]
  local per = rec and rec.dep and rec.dep[minutes]
  if not per then return nil end
  return math.floor(per * stack + 0.5)
end
