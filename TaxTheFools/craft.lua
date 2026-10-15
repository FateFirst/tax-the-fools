TaxTheFools = TaxTheFools or {}
local U, D = TaxTheFools.Util, TaxTheFools.Data
local Craft = {}
TaxTheFools.Craft = Craft

-- Pure: every price, recipe and holding arrives in ctx. No game calls here.

-- Every captured recipe on the realm, from every character, by the item it makes.
function Craft.Index(chars)
  local by = {}
  for _, c in pairs(chars or {}) do
    for _, prof in pairs(c.professions or {}) do
      for _, r in pairs(prof.recipes or {}) do
        if r.item then
          local list = by[r.item]
          if not list then
            list = {}
            by[r.item] = list
          end
          table.insert(list, r)
        end
      end
    end
  end
  return by
end

-- One evaluation's worth of inputs. memo and busy live as long as the context:
-- build a fresh one whenever prices or holdings may have changed.
function Craft.Context(realm, items, held, today)
  return { market = realm.market or {}, items = items or {}, recipes = Craft.Index(realm.chars),
           held = held or {}, today = today, memo = {}, busy = {}, cuts = 0 }
end

-- Turtle's deposit (parent spec §7):
-- floor(vendorUnit × stack × (minutes/120) × (1 + (maxStack − stack) × 0.05) × 0.025) × stacks
function Craft.Deposit(vendorUnit, maxStack, stack, minutes, stacks)
  stack = stack or 1
  maxStack = maxStack or stack
  if maxStack < stack then maxStack = stack end
  return math.floor(vendorUnit * stack * (minutes / 120) * (1 + (maxStack - stack) * 0.05) * 0.025) * (stacks or 1)
end

function Craft.Yield(recipe)
  local lo = recipe.yieldMin or 1
  local hi = recipe.yieldMax or lo
  local y = (lo + hi) / 2
  if y <= 0 then y = 1 end
  return y
end

local function record(ctx, key) return ctx.items[U.keyId(key)] end

local function older(a, b)
  if a == nil then return b end
  if b == nil then return a end
  if b < a then return b end
  return a
end

-- The cheaper of the market value and a vendor's buy price. A vendor price
-- has no age; a market value is as old as the newest scan row behind it.
function Craft.BuyPrice(key, ctx)
  local m = ctx.market[key]
  local rec = record(ctx, key)
  local ah = m and m.v
  local vb = rec and rec.vb
  if vb and (not ah or vb <= ah) then return vb, "vendor", nil end
  if ah then return ah, "ah", m.lowDay end
  return nil
end

-- One craft's materials over the average yield; nil if any material has no price.
local function perUnit(recipe, ctx, depth)
  local total, day = 0, nil
  for _, g in ipairs(recipe.reagents or {}) do
    if not g.item then return nil end
    local c, _, d = Craft.UnitCost(g.item, ctx, depth + 1)
    if not c then return nil end
    total = total + c * (g.count or 1)
    day = older(day, d)
  end
  return total / Craft.Yield(recipe), day
end

-- cost, source ("ah" | "vendor" | "craft" | nil), day (oldest price day behind it).
-- A result is only memoised when no cycle guard or depth limit cut it short:
-- the same item reached by a shorter path may cost less.
function Craft.UnitCost(key, ctx, depth)
  depth = depth or 0
  -- A what-if price (Deals): ctx.override = { [key] = unit } wins over everything.
  local ov = ctx.override and ctx.override[key]
  if ov then return ov, "ah", nil end
  local memo = ctx.memo[key]
  if memo then return memo.cost, memo.source, memo.day end
  if ctx.busy[key] then
    ctx.cuts = ctx.cuts + 1
    return nil
  end
  local cutsBefore = ctx.cuts
  local cost, source, day = Craft.BuyPrice(key, ctx)
  local recipes = ctx.recipes[key]
  if recipes then
    if depth >= D.CRAFT_DEPTH then
      ctx.cuts = ctx.cuts + 1
    else
      ctx.busy[key] = true
      for _, r in ipairs(recipes) do
        local c, d = perUnit(r, ctx, depth)
        if c and (not cost or c < cost) then cost, source, day = c, "craft", d end
      end
      ctx.busy[key] = nil
    end
  end
  if ctx.cuts == cutsBefore then ctx.memo[key] = { cost = cost, source = source, day = day } end
  return cost, source, day
end

-- Buy against craft for one material, for the detail pane. Costing never reads this: UnitCost
-- already takes the cheaper. { buy, buySource, buyDay } is the AH or vendor price; { craft,
-- craftDay, recipe } the cheapest per-unit cost over its known recipes and the recipe giving it.
-- Fields are nil when unknown. A busy item (a cycle) or one at the depth limit only has a buy side.
function Craft.Options(key, ctx, depth)
  depth = depth or 0
  local o = {}
  local ov = ctx.override and ctx.override[key]
  if ov then
    o.buy, o.buySource = ov, "ah"
    return o
  end
  o.buy, o.buySource, o.buyDay = Craft.BuyPrice(key, ctx)
  local recipes = ctx.recipes[key]
  if recipes and depth < D.CRAFT_DEPTH and not ctx.busy[key] then
    ctx.busy[key] = true
    for _, r in ipairs(recipes) do
      local c, d = perUnit(r, ctx, depth)
      if c and (not o.craft or c < o.craft) then o.craft, o.craftDay, o.recipe = c, d, r end
    end
    ctx.busy[key] = nil
  end
  return o
end

local function nameOf(ctx, key, fallback)
  local rec = key and record(ctx, key)
  if rec and rec.n then return rec.n end
  if fallback then return fallback end
  if key then return "Unknown item #" .. tostring(U.keyId(key)) end
  return "Unknown item"
end

-- The reagents of the recipe that makes `key` (the cheapest known, else the first), scaled to
-- `need` units of it. need is fractional: need x count / yieldMin, the whole crafts' worth at the
-- smallest yield, so it never understates what is used. Show it rounded up.
local function subLines(key, need, options, ctx)
  local recipe = options.recipe or ctx.recipes[key][1]
  local out = {}
  local y = recipe.yieldMin or 1
  if y <= 0 then y = 1 end
  for _, g in ipairs(recipe.reagents or {}) do
    local s = { item = g.item, name = nameOf(ctx, g.item, g.name), need = need * (g.count or 1) / y }
    if g.item then s.unit, s.source = Craft.UnitCost(g.item, ctx, 1) end
    table.insert(out, s)
  end
  return out
end

-- Cost, value, profit and cash profit of one craft. Never guesses: with any
-- price missing, profit and cash are nil and missing names the items. With `detail`, a material
-- that has recipes also gets line.options (buy against craft) and line.sub (its reagents); that is
-- extra work, so only the detail pane of the selected recipe asks for it.
function Craft.Evaluate(recipe, ctx, detail)
  local ev = { missing = {}, lines = {} }
  local y = Craft.Yield(recipe)
  local product = recipe.item
  if product then ctx.busy[product] = true end
  local cost, cash, priced = 0, 0, true
  for _, g in ipairs(recipe.reagents or {}) do
    local line = { item = g.item, name = nameOf(ctx, g.item, g.name), need = g.count or 1, have = 0 }
    if g.item then
      line.have = ctx.held[g.item] or 0
      line.unit, line.source, line.day = Craft.UnitCost(g.item, ctx, 0)
      local rec = record(ctx, g.item)
      if line.source == "vendor" and rec and rec.vbLimited then line.limited = true end
      if detail and ctx.recipes[g.item] then
        line.options = Craft.Options(g.item, ctx, 0)
        line.sub = subLines(g.item, line.need, line.options, ctx)
      end
    end
    if line.unit then
      cost = cost + line.unit * line.need
      local buy = line.need - line.have
      if buy < 0 then buy = 0 end
      cash = cash + buy * line.unit
      ev.oldest = older(ev.oldest, line.day)
    else
      priced = false
      table.insert(ev.missing, line.name)
    end
    table.insert(ev.lines, line)
  end
  if product then ctx.busy[product] = nil end
  if priced then ev.cost = cost end

  local m = product and ctx.market[product]
  local rec = product and record(ctx, product)
  local sell = rec and rec.v
  if m and m.v then
    local deposit = 0
    if sell then deposit = Craft.Deposit(sell, rec.st, 1, D.DEPOSIT_MINUTES, 1)
    else ev.depositUnknown = true end
    ev.value = m.v * y * (1 - D.AH_CUT) - deposit * y
    ev.valueSource = "ah"
    ev.oldest = older(ev.oldest, m.lowDay)
  elseif sell then
    ev.value = sell * y
    ev.valueSource = "vendor"
  else
    table.insert(ev.missing, nameOf(ctx, product))
  end

  if priced and ev.value then
    ev.profit = ev.value - cost
    ev.cash = ev.value - cash
  end
  return ev
end
