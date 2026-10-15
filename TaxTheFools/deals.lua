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
