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
  return lines
end

function Tip.Add(tt, link, count)
  if not link or not TaxTheFoolsDB then return end
  local key, id = U.keyFromLink(link)
  if not key then return end
  I.Resolve(id)
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
