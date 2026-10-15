-- Right-click a bag item with our auction window open: search for it on Browse, select it on Sell.
-- It wraps FrameXML's ContainerFrameItemButton_OnClick and only ever searches or selects.
local U, DB, UI = TaxTheFools.Util, TaxTheFools.DB, TaxTheFools.UI
local Browse, SellUI = TaxTheFools.Browse, TaxTheFools.SellUI
local BagClick = { original = nil }
TaxTheFools.BagClick = BagClick

local function keyDown(f) return f and f() end

-- True when this click is ours to handle: setting on, right-click, no modifier, our window on Browse or Sell.
function BagClick.Wants(button)
  if not DB.S().bagClick then return false end
  if button ~= "RightButton" then return false end
  if keyDown(IsShiftKeyDown) or keyDown(IsControlKeyDown) or keyDown(IsAltKeyDown) then return false end
  local f = UI.ah
  if not f or not f:IsVisible() then return false end
  local sel = f.tabs.selected
  if sel ~= "browse" and sel ~= "sell" then return false end
  local page = UI.pages[sel]
  return (page and page:IsVisible()) and sel or false
end

-- Returns true when the click was consumed.
function BagClick.Handle(button, bag, slot)
  local tab = BagClick.Wants(button)
  if not tab then return false end
  local link = GetContainerItemLink(bag, slot)
  local key = U.keyFromLink(link)
  if not key then return false end
  if tab == "browse" then
    local name = U.linkName(link)
    if not name then return false end
    Browse.frame.search:SetText(name)
    Browse.Search(name, 0)
  else
    local it = SellUI.Find(key)
    if not it then
      SellUI.Refresh()        -- the grid may be a bag change behind
      it = SellUI.Find(key)
    end
    if it then SellUI.Select(it) else SellUI.Say("Can't auction that", "warn") end
  end
  return true
end

local function onClick(button, ignoreModifiers)
  local b = this
  button = button or arg1
  if b and button then
    local parent = b:GetParent()
    if parent and BagClick.Handle(button, parent:GetID(), b:GetID()) then return end
  end
  return BagClick.original(button, ignoreModifiers)
end

-- Safe to call twice: the second call finds the wrapper already in place.
function BagClick.Install()
  if BagClick.original then return end
  local orig = getglobal("ContainerFrameItemButton_OnClick")
  if not orig then return end
  BagClick.original = orig
  setglobal("ContainerFrameItemButton_OnClick", onClick)
end
