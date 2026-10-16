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

-- Shapes and field names follow sync/SCHEMA.md (the addon's own), so the merge's real identities and
-- rules are exercised and a sync of this file reports no path without a rule.
local today = math.floor(base / 86400)
local items = {
  { id = "14048", name = "Bolt of Runecloth", vendor = 1000 },
  { id = "14047", name = "Runecloth", vendor = 450 },
  { id = "13468", name = 'Black Lotus "Rare"', vendor = 0 },
  { id = "4306", name = "Silk Cloth", vendor = 150 },
  { id = "19019", name = "Thunderfury, Blessed Blade of the Windseeker", vendor = 0 },
}
for i, it in ipairs(items) do
  db.items[it.id] = {
    n = it.name, q = 1 + math.mod(i, 4), st = 20, t = "Interface\\Icons\\INV_Misc_" .. it.id,
    v = it.vendor, dep = { [480] = 25 * i, [120] = 6 * i },
  }
  if it.vendor > 0 then db.items[it.id].vb = it.vendor * 4 end
  local entry = { days = {}, months = {} }
  for d = 0, 29 do
    local day = today - 29 + d
    entry.days[day] = {
      n = 5 + math.mod(d * 7, 11), qty = 40 + d, min = 1000 * i + d, p25 = 1100 * i + d, med = 1200 * i + d,
      sellers = 3, src = (d == 3) and "browse" or "full",
    }
  end
  for m = 4, 9 do
    entry.months[202500 + m] = { p25 = 1000 * i + m * 3, n = 100 + m, d = 20 + m }
  end
  realm.history[it.id] = entry
end
A.Scan.RecomputeMarket()
realm.scan.lastFull = base
realm.snapshot = { at = base, day = today, changedAt = base, rows = {
  ["14047"] = { "12|5000|4000|Alice", "3|5200|4100|Bob" },
  ["4306"] = { "7|900|800|Carol" },
} }
realm.watch["14048"] = base - 500
realm.watch["13468"] = base - 400
realm.snipe["14047"] = { max = 300, at = base - 3600, name = "Runecloth" }
realm.snipe["4306"] = { max = 99, at = base - 7200, name = "Silk Cloth" }
realm.removed.watch["19019"] = base - 86400
realm.removed.snipe["19019"] = base - 90000
db.settings.mail.keep["Auction expired"] = base - 1000
db.settings.mail.keepRemoved["Old rule"] = base - 5000

db.recipes.Tailoring = {
  trainer = { ["Bolt of Runecloth"] = { c = 250, s = 250, at = base - 5000 } },
  seen = { ["14046"] = { n = "Runecloth Bag", skill = 260, r = 1, at = base - 6000 } },
}

local function char(name, class, extra)
  local c = { class = class }
  c.bags = { ["14047"] = 40, ["4306"] = 13 }
  c.bagsAt = base - 100
  c.bank = { ["14048"] = 12, ["13468"] = 1 }
  c.bankAt = base - 5000
  c.professions = {
    Tailoring = { rank = 250, maxRank = 300, at = base - 4000, recipes = { ["Bolt of Runecloth"] = true, ["Runecloth Bag"] = true } },
    Enchanting = { rank = 40, maxRank = 75, at = base - 4500, recipes = {} },
  }
  c.sales = {
    { at = base - 86400, key = "14048", name = "Bolt of Runecloth", outcome = "sold", money = 8800, qty = 5, unit = 1760, secs = 3600 },
    { at = base - 43200, key = "13468", name = 'Black Lotus "Rare"', outcome = "expired", money = 0, qty = 1 },
  }
  c.postings = {
    { at = base - 3000, key = "14047", stack = 20, bid = 4000, buyout = 5000, minutes = 480, deposit = 120, done = "sold" },
    { at = base - 2000, key = "4306", stack = 10, bid = 800, buyout = 900, minutes = 480, deposit = 40 },
  }
  c.ledger = {}
  for i = 1, 25 do
    table.insert(c.ledger, { at = base - i * 1000, kind = (math.mod(i, 2) == 0) and "sale" or "buy",
      amount = 1000 * i + 7, key = "14048", qty = i, who = "Someone's \"Alt\"" })
  end
  table.insert(c.ledger, { at = base - 700, kind = "vendorIn", amount = 350, who = "Vendor Bob" })
  table.insert(c.ledger, { at = base - 600, kind = "mailOut", amount = 30, who = "Postage" })
  c.ledgerBackfilled = true
  c.pendingBids = {
    { name = "Silk Cloth", amount = 1234, at = base - 50, key = "4306" },
    { name = "Runecloth", amount = 500, at = base - 60, key = "14047", used = base - 10 },
  }
  c.pendingBuys = { { name = "Runecloth", at = base - 40 } }
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
