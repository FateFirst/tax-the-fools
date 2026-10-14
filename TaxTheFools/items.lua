TaxTheFools = TaxTheFools or {}
local U = TaxTheFools.Util
local I = { requested = {}, tipMoney = false }
TaxTheFools.Items = I

function I.ResetState() I.requested = {} I.tipMoney = false end

function I.Get(id) return TaxTheFoolsDB.items[id] end

function I.Remember(id, name, quality, stack, texture)
  if not id then return nil end
  local rec = TaxTheFoolsDB.items[id]
  if not rec then
    rec = {}
    TaxTheFoolsDB.items[id] = rec
  end
  if name then rec.n = name end
  if quality then rec.q = quality end
  if stack then rec.st = stack end
  if texture then rec.t = texture end
  return rec
end

-- What the client knows about an item, remembered for every character.
-- GetItemInfo returns nothing for items this client has never seen; those
-- are requested from the server once per session.
function I.Resolve(id)
  local rec = TaxTheFoolsDB.items[id]
  if rec and rec.n and rec.st then return rec end
  local name, _, quality, _, _, _, stack, _, texture = GetItemInfo(id)
  if name then return I.Remember(id, name, quality, stack, texture) end
  I.Request(id)
  return rec
end

-- Only ever called for ids seen in the AH, bags or a link: asking the server
-- for an id that does not exist can disconnect a 1.12 client.
function I.Request(id)
  if I.requested[id] then return end
  I.requested[id] = true
  if C_Item and C_Item.RequestLoadItemDataByID then
    C_Item.RequestLoadItemDataByID(id)
    return
  end
  local tip = U.scanTip()
  tip:ClearLines()
  tip:SetHyperlink("item:" .. id .. ":0:0:0")
end

function I.Name(id)
  local rec = I.Resolve(id)
  return (rec and rec.n) or ("Unknown item #" .. tostring(id))
end

function I.Vendor(id)
  local rec = TaxTheFoolsDB.items[id]
  if rec and rec.v then return rec.v end
  if C_Item and C_Item.GetItemSellPrice then
    local v = C_Item.GetItemSellPrice(id)
    if v and v > 0 then
      I.Remember(id).v = v
      return v
    end
  end
  return nil
end

-- With a merchant open, the client prices every bag item on its tooltip and
-- reports the stack's value through OnTooltipAddMoney.
function I.LearnVendorPrices()
  local tip = U.scanTip()
  tip:SetScript("OnTooltipAddMoney", function() I.tipMoney = arg1 end)
  for bag = 0, 4 do
    for slot = 1, GetContainerNumSlots(bag) do
      local id = U.parseLink(GetContainerItemLink(bag, slot))
      if id then
        local _, count = GetContainerItemInfo(bag, slot)
        I.tipMoney = false
        tip:ClearLines()
        tip:SetBagItem(bag, slot)
        if I.tipMoney and count and count > 0 then
          I.Remember(id).v = math.floor(I.tipMoney / count + 0.5)
        end
      end
    end
  end
end

function I.FindByName(name)
  local want = string.lower(name or "")
  for id, rec in pairs(TaxTheFoolsDB.items) do
    if rec.n and string.lower(rec.n) == want then return id end
  end
  return nil
end
