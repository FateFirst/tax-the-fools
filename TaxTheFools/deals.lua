TaxTheFools = TaxTheFools or {}
local U, D, Craft = TaxTheFools.Util, TaxTheFools.Data, TaxTheFools.Craft
local Deals = {}
TaxTheFools.Deals = Deals

-- Pure: the snapshot, the evaluation context and the settings arrive as arguments. No game calls here.

local function candidate(best, deal)
  if not best or deal.profit > best.profit then return deal end
  return best
end

-- Profit of buying this stack of reagents and crafting with it, against buying the
-- reagent at its usual cost: the best recipe's gain per craft x the crafts the stack covers.
-- Recipes by reagent, built once per context (ctx.recipes is keyed by product).
local function usedIn(ctx)
  if not ctx.byReagent then
    local by = {}
    for _, list in pairs(ctx.recipes) do
      for _, r in ipairs(list) do
        for _, g in ipairs(r.reagents or {}) do
          if g.item then
            by[g.item] = by[g.item] or {}
            local l = by[g.item]
            if l[table.getn(l)] ~= r then table.insert(l, r) end
          end
        end
      end
    end
    ctx.byReagent = by
  end
  return ctx.byReagent
end

local function matsDeal(key, count, unit, ctx)
  local bestProfit, bestName = nil, nil
  for _, r in ipairs(usedIn(ctx)[key] or {}) do
    local need = 0
    for _, g in ipairs(r.reagents or {}) do
      if g.item == key then need = need + (g.count or 1) end
    end
    if need > 0 then
      local crafts = math.floor(count / need)
      if crafts > 0 then
        local old = Craft.Evaluate(r, ctx)
        -- the what-if changes every cost that depends on this reagent, so it gets its own memo
        local memo = ctx.memo
        ctx.memo = {}
        ctx.override = { [key] = unit }
        local new = Craft.Evaluate(r, ctx)
        ctx.override = nil
        ctx.memo = memo
        if old.profit and new.profit then
          local profit = (new.profit - old.profit) * crafts
          if not bestProfit or profit > bestProfit then
            bestProfit = profit
            bestName = r.name or (r.item and U.keyId(r.item) and ("Unknown item #" .. U.keyId(r.item))) or "Unknown recipe"
          end
        end
      end
    end
  end
  return bestProfit, bestName
end

-- The best deal one listing makes, or nil. Overlaps resolve to the highest profit.
function Deals.ListingProfit(key, count, buyout, ctx, s)
  if not count or count < 1 or not buyout or buyout <= 0 then return nil end
  local unit = buyout / count
  local m = ctx.market[key]
  local rec = ctx.items[U.keyId(key)]
  local sell = rec and rec.v
  local mv = m and m.v
  local minProfit = s.minProfit or 0
  local function make(kind, profit, recipe, unknown)
    local d = { key = key, count = count, buyout = buyout, unit = unit, market = mv, type = kind,
                profit = profit, recipe = recipe, depositUnknown = unknown or false }
    if mv and mv > 0 then d.pct = unit / mv * 100 end
    return d
  end
  local best = nil

  if s.market and mv and mv > 0 and (m.conf or 0) >= (s.minConfidence or 0)
     and buyout * 100 <= (s.belowMarketPct or 70) * count * mv then
    local deposit, unknown = 0, true
    if sell then
      deposit = Craft.Deposit(sell, rec.st, count, D.DEPOSIT_MINUTES, 1)
      unknown = false
    end
    local profit = count * mv * (1 - D.AH_CUT) - buyout - deposit
    if profit >= minProfit then best = candidate(best, make("market", profit, nil, unknown)) end
  end

  if s.vendor and sell and buyout < count * sell then
    local profit = count * sell - buyout
    if profit >= 1 then best = candidate(best, make("vendor", profit)) end
  end

  if s.mats and mv and mv > 0 and usedIn(ctx)[key]
     and buyout * 100 <= (s.matPct or 85) * count * mv then
    local profit, name = matsDeal(key, count, unit, ctx)
    if profit and profit >= minProfit and profit > 0 then best = candidate(best, make("mats", profit, name)) end
  end
  return best
end

-- Every deal in the snapshot, best profit first. Your own listings never count.
function Deals.Find(snapshot, ctx, s, me)
  local out = {}
  if not snapshot or not snapshot.rows then return out end
  for key, list in pairs(snapshot.rows) do
    for _, row in ipairs(list) do
      local count, buyout, _, owner = TaxTheFools.Scan.ParseSnapRow(row)  -- scan.lua loads after this file
      if count and not (me and owner and owner == me) then
        local deal = Deals.ListingProfit(key, count, buyout, ctx, s)
        if deal then
          deal.owner = owner
          table.insert(out, deal)
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.profit ~= b.profit then return a.profit > b.profit end
    if a.key ~= b.key then return a.key < b.key end
    return a.buyout < b.buyout
  end)
  return out
end

-- ---------- snipe list (phase 7 spec section 3) ----------
-- Pure. list = { [key] = { max = copper each } }. Every listing that is not yours, has a buyout and
-- costs at most max each is a deal; profit = (max - unit) x count.
function Deals.FindSnipes(snapshot, list, me, market)
  local out = {}
  if not snapshot or not snapshot.rows or not list then return out end
  for key, e in pairs(list) do
    for _, row in ipairs(snapshot.rows[key] or {}) do
      local count, buyout, _, owner = TaxTheFools.Scan.ParseSnapRow(row)
      if count and count > 0 and buyout and buyout > 0 and not (me and owner and owner == me) then
        local unit = buyout / count
        if e.max and unit <= e.max then
          local m = market and market[key]
          local mv = m and m.v
          table.insert(out, { type = "snipe", key = key, count = count, buyout = buyout, unit = unit,
                              max = e.max, owner = owner, profit = (e.max - unit) * count,
                              market = mv, pct = (mv and mv > 0) and (unit / mv * 100) or nil })
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.profit ~= b.profit then return a.profit > b.profit end
    if a.key ~= b.key then return a.key < b.key end
    return a.buyout < b.buyout
  end)
  return out
end

local function dealSig(d) return d.key .. "|" .. (d.count or 0) .. "|" .. (d.buyout or 0) .. "|" .. (d.owner or "") end

-- Pure. Appends the deals of extra whose (key, count, buyout, owner) primary does not already have, so a
-- listing is shown once, under the type in primary. Changes and returns primary.
function Deals.MergeOnce(primary, extra)
  local listed = {}
  for _, d in ipairs(primary) do listed[dealSig(d)] = true end
  for _, d in ipairs(extra or {}) do
    local sig = dealSig(d)
    if not listed[sig] then
      table.insert(primary, d)
    end
  end
  return primary
end

-- ---------- undersupplied (phase 4 spec section 4) ----------
-- Pure: inp = { stats = { rate, n }, count = listings today, median = median listing count over
-- the last 30 days, held, market, lowest = lowest unit price listed now }.
-- Undersupplied: sells (rate >= 0.5 over n >= 3 results), little is listed (count at most underPct%
-- of the median), and you hold some. suggest = floor(max(market, lowest) x premiumPct/100).
function Deals.Under(key, inp, s)
  if not s.under then return nil end
  local st = inp.stats
  if not st or not st.rate or st.rate < 0.5 or (st.n or 0) < 3 then return nil end
  if not inp.median or inp.median <= 0 or not inp.count then return nil end
  if inp.count * 100 > (s.underPct or 33) * inp.median then return nil end
  if not inp.held or inp.held < 1 then return nil end
  local base = inp.market
  if inp.lowest and (not base or inp.lowest > base) then base = inp.lowest end
  if not base or base <= 0 then return nil end
  local suggest = math.floor(base * (s.premiumPct or 110) / 100)
  local mv = inp.market
  return { type = "under", key = key, held = inp.held, count = inp.held, suggest = suggest, unit = suggest,
           market = mv, profit = inp.held * suggest * (1 - D.AH_CUT) }
end

-- Every undersupplied deal among the items you hold, best profit first. src = { held = { [key] = n },
-- stats = function(key) -> Sales.Stats table, median = function(key) -> median listing count }.
function Deals.FindUnder(snapshot, ctx, s, src)
  local out = {}
  if not snapshot or not snapshot.rows or not s.under then return out end
  for key, held in pairs(src.held or {}) do
    local rows = snapshot.rows[key] or {}
    local lowest = nil
    for _, row in ipairs(rows) do
      local count, buyout = TaxTheFools.Scan.ParseSnapRow(row)
      if count and count > 0 and buyout and buyout > 0 then
        local unit = buyout / count
        if not lowest or unit < lowest then lowest = unit end
      end
    end
    local m = ctx.market[key]
    local deal = Deals.Under(key, { stats = src.stats(key), count = table.getn(rows), median = src.median(key),
                                    held = held, market = m and m.v, lowest = lowest }, s)
    if deal then table.insert(out, deal) end
  end
  table.sort(out, function(a, b)
    if a.profit ~= b.profit then return a.profit > b.profit end
    return a.key < b.key
  end)
  return out
end

-- ---------- recipe deals (phase 5a spec section 5) ----------
-- Pure. src = { indexes = { { prof, index = Recipes.PatternIndex(...) } }, chars = realm characters,
-- skillAhead = number }. A listing is a deal when it is a pattern someone on the realm can learn and
-- it pays back within s.paybackCrafts crafts; profit = perCraft x paybackCrafts - buyout.
function Deals.FindRecipes(snapshot, ctx, s, me, src)
  local out = {}
  if not snapshot or not snapshot.rows or not s.recipe or not src then return out end
  local R = TaxTheFools.Recipes
  local limit, minProfit = s.paybackCrafts or 10, s.minProfit or 0
  local per, crafters = {}, {}
  for _, ix in ipairs(src.indexes or {}) do
    for key, entry in pairs(ix.index or {}) do
      local list = snapshot.rows[key]
      if list then
        local id = U.keyId(key)
        local vrec = ctx.items[id]
        local vendor = vrec and vrec.vb and vrec.vb > 0 and not vrec.vbLimited and vrec.vb or nil
        for _, row in ipairs(list) do
          local count, buyout, _, owner = TaxTheFools.Scan.ParseSnapRow(row)
          if count == 1 and buyout and buyout > 0 and not (me and owner and owner == me)
             and not (vendor and vendor < buyout) then
            if crafters[entry] == nil then
              crafters[entry] = R.Crafters(src.chars, ix.prof, entry, src.skillAhead)
              per[entry] = Craft.Evaluate(entry, ctx).profit or false
            end
            local who = crafters[entry]
            local perCraft = per[entry]
            if table.getn(who) > 0 and perCraft then
              local payback = R.Payback(buyout, perCraft)
              if type(payback) == "number" and payback <= limit then
                local profit = perCraft * limit - buyout
                if profit >= minProfit then
                  local m = ctx.market[key]
                  table.insert(out, { type = "recipe", key = key, count = 1, buyout = buyout, unit = buyout,
                                      market = m and m.v, crafter = who[1], recipe = entry.name, perCraft = perCraft,
                                      payback = payback, profit = profit, owner = owner })
                end
              end
            end
          end
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.profit ~= b.profit then return a.profit > b.profit end
    if a.key ~= b.key then return a.key < b.key end
    return a.buyout < b.buyout
  end)
  return out
end
