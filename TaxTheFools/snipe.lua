TaxTheFools = TaxTheFools or {}
local Snipe = {}
TaxTheFools.Snipe = Snipe

-- Pure snipe list rules (phase 7 spec section 3). list = DB.Realm().snipe, { [key] = { max, name, at } }.

-- Adds or updates an item. An item already listed keeps the higher of the two maximums.
function Snipe.Set(list, key, name, max, now)
  local e = list[key]
  if e and e.max and e.max > max then max = e.max end
  list[key] = { max = max, name = name, at = now }
  return list[key]
end

-- Sets the exact maximum of a listed item (the editable Max each field). nil when it is not listed.
function Snipe.SetMax(list, key, max)
  local e = list[key]
  if not e or not max or max <= 0 then return nil end
  e.max = max
  return e
end

function Snipe.Remove(list, key)
  if not list[key] then return false end
  list[key] = nil
  return true
end

-- One word as copper: "20s", "1g5s", "2g", "50c". nil when the word is not made only of g/s/c parts.
local function moneyWord(w)
  w = string.lower(w)
  local total, rest, any = 0, w, false
  while rest ~= "" do
    local _, e, n, u = string.find(rest, "^(%d+)([gsc])")
    if not e then return nil end
    n = tonumber(n)
    if u == "g" then n = n * 10000 elseif u == "s" then n = n * 100 end
    total = total + n
    any = true
    rest = string.sub(rest, e + 1)
  end
  if not any then return nil end
  return total
end

-- "Silk Cloth 20s", "Silk Cloth 1g 5s", "Silk Cloth 1g5s", "Silk Cloth 2g 50s 3c" or "Silk Cloth 2050"
-- (bare copper) -> name, copper. The name is everything before the money, trimmed. A trailing bare
-- number is always taken as copper, so an item whose name ends in a number needs a unit on the price.
-- nil when there is no name or no price above zero.
function Snipe.Parse(text)
  if type(text) ~= "string" then return nil end
  local words = {}
  for w in string.gfind(text, "%S+") do table.insert(words, w) end
  local n = table.getn(words)
  if n < 2 then return nil end
  local copper, first = 0, n + 1
  if string.find(words[n], "^%d+$") then
    copper, first = tonumber(words[n]), n
  else
    while first > 1 do
      local v = moneyWord(words[first - 1])
      if not v then break end
      copper = copper + v
      first = first - 1
    end
  end
  if first > n or first <= 1 or copper <= 0 then return nil end
  local name = words[1]
  for i = 2, first - 1 do name = name .. " " .. words[i] end
  return name, copper
end

function Snipe.Match(list, key, unit)
  local e = list and list[key]
  return e ~= nil and e.max ~= nil and unit <= e.max
end
