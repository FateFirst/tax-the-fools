TaxTheFools = TaxTheFools or {}
local D = TaxTheFools.Data
local DB = { wasBroken = false }
TaxTheFools.DB = DB

local function copyDefaults(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      copyDefaults(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end
DB.copyDefaults = copyDefaults

-- One-time changes to existing saved data, keyed by the version that needs them:
-- MIGRATIONS[2] = function(db) ... end runs once for anyone below version 2.
local MIGRATIONS = {}

function DB.ResetState()
  DB.wasBroken = false
  DB.pruneKeys, DB.pruneIndex = nil, 1
end

-- What a saved table must look like to be trusted.
function DB.Valid(db)
  if type(db) ~= "table" then return false end
  for _, k in ipairs({ "settings", "items", "realms" }) do
    if db[k] ~= nil and type(db[k]) ~= "table" then return false end
  end
  return true
end

function DB.Init()
  if TaxTheFoolsDB ~= nil and not DB.Valid(TaxTheFoolsDB) then
    if type(TaxTheFoolsDB_broken) ~= "table" then TaxTheFoolsDB_broken = {} end
    TaxTheFoolsDB_broken[time()] = TaxTheFoolsDB
    TaxTheFoolsDB = nil
    DB.wasBroken = true
  end
  if TaxTheFoolsDB == nil then TaxTheFoolsDB = { dataVersion = D.DATA_VERSION } end
  copyDefaults(TaxTheFoolsDB, D.DEFAULTS)
  local v = TaxTheFoolsDB.dataVersion or 0
  for n = v + 1, D.DATA_VERSION do
    if MIGRATIONS[n] then MIGRATIONS[n](TaxTheFoolsDB) end
  end
  TaxTheFoolsDB.dataVersion = D.DATA_VERSION
  if type(TaxTheFoolsCharDB) ~= "table" then TaxTheFoolsCharDB = {} end
  copyDefaults(TaxTheFoolsCharDB, D.CHAR_DEFAULTS)
  DB.realmName = GetRealmName() or "?"
  DB.charName = UnitName("player") or "?"
  return TaxTheFoolsDB
end

function DB.S() return TaxTheFoolsDB.settings end

-- Prices are per realm: the auction house is cross-faction on this server.
function DB.Realm()
  local realms = TaxTheFoolsDB.realms
  local r = realms[DB.realmName]
  if not r then
    r = {}
    realms[DB.realmName] = r
  end
  copyDefaults(r, D.REALM_DEFAULTS)
  return r
end

function DB.Char()
  local chars = DB.Realm().chars
  local c = chars[DB.charName]
  if not c then
    local _, class = UnitClass("player")
    c = { class = class }
    chars[DB.charName] = c
  end
  return c
end

function DB.Wipe()
  TaxTheFoolsDB, TaxTheFoolsCharDB = nil, nil
  DB.Init()
end

-- Retention runs over a snapshot of keys, a few per frame: next() over a table
-- that gains keys between calls is undefined in Lua.
DB.pruneKeys, DB.pruneIndex = nil, 1

function DB.StartPrune()
  local keys = {}
  for k in pairs(DB.Realm().history) do table.insert(keys, k) end
  DB.pruneKeys, DB.pruneIndex = keys, 1
end

function DB.PruneStep(budget, today)
  local keys = DB.pruneKeys
  if not keys then return true end
  local realm = DB.Realm()
  local last = math.min(table.getn(keys), DB.pruneIndex + budget - 1)
  for i = DB.pruneIndex, last do
    local key = keys[i]
    local entry = realm.history[key]
    if entry and TaxTheFools.Price.Compact(entry, today) then
      realm.history[key] = nil
      realm.market[key] = nil
    end
  end
  DB.pruneIndex = last + 1
  if DB.pruneIndex > table.getn(keys) then
    DB.pruneKeys = nil
    return true
  end
  return false
end

function DB.SizeText()
  local realm = DB.Realm()
  local items, priced, rows = 0, 0, 0
  for _ in pairs(TaxTheFoolsDB.items) do items = items + 1 end
  for _, e in pairs(realm.history) do
    priced = priced + 1
    for _ in pairs(e.days or {}) do rows = rows + 1 end
  end
  return items .. " items known, " .. priced .. " with price history, " .. rows .. " daily rows on " .. DB.realmName
end
