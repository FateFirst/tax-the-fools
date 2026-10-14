TaxTheFools = TaxTheFools or {}
local U = {}
TaxTheFools.Util = U

U.PREFIX = "|cff52c722TTF:|r "

function U.msg(text)
  DEFAULT_CHAT_FRAME:AddMessage(U.PREFIX .. tostring(text))
end

function U.debug(text)
  if TaxTheFoolsDB and TaxTheFoolsDB.settings and TaxTheFoolsDB.settings.debug then
    U.msg("|cff888888" .. tostring(text) .. "|r")
  end
end

function U.trim(s)
  local _, _, r = string.find(s or "", "^%s*(.-)%s*$")
  return r or ""
end

function U.words(s)
  local t = {}
  for w in string.gfind(s or "", "%S+") do table.insert(t, w) end
  return t
end

function U.count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- Money as "12g 34s 56c". Zero parts are left out; nothing at all reads "0c".
-- Coloured like the client's coins unless plain is set.
function U.money(c, plain)
  c = math.floor((c or 0) + 0.5)
  local neg = c < 0
  if neg then c = -c end
  local g = math.floor(c / 10000)
  local s = math.floor(math.mod(c, 10000) / 100)
  local cp = math.mod(c, 100)
  local G, S, C, E = "|cffffd100", "|cffc7c7cf", "|cffc77840", "|r"
  if plain then G, S, C, E = "", "", "", "" end
  local parts = {}
  if g > 0 then table.insert(parts, G .. g .. "g" .. E) end
  if s > 0 then table.insert(parts, S .. s .. "s" .. E) end
  if cp > 0 or table.getn(parts) == 0 then table.insert(parts, C .. cp .. "c" .. E) end
  return (neg and "-" or "") .. table.concat(parts, " ")
end

-- 1.12 links are item:id:enchant:suffix:unique.
function U.parseLink(link)
  if not link then return nil end
  local _, _, id, enchant, suffix = string.find(link, "item:(%d+):(%d*):(%d*)")
  if not id then return nil end
  return tonumber(id), tonumber(suffix) or 0, tonumber(enchant) or 0
end

function U.key(id, suffix) return id .. ":" .. (suffix or 0) end

-- Enchants and unique ids are ignored; random suffixes ("of the Monkey") price separately.
function U.keyFromLink(link)
  local id, suffix = U.parseLink(link)
  if not id then return nil end
  return U.key(id, suffix), id
end

function U.keyId(key)
  local _, _, id = string.find(key or "", "^(%d+)")
  return tonumber(id)
end

function U.linkString(link)
  local _, _, s = string.find(link or "", "(item:[%d:%-]+)")
  return s
end

function U.day(t) return math.floor((t or time()) / 86400) end

function U.daysAgo(n)
  if not n or n <= 0 then return "today" end
  return n .. "d ago"
end

U.QUALITY = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000" }
function U.quality(q) return "|cff" .. (U.QUALITY[q or 1] or "ffffff") end

-- One hidden tooltip for reading what the client knows about an item.
local scanTip
function U.scanTip()
  if not scanTip then
    scanTip = CreateFrame("GameTooltip", "TaxTheFoolsScanTip", nil, "GameTooltipTemplate")
  end
  scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
  return scanTip
end
