TaxTheFools = TaxTheFools or {}
local U, Recipes = TaxTheFools.Util, TaxTheFools.Recipes
local RL = { dirty = false, patIds = nil }
TaxTheFools.RecipesLearn = RL

-- Learning in game. Read only and merge only: nothing here buys, learns or changes a filter,
-- and nothing seen is removed by a later read that shows less.

local PROFESSIONS = {
  Alchemy = true, Blacksmithing = true, Cooking = true, Enchanting = true, Engineering = true,
  ["First Aid"] = true, Leatherworking = true, Mining = true, Tailoring = true, Herbalism = true,
  Skinning = true, Fishing = true, Poisons = true,
}

function RL.ResetState() RL.dirty = false RL.patIds = nil end

local function bucket(prof)
  local db = TaxTheFoolsDB
  db.recipes = db.recipes or {}
  local b = db.recipes[prof]
  if not b then b = {} db.recipes[prof] = b end
  b.trainer = b.trainer or {}
  b.seen = b.seen or {}
  return b
end

-- TRAINER_SHOW / TRAINER_UPDATE (through Core.Safe): mark dirty only.
function RL.OnTrainer() RL.dirty = true end

function RL.ReadTrainer()
  local n = GetNumTrainerServices() or 0
  for i = 1, n do
    local name, _, category = GetTrainerServiceInfo(i)
    if name and category ~= "header" then
      local skillName, skillRank = GetTrainerServiceSkillReq(i)
      if skillName and PROFESSIONS[skillName] then
        local cost = GetTrainerServiceCost(i)
        bucket(skillName).trainer[name] = { c = cost or 0, s = skillRank or 0, at = time() }
      end
    end
  end
end

-- Every frame (through Core.Safe): at most one read, however many events came in.
function RL.Tick()
  if not RL.dirty then return end
  RL.dirty = false
  RL.ReadTrainer()
end

-- Pattern ids with a recipe in the built-in data or already seen; built once, kept current.
local function patternIds()
  if RL.patIds then return RL.patIds end
  local set = {}
  for _, recs in pairs(TaxTheFools.RecipeData or {}) do
    for _, d in pairs(recs) do
      for _, p in ipairs(d.pat or {}) do set[p] = true end
    end
  end
  for _, b in pairs((TaxTheFoolsDB and TaxTheFoolsDB.recipes) or {}) do
    for id in pairs(b.seen or {}) do set[tonumber(id) or id] = true end
  end
  RL.patIds = set
  return set
end

local function tipLines(tt)
  local out = {}
  local name = tt.GetName and tt:GetName()
  if not name then return out end
  for i = 1, tt:NumLines() do
    local fs = getglobal(name .. "TextLeft" .. i)
    local t = fs and fs:GetText()
    if t then table.insert(out, t) end
  end
  return out
end

-- Called from Tip.Add with the tooltip and the item link. Learns, never displays.
function RL.FromTooltip(tt, link)
  if not link or not TaxTheFoolsDB or not tt then return end
  local _, id = U.keyFromLink(link)
  if not id or patternIds()[id] then return end
  local name, _, _, _, itemType = GetItemInfo(id)
  if not name or not Recipes.IsPattern(name, itemType) then return end
  local p = Recipes.ParseTip(tipLines(tt))
  if not p then return end
  bucket(p.prof).seen[id] = { n = p.name, skill = p.skill, r = p.reagents, at = time() }
  patternIds()[id] = true
end
