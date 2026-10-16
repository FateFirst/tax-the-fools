TaxTheFools = TaxTheFools or {}
local Th, W, DB = TaxTheFools.Theme, TaxTheFools.Widgets, TaxTheFools.DB
local Mini = { RADIUS = 80, button = nil }
TaxTheFools.Minimap = Mini

-- math.* works in radians; WoW's global sin/cos take degrees. Use math.* only.
function Mini.Position(angle)
  local r = math.rad(angle)
  return math.cos(r) * Mini.RADIUS, math.sin(r) * Mini.RADIUS
end

function Mini.AngleFrom(cx, cy, mx, my)
  return math.deg(math.atan2(cy - my, cx - mx))
end

function Mini.Create()
  if Mini.button then return Mini.button end
  local b = CreateFrame("Button", "TaxTheFoolsMinimap", Minimap)
  b:SetWidth(28)
  b:SetHeight(28)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture(Th.MEDIA .. "circle")
  bg:SetAllPoints(b)
  Th.Tint(bg, "header")
  -- The goblin coin is full colour artwork, so it is never tinted.
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetTexture(Th.MEDIA .. "minimap")
  b.icon:SetWidth(24)
  b.icon:SetHeight(24)
  b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnClick", function() Mini.Click(arg1) end)
  b:SetScript("OnDragStart", function() this:SetScript("OnUpdate", function() Mini.DragUpdate() end) end)
  b:SetScript("OnDragStop", function() this:SetScript("OnUpdate", nil) end)
  W.Tip(b, "Tax the Fools", "Left-click: crafting profit. Right-click: options. Drag: move this button.")
  b:SetScript("OnEnter", function() W.ShowTip(this) end)
  b:SetScript("OnLeave", function() W.HideTip() end)
  Mini.button = b
  Mini.Refresh()
  return b
end

function Mini.Refresh()
  local b = Mini.button
  if not b then return end
  if DB.S().minimap then b:Show() else b:Hide() end
  local x, y = Mini.Position(DB.S().minimapAngle or 200)
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function Mini.DragUpdate()
  local mx, my = Minimap:GetCenter()
  local cx, cy = GetCursorPosition()
  local s = Minimap:GetEffectiveScale()
  DB.S().minimapAngle = Mini.AngleFrom(cx / s, cy / s, mx, my)
  DB.Touch()
  Mini.Refresh()
end

function Mini.Click(button)
  if button == "RightButton" then TaxTheFools.Options.Toggle() else TaxTheFools.CraftUI.Toggle() end
end
