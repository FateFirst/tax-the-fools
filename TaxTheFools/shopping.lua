TaxTheFools = TaxTheFools or {}
local U, D, Craft = TaxTheFools.Util, TaxTheFools.Data, TaxTheFools.Craft
local Shopping = {}
TaxTheFools.Shopping = Shopping

-- Pure: prices, recipes and holdings all arrive in ctx and `held`. No game calls here.

local function nameOf(ctx, key, fallback)
  local rec = ctx.items[U.keyId(key)]
  if rec and rec.n then return rec.n end
  if fallback then return fallback end
  return "Unknown item #" .. tostring(U.keyId(key))
end

local function addLine(st, bucket, key, name, qty)
  local line = st.index[bucket][key]
  if line then
    line.qty = line.qty + qty
  else
    line = { key = key, name = name, qty = qty }
    st.index[bucket][key] = line
    table.insert(st[bucket], line)
  end
  return line
end

-- Supply `qty` of `key`: holdings first, then craft (expanding) or buy, whichever Craft.Options
-- says is cheaper. `path` holds the items being crafted above this one (cycle guard).
local function need(st, key, name, qty, depth, path)
  local have = st.held[key] or 0
  if have > 0 then
    local use = have
    if use > qty then use = qty end
    st.held[key] = have - use
    qty = qty - use
  end
  if qty <= 0 then return end
  name = nameOf(st.ctx, key, name)
  local o = Craft.Options(key, st.ctx, depth)
  local canCraft = o.recipe and o.craft and depth < D.CRAFT_DEPTH and not path[key]
  if canCraft and (not o.buy or o.craft < o.buy) then
    -- Crafts needed = ceil(qty / yieldMin): the smallest yield, so we never buy too little.
    local ymin = o.recipe.yieldMin or 1
    if ymin <= 0 then ymin = 1 end
    local crafts = math.ceil(qty / ymin)
    addLine(st, "crafts", key, name, crafts)
    path[key] = true
    for _, g in ipairs(o.recipe.reagents or {}) do
      if g.item then need(st, g.item, g.name, crafts * (g.count or 1), depth + 1, path) end
    end
    path[key] = nil
  elseif o.buy then
    local line = addLine(st, "buys", key, name, qty)
    line.unit, line.source = o.buy, o.buySource
  else
    st.missingSet[name] = true
  end
end

-- The shopping list for `n` crafts of `recipe`, after what is held (a working copy; the
-- caller's table is untouched). Returns { buys = { { key, name, qty, unit, source, total } },
-- crafts = { { key, name, qty } }, total, missing = { names } }; buys sorted by total, descending.
function Shopping.Plan(recipe, n, ctx, held)
  local st = { ctx = ctx, held = {}, buys = {}, crafts = {}, index = { buys = {}, crafts = {} },
               missingSet = {} }
  for k, v in pairs(held or {}) do st.held[k] = v end
  local path = {}
  if recipe.item then path[recipe.item] = true end
  for _, g in ipairs(recipe.reagents or {}) do
    if g.item then need(st, g.item, g.name, n * (g.count or 1), 0, path) end
  end
  local total = 0
  for _, b in ipairs(st.buys) do
    b.total = b.unit * b.qty
    total = total + b.total
  end
  table.sort(st.buys, function(a, b)
    if a.total ~= b.total then return a.total > b.total end
    return a.name < b.name
  end)
  local missing = {}
  for name in pairs(st.missingSet) do table.insert(missing, name) end
  table.sort(missing)
  return { buys = st.buys, crafts = st.crafts, total = total, missing = missing }
end
