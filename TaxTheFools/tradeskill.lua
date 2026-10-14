TaxTheFools = TaxTheFools or {}
local U, DB, I = TaxTheFools.Util, TaxTheFools.DB, TaxTheFools.Items
local TS = { open = false, dirty = false, capturedAt = -1000 }
TaxTheFools.TradeSkill = TS

TS.THROTTLE = 0.5    -- seconds between captures; TRADE_SKILL_UPDATE fires in bursts

function TS.ResetState() TS.open, TS.dirty, TS.capturedAt = false, false, -1000 end

-- Every item seen in the window is remembered account-wide, so its name is
-- known to the watchlist scan and the Crafting page on every character.
local function remember(link, name, texture)
  local key, id = U.keyFromLink(link)
  if not key then return nil end
  I.Remember(id, name, nil, nil, texture)
  return key, id
end

-- One recipe row. A reagent whose link is not cached yet is kept by name
-- with no item key; the next capture fills it in.
function TS.ReadRecipe(i)
  local link = GetTradeSkillItemLink(i)
  local key, id = remember(link, U.linkName(link))
  if id then I.Vendor(id) end          -- ClassicAPI supplies the sell price the deposit needs
  local lo, hi = GetTradeSkillNumMade(i)
  if not lo or lo < 1 then lo = 1 end
  if not hi or hi < lo then hi = lo end
  local r = { item = key, yieldMin = lo, yieldMax = hi, reagents = {} }
  for n = 1, GetTradeSkillNumReagents(i) do
    local name, texture, count = GetTradeSkillReagentInfo(i, n)
    local rkey = remember(GetTradeSkillReagentItemLink(i, n), name, texture)
    table.insert(r.reagents, { item = rkey, name = name, count = count or 1 })
  end
  return r
end

-- Reads the open window into this character's professions. The recipe table
-- is replaced, so unlearned recipes go, with two exceptions that protect what
-- is stored: a list that reads empty (the client has not sent it yet) changes
-- nothing, and recipes hidden under a collapsed header are kept.
function TS.Capture()
  local line, rank, maxRank = GetTradeSkillLine()
  if not line or line == "UNKNOWN" then return nil end
  local recipes, found, collapsed = {}, 0, false
  for i = 1, GetNumTradeSkills() do
    local name, kind, _, expanded = GetTradeSkillInfo(i)
    if kind == "header" then
      if not expanded then collapsed = true end
    elseif name then
      local r = TS.ReadRecipe(i)
      r.color = kind
      recipes[name] = r
      found = found + 1
    end
  end
  if found == 0 then return nil end
  local c = DB.Char()
  c.professions = c.professions or {}
  local prof = c.professions[line]
  if not prof then
    prof = {}
    c.professions[line] = prof
  end
  if collapsed and prof.recipes then
    for name, r in pairs(prof.recipes) do
      if not recipes[name] then recipes[name] = r end
    end
  end
  prof.rank, prof.maxRank, prof.at, prof.recipes = rank, maxRank, time(), recipes
  if DB.S().craft.autoWatch then TS.Watch(recipes) end
  return prof
end

function TS.Watch(recipes)
  local watch = DB.Realm().watch
  for _, r in pairs(recipes) do
    if r.item then watch[r.item] = true end
    for _, g in ipairs(r.reagents) do
      if g.item then watch[g.item] = true end
    end
  end
end

function TS.OnEvent(e, now)
  if e == "TRADE_SKILL_SHOW" then
    TS.open, TS.dirty = true, true
    TS.Tick(now)
  elseif e == "TRADE_SKILL_UPDATE" then
    TS.dirty = true
  elseif e == "TRADE_SKILL_CLOSE" then
    TS.open, TS.dirty = false, false
  end
end

function TS.Tick(now)
  if not TS.open or not TS.dirty then return end
  if now - TS.capturedAt < TS.THROTTLE then return end
  TS.dirty, TS.capturedAt = false, now
  TS.Capture()
end
