TaxTheFools = TaxTheFools or {}
local U, DB, I, P, Th = TaxTheFools.Util, TaxTheFools.DB, TaxTheFools.Items, TaxTheFools.Price, TaxTheFools.Theme
local Tip = { hooked = false }
TaxTheFools.Tooltip = Tip

local CONF_TOKEN = { high = "good", medium = "warn", low = "bad" }

function Tip.Lines(key, count, now)
  local s = DB.S().tooltip
  local m = DB.Realm().market[key]
  local lines = {}
  count = (count and count > 1) and count or 1
  local mult = (IsShiftKeyDown() and count > 1) and count or 1
  local suffix = (mult > 1) and (" x" .. mult) or ""
  if s.market then
    if m and m.v then
      local label = P.ConfLabel(m.conf or 0)
      table.insert(lines, { "Market" .. suffix, U.money(m.v * mult) .. " " .. Th.Code(CONF_TOKEN[label]) .. "(" .. label .. ")|r" })
    else
      table.insert(lines, { "Market", "|cff888888no data|r" })
    end
  end
  if s.low and m and m.low and m.lowDay then
    table.insert(lines, { "Low now" .. suffix, U.money(m.low * mult) .. "  " .. U.daysAgo(U.day(now) - m.lowDay) })
  end
  if s.vendor then
    local v = I.Vendor(U.keyId(key))
    if v then table.insert(lines, { "Vendor" .. suffix, U.money(v * mult) }) end
  end
  local ss = DB.S().sales
  if ss and ss.tooltip then
    local st = TaxTheFools.Sales.Stats(DB.Realm().chars, key, ss.days or 30, now)
    if st.n > 0 then
      table.insert(lines, { "Sells", math.floor(st.rate * 100 + 0.5) .. "% (" .. st.n .. ")" })
    end
  end
  local ts = DB.S().trend
  if ts and ts.tooltip then
    local t = P.Trend(DB.Realm().history[key], U.day(now))
    if t then
      local token = P.TrendToken(t.dir)
      local sign = (t.pct > 0) and "+" or ""
      table.insert(lines, { "Trend 7d", Th.Code(token) .. sign .. t.pct .. "% " .. t.dir .. "|r" })
    end
  end
  local rs = DB.S().recipes
  if rs and rs.tooltip then
    local ok, text = pcall(Tip.RecipeLine, key)
    if ok and text then table.insert(lines, { "Recipe", text }) end
  end
  return lines
end

-- The payback line for a pattern item: "Pays back in 4 crafts (+1g 20s each)", "No profit per craft",
-- "Learned by Name", or nil when the item is no pattern or no price is known.
function Tip.RecipeLine(key)
  local CraftUI = TaxTheFools.CraftUI
  if not CraftUI then return nil end
  local entry = CraftUI.PatternEntry(key)
  if not entry then return nil end
  local R, realm = TaxTheFools.Recipes, DB.Realm()
  local rs = DB.S().recipes
  local crafters = R.Crafters(realm.chars, entry.prof, entry, rs.skillAhead or 0)
  if table.getn(crafters) == 0 then
    local names = {}
    for name, c in pairs(realm.chars or {}) do
      if c.professions and c.professions[entry.prof] and table.getn(R.Unlearned({ entry }, c, entry.prof)) == 0 then
        table.insert(names, name)
      end
    end
    if table.getn(names) == 0 then return nil end
    table.sort(names)
    return "Learned by " .. names[1]
  end
  local ctx = TaxTheFools.TradeSkill.Context()
  local cost = R.Cost(entry, ctx, realm.snapshot)
  if not cost then return nil end
  local ev = TaxTheFools.Craft.Evaluate(entry, ctx)
  if ev.profit == nil then return nil end
  local pb = R.Payback(math.floor(cost), ev.profit)
  if pb == "never" then return "No profit per craft" end
  local each = " (+" .. U.money(ev.profit, true) .. " each)"
  if pb == 0 then return "Free to learn" .. each end
  return "Pays back in " .. pb .. (pb == 1 and " craft" or " crafts") .. each
end

function Tip.Add(tt, link, count)
  if not link or not TaxTheFoolsDB then return end
  local key, id = U.keyFromLink(link)
  if not key then return end
  I.Resolve(id)
  -- Learning must never cost the price lines: an error here is swallowed.
  pcall(TaxTheFools.RecipesLearn.FromTooltip, tt, link)
  local lines = Tip.Lines(key, count, time())
  for _, l in ipairs(lines) do tt:AddDoubleLine(l[1], l[2], 0.78, 0.78, 0.74, 1, 1, 1) end
  if table.getn(lines) > 0 then tt:Show() end
end

-- Where each tooltip method's item comes from. The originals' return values
-- (SetBagItem returns cooldown and repair cost) are passed straight back.
Tip.SOURCES = {
  SetBagItem = function(bag, slot)
    local _, count = GetContainerItemInfo(bag, slot)
    return GetContainerItemLink(bag, slot), count
  end,
  SetInventoryItem = function(unit, slot) return GetInventoryItemLink(unit, slot), GetInventoryItemCount(unit, slot) end,
  SetAuctionItem = function(kind, i)
    local _, _, count = GetAuctionItemInfo(kind, i)
    return GetAuctionItemLink(kind, i), count
  end,
  SetMerchantItem = function(i)
    local _, _, _, qty = GetMerchantItemInfo(i)
    return GetMerchantItemLink(i), qty
  end,
  SetLootItem = function(i)
    local _, _, qty = GetLootSlotInfo(i)
    return GetLootSlotLink(i), qty
  end,
  SetTradeSkillItem = function(skill, reagent)
    if reagent then
      local _, _, count = GetTradeSkillReagentInfo(skill, reagent)
      return GetTradeSkillReagentItemLink(skill, reagent), count
    end
    return GetTradeSkillItemLink(skill), 1
  end,
  SetHyperlink = function(link) return link, 1 end,
}

local function wrap(name, source)
  local orig = GameTooltip[name]
  if type(orig) ~= "function" then return end
  GameTooltip[name] = function(self, a1, a2, a3)
    local r1, r2, r3 = orig(self, a1, a2, a3)
    local ok, err = pcall(function()
      local link, count = source(a1, a2, a3)
      Tip.Add(self, link, count)
    end)
    if not ok then U.debug("tooltip: " .. tostring(err)) end
    return r1, r2, r3
  end
end

function Tip.Hook()
  if Tip.hooked then return end
  Tip.hooked = true
  for name, source in pairs(Tip.SOURCES) do wrap(name, source) end
end
