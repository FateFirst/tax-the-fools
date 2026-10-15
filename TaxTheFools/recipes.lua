TaxTheFools = TaxTheFools or {}
local U = TaxTheFools.Util
local Recipes = {}
TaxTheFools.Recipes = Recipes

-- Pure recipe rules: every table arrives as an argument. No game calls, no saved-variable access.

local PREFIXES = { "Pattern: ", "Recipe: ", "Plans: ", "Schematic: ", "Formula: ", "Manual: " }

function Recipes.IsPattern(name, itemType)
  if itemType == "Recipe" then return true end
  name = name or ""
  for _, p in ipairs(PREFIXES) do
    if string.sub(name, 1, string.len(p)) == p then return true end
  end
  return false
end

local function nameIndex(items)
  local by = {}
  for id, rec in pairs(items or {}) do
    if rec.n then by[string.lower(rec.n)] = id end
  end
  return by
end

local function copyReagents(list)
  local out = {}
  for _, g in ipairs(list or {}) do
    table.insert(out, { item = g.item, name = g.name, count = g.count or 1 })
  end
  return out
end

-- One entry per recipe name, sorted by skill then name.
function Recipes.Catalogue(prof, data, learnedDb, realmChars, items)
  items = items or {}
  local byName, order = {}, {}
  local ids = nil
  local function add(e)
    local k = string.lower(e.name)
    byName[k] = e
    table.insert(order, e)
  end

  -- 1. built in
  for _, d in pairs((data and data[prof]) or {}) do
    local reagents = {}
    local r = d.r or {}
    local i = 1
    while r[i] do
      local rec = items[r[i]]
      table.insert(reagents, { item = U.key(r[i], 0), name = rec and rec.n or nil, count = r[i + 1] or 1 })
      i = i + 2
    end
    local pats, src = {}, {}
    for _, p in ipairs(d.pat or {}) do table.insert(pats, p) end
    for _, s in ipairs(d.src or {}) do table.insert(src, s) end
    add({ name = d.n, skill = d.skill, item = d.item and U.key(d.item, 0) or nil, yieldMin = 1, yieldMax = 1,
          reagents = reagents, pats = pats, src = src, turtle = d.turtle })
  end

  -- 2. seen in game, when not already built in
  local db = learnedDb and learnedDb[prof]
  for pid, s in pairs((db and db.seen) or {}) do
    if s.n and not byName[string.lower(s.n)] then
      ids = ids or nameIndex(items)
      local reagents = {}
      for _, g in ipairs(s.r or {}) do
        local id = ids[string.lower(g.name or "")]
        table.insert(reagents, { item = id and U.key(id, 0) or nil, name = g.name, count = g.count or 1 })
      end
      local pid2 = tonumber(pid)
      local product = ids[string.lower(s.n)]
      add({ name = s.n, skill = s.skill, item = product and U.key(product, 0) or nil, yieldMin = 1, yieldMax = 1,
            reagents = reagents, pats = pid2 and { pid2 } or {}, src = {} })
    end
  end

  -- 3. captured by any realm character: the game's own figures win
  local names = {}
  for n in pairs(realmChars or {}) do table.insert(names, n) end
  table.sort(names)
  local done = {}
  for _, cn in ipairs(names) do
    local p = realmChars[cn].professions and realmChars[cn].professions[prof]
    for rn, rec in pairs((p and p.recipes) or {}) do
      local k = string.lower(rn)
      if not done[k] then
        done[k] = true
        local e = byName[k]
        if not e and rec.item then
          for _, o in ipairs(order) do
            if o.item == rec.item then e = o break end
          end
        end
        if not e then
          e = { name = rn, skill = rec.skill, pats = {}, src = {} }
          add(e)
        end
        if rec.item then e.item = rec.item end
        e.yieldMin = rec.yieldMin or 1
        e.yieldMax = rec.yieldMax or e.yieldMin
        e.reagents = copyReagents(rec.reagents)
      end
    end
  end

  for _, e in ipairs(order) do
    local t = db and db.trainer and db.trainer[e.name]
    if t then e.trainer = { c = t.c, s = t.s } end
  end
  table.sort(order, function(a, b)
    local sa, sb = a.skill or 0, b.skill or 0
    if sa ~= sb then return sa < sb end
    return a.name < b.name
  end)
  return order
end

local function learned(char, entry, prof)
  local p = char and char.professions and char.professions[prof]
  if not p or not p.recipes then return false end
  if p.recipes[entry.name] then return true end
  if entry.item then
    for _, r in pairs(p.recipes) do
      if r.item == entry.item then return true end
    end
  end
  return false
end

function Recipes.Unlearned(catalogue, char, prof)
  local out = {}
  for _, e in ipairs(catalogue or {}) do
    if not learned(char, e, prof) then table.insert(out, e) end
  end
  return out
end

-- cost, source ("trainer" | "vendor" | "ah" | nil), limited
function Recipes.Cost(entry, ctx, snapshot)
  local best, source, limited = nil, nil, nil
  if entry.trainer and entry.trainer.c then best, source = entry.trainer.c, "trainer" end
  local items = ctx and ctx.items or {}
  for _, id in ipairs(entry.pats or {}) do
    local rec = items[id]
    if rec and rec.vb and rec.vb > 0 and (not best or rec.vb < best) then
      best, source, limited = rec.vb, "vendor", rec.vbLimited and true or nil
    end
  end
  for _, id in ipairs(entry.pats or {}) do
    local key = U.key(id, 0)
    local price = nil
    for _, row in ipairs((snapshot and snapshot.rows and snapshot.rows[key]) or {}) do
      local count, buyout = TaxTheFools.Scan.ParseSnapRow(row)  -- scan.lua loads after this file
      if count and count > 0 and buyout and buyout > 0 then
        local unit = buyout / count
        if not price or unit < price then price = unit end
      end
    end
    if not price then
      local m = ctx and ctx.market and ctx.market[key]
      price = m and m.v
    end
    if price and (not best or price < best) then best, source, limited = price, "ah", nil end
  end
  return best, source, limited
end

function Recipes.Payback(cost, profit)
  if cost == nil then return nil end
  if cost == 0 then return 0 end
  if profit == nil or profit <= 0 then return "never" end
  local n = math.ceil(cost / profit)
  if n < 1 then n = 1 end
  return n
end

function Recipes.PatternIndex(catalogue)
  local by = {}
  for _, e in ipairs(catalogue or {}) do
    for _, id in ipairs(e.pats or {}) do by[U.key(id, 0)] = e end
  end
  return by
end

function Recipes.Crafters(realmChars, prof, entry, skillAhead)
  local out = {}
  for name, c in pairs(realmChars or {}) do
    local p = c.professions and c.professions[prof]
    if p and not learned(c, entry, prof) and (p.rank or 0) + (skillAhead or 0) >= (entry.skill or 0) then
      table.insert(out, name)
    end
  end
  table.sort(out)
  return out
end

-- The 1.12 recipe tooltip: "Requires <Prof> (<n>)", "Teaches you how to make a <Name>.",
-- then "Requires Reagent (n), Reagent".
function Recipes.ParseTip(lines)
  local prof, skill, name, reagentLine
  local seenProf = false
  for _, line in ipairs(lines or {}) do
    line = U.trim(line)
    local _, _, rest = string.find(line, "^Requires (.+)$")
    if rest then
      local _, _, p, n = string.find(rest, "^(.-) %((%d+)%)$")
      if not seenProf and p then
        prof, skill, seenProf = p, tonumber(n), true
      else
        reagentLine = rest
      end
    end
    if not name then
      local _, _, nm = string.find(line, "Teaches you how to %a+ (.-)%.?$")
      if nm then
        local _, _, rest2 = string.find(nm, "^an? (.+)$")
        name = rest2 or nm
      end
    end
  end
  if not prof or not name or not reagentLine then return nil end
  local reagents = {}
  local pos = 1
  while pos <= string.len(reagentLine) + 1 do
    local a = string.find(reagentLine, ", ", pos, true)
    local part = string.sub(reagentLine, pos, (a or string.len(reagentLine) + 1) - 1)
    local _, _, nm, c = string.find(part, "^(.-) %((%d+)%)$")
    if nm then table.insert(reagents, { name = nm, count = tonumber(c) })
    elseif part ~= "" then table.insert(reagents, { name = part, count = 1 }) end
    if not a then break end
    pos = a + 2
  end
  if table.getn(reagents) == 0 then return nil end
  return { prof = prof, skill = skill, name = name, reagents = reagents }
end
