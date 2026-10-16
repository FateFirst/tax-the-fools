-- Fills TaxTheFoolsDB under the fake client and writes it in SavedVariables format.
-- Run from the repo root: make sync-fixture
dofile("tests/wow_stub.lua")
WoW.reset()

local toc = io.open("TaxTheFools/TaxTheFools.toc")
local files = {}
for line in toc:lines() do
  local _, _, f = string.find(line, "^([%w_]+%.lua)%s*$")
  if f then table.insert(files, f) end
end
toc:close()
for _, f in ipairs(files) do dofile("TaxTheFools/" .. f) end
WoW.fire("VARIABLES_LOADED")

local A = TaxTheFools
local DB = A.DB
local db = TaxTheFoolsDB
local realm = DB.Realm()
local base = 1760000000

db.settingsAt = base
db.settings.mail.bankAlt = 'Bank "Alt"'
db.settings.scale = 1.25
db.settings.minimapAngle = -37.5

local items = {
  { id = "14048", name = "Bolt of Runecloth", vendor = 1000 },
  { id = "14047", name = "Runecloth", vendor = 450 },
  { id = "13468", name = 'Black Lotus "Rare"', vendor = 0 },
  { id = "4306", name = "Silk Cloth", vendor = 150 },
  { id = "19019", name = "Thunderfury, Blessed Blade of the Windseeker", vendor = 0 },
}
for i, it in ipairs(items) do
  db.items[it.id] = {
    name = it.name, vendor = it.vendor, stack = 20, quality = 1 + math.mod(i, 4),
    link = "|cffffffff|Hitem:" .. it.id .. ":0:0:0|h[" .. it.name .. "]|h|r",
    deposit = { [480] = 25 * i },
  }
  local entry = { days = {}, months = {} }
  for d = 0, 29 do
    local day = 20000 + d
    entry.days[day] = {
      n = 5 + math.mod(d * 7, 11), qty = 40 + d, min = 1000 * i + d, p25 = 1100 * i + d, med = 1200 * i + d,
      sellers = 3, src = (d == 3) and "browse" or "full",
    }
  end
  for m = 1, 6 do
    entry.months[24000 + m] = { n = 100 + m, min = 900 * i, p25 = 1000 * i + m * 3, med = 1150 * i, days = 20 + m }
  end
  realm.history[it.id] = entry
  realm.market[it.id] = A.Price.Market(entry, 20029)
end
realm.scan = { at = base, pages = 120, count = 5234, full = true, duration = 61.5 }
realm.watch["14048"] = true
realm.watch["13468"] = true
realm.snipe["14047"] = { price = 300, at = base - 3600, name = "Runecloth" }
realm.snipe["4306"] = { price = 99, at = base - 7200, name = "Silk Cloth" }

db.recipes.Tailoring = {
  ["Bolt of Runecloth"] = { item = "14048", skill = 250, reagents = { ["14047"] = 4 } },
  ["Runecloth Bag"] = { item = "14046", skill = 260, reagents = { ["14048"] = 5, ["14341"] = 2 } },
}

local function char(name, class, extra)
  local c = { class = class }
  c.bags = { ["14047"] = 40, ["4306"] = 13 }
  c.bagsAt = base - 100
  c.bank = { ["14048"] = 12, ["13468"] = 1 }
  c.bankAt = base - 5000
  c.professions = {
    Tailoring = { rank = 250, max = 300, recipes = { ["Bolt of Runecloth"] = true, ["Runecloth Bag"] = true } },
    Enchanting = { rank = 40, max = 75, recipes = {} },
  }
  c.sales = {
    { at = base - 86400, key = "14048", qty = 5, price = 8800, state = "sold" },
    { at = base - 43200, key = "13468", qty = 1, price = 250000, state = "expired" },
  }
  c.postings = {
    { at = base - 3000, key = "14047", qty = 20, bid = 4000, buyout = 5000, minutes = 480 },
  }
  c.ledger = {}
  for i = 1, 25 do
    table.insert(c.ledger, { at = base - i * 1000, kind = (math.mod(i, 2) == 0) and "sale" or "buy",
      amount = 1000 * i + 7, key = "14048", qty = i, who = "Someone's \"Alt\"" })
  end
  c.ledgerBackfilled = true
  c.pendingBids = { { name = "Silk Cloth", amount = 1234, at = base - 50, key = "4306" } }
  c.seenMail = {
    ["Auction successful: Runecloth\\x1"] = { at = base - 900, n = 2 },
    ["line one\nline two|Hitem:1|h[x]|h"] = { at = base - 800, n = 1 },
  }
  if extra then for k, v in pairs(extra) do c[k] = v end end
  realm.chars[name] = c
end
char("Fizzlebang", "MAGE")
char("Dragonbait", "WARRIOR", { ledgerBackfilled = false })
char("Zeppo", "ROGUE")

-- Serialiser: the client's shape, keys sorted (numbers first), tabs for depth.
local function q(s)
  s = string.gsub(s, "[%c\\\"]", function(c)
    if c == "\\" then return "\\\\" end
    if c == '"' then return '\\"' end
    if c == "\n" then return "\\n" end
    if c == "\r" then return "\\r" end
    return string.format("\\%03d", string.byte(c))
  end)
  return '"' .. s .. '"'
end

local function num(n)
  if n == math.floor(n) and n > -1e15 and n < 1e15 then return string.format("%d", n) end
  return string.format("%.14g", n)
end

local function ser(v, depth)
  local t = type(v)
  if t == "table" then
    local nk, sk = {}, {}
    for k in pairs(v) do
      if type(k) == "number" then table.insert(nk, k) else table.insert(sk, k) end
    end
    table.sort(nk)
    table.sort(sk)
    if table.getn(nk) + table.getn(sk) == 0 then return "{\n" .. string.rep("\t", depth) .. "}" end
    local out = { "{\n" }
    local pad = string.rep("\t", depth + 1)
    for _, k in ipairs(nk) do
      table.insert(out, pad .. "[" .. num(k) .. "] = " .. ser(v[k], depth + 1) .. ",\n")
    end
    for _, k in ipairs(sk) do
      table.insert(out, pad .. "[" .. q(k) .. "] = " .. ser(v[k], depth + 1) .. ",\n")
    end
    table.insert(out, string.rep("\t", depth) .. "}")
    return table.concat(out)
  elseif t == "string" then return q(v)
  elseif t == "number" then return num(v)
  elseif t == "boolean" then return tostring(v)
  end
  return "nil"
end

local f = assert(io.open("sync/luasv/testdata/big.lua", "wb"))
f:write("TaxTheFoolsDB = " .. ser(TaxTheFoolsDB, 0) .. "\n")
f:close()
print("wrote sync/luasv/testdata/big.lua")
