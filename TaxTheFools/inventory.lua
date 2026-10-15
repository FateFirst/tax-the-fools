TaxTheFools = TaxTheFools or {}
local U, DB = TaxTheFools.Util, TaxTheFools.DB
local Inv = { bankOpen = false, bagsDirty = false, bankDirty = false, scannedAt = -1000 }
TaxTheFools.Inventory = Inv

Inv.BAGS = { 0, 1, 2, 3, 4 }
Inv.BANK = { -1, 5, 6, 7, 8, 9, 10 }   -- the bank's own slots, then its bag slots
Inv.THROTTLE = 1                        -- seconds between counts; BAG_UPDATE comes in bursts

function Inv.ResetState()
  Inv.bankOpen, Inv.bagsDirty, Inv.bankDirty, Inv.scannedAt = false, false, false, -1000
end

function Inv.Count(bags)
  local counts = {}
  for _, bag in ipairs(bags) do
    for slot = 1, GetContainerNumSlots(bag) do
      local key = U.keyFromLink(GetContainerItemLink(bag, slot))
      if key then
        local _, n = GetContainerItemInfo(bag, slot)
        counts[key] = (counts[key] or 0) + (n or 1)
      end
    end
  end
  return counts
end

-- What is held changes every profit on the Crafting page; it repaints only if
-- visible. ui_craft.lua loads after this file: look it up at call time.
function Inv.Changed()
  if TaxTheFools.CraftUI then TaxTheFools.CraftUI.RefreshAll() end
  if TaxTheFools.SellUI then TaxTheFools.SellUI.OnBags() end
end

function Inv.ScanBags()
  local c = DB.Char()
  c.bags, c.bagsAt = Inv.Count(Inv.BAGS), time()
  Inv.Changed()
end

-- The bank can only be read while its window is open; closed, it reads as
-- empty, and recording that would wipe what is really there.
function Inv.ScanBank()
  if not Inv.bankOpen then return end
  local c = DB.Char()
  c.bank, c.bankAt = Inv.Count(Inv.BANK), time()
  Inv.Changed()
end

function Inv.OnEvent(e)
  if e == "BANKFRAME_OPENED" then
    Inv.bankOpen = true
    Inv.ScanBank()
  elseif e == "BANKFRAME_CLOSED" then
    Inv.bankOpen, Inv.bankDirty = false, false
  elseif e == "PLAYERBANKSLOTS_CHANGED" then
    if Inv.bankOpen then Inv.bankDirty = true end
  elseif e == "BAG_UPDATE" then
    Inv.bagsDirty = true
    if Inv.bankOpen then Inv.bankDirty = true end
  elseif e == "PLAYER_ENTERING_WORLD" then
    Inv.bagsDirty = true
  end
end

function Inv.Tick(now)
  if not Inv.bagsDirty and not Inv.bankDirty then return end
  if now - Inv.scannedAt < Inv.THROTTLE then return end
  Inv.scannedAt = now
  if Inv.bagsDirty then
    Inv.bagsDirty = false
    Inv.ScanBags()
  end
  if Inv.bankDirty then
    Inv.bankDirty = false
    Inv.ScanBank()
  end
end

local function add(held, counts)
  for key, n in pairs(counts or {}) do held[key] = (held[key] or 0) + n end
end

-- Everything every character on the realm holds, bags and bank together.
function Inv.Held(realm)
  local held = {}
  for _, c in pairs(realm.chars or {}) do
    add(held, c.bags)
    add(held, c.bank)
  end
  return held
end
