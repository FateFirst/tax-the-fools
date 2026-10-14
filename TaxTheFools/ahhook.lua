TaxTheFools = TaxTheFools or {}
local DB = TaxTheFools.DB
local AH = { open = false, keepOpen = false, pending = false, hooked = false, switching = false, window = nil }
TaxTheFools.AH = AH

function AH.ResetState()
  AH.open, AH.keepOpen, AH.pending, AH.switching = false, false, false, false
end

-- Blizzard's AuctionFrame calls CloseAuctionHouse() from its OnHide, and every
-- query after that is silently ignored. So its OnHide is wrapped to do nothing
-- while we are holding the session open behind our own window.
function AH.Hook()
  if AH.hooked or not AuctionFrame then return end
  AH.hooked = true
  local orig = AuctionFrame:GetScript("OnHide")
  AuctionFrame:SetScript("OnHide", function()
    if AH.keepOpen then return end
    if orig then orig() end
  end)
  -- Blizzard's own AUCTION_OWNED_LIST_UPDATE handler indexes this page counter.
  if AuctionFrameAuctions and type(AuctionFrameAuctions.page) ~= "number" then AuctionFrameAuctions.page = 0 end
  local b = CreateFrame("Button", "TaxTheFoolsBackButton", AuctionFrame, "UIPanelButtonTemplate")
  b:SetWidth(110)
  b:SetHeight(20)
  b:SetText("Tax the Fools")
  b:SetPoint("TOPRIGHT", AuctionFrame, "TOPRIGHT", -40, -14)
  b:SetScript("OnClick", function() AH.ShowOurs() end)
end

function AH.OnShow()
  AH.open = true
  if DB.S().replaceBlizzardAH then
    AH.pending = true
  elseif AuctionFrame then
    AH.Hook()
  end
end

-- AuctionFrame is loaded on demand and shown by Blizzard's own handler for the
-- same event; hiding it before then (or from inside its OnShow) closes the AH.
-- So the swap happens on the next frame.
function AH.Tick()
  if not AH.pending then return end
  AH.pending = false
  if not AuctionFrame then return end
  AH.Hook()
  AH.ShowOurs()
end

function AH.ShowOurs()
  AH.keepOpen = true
  if AuctionFrame and AuctionFrame:IsShown() then HideUIPanel(AuctionFrame) end
  if AH.window then AH.window:Show() end
end

function AH.ShowBlizzard()
  AH.switching = true
  if AH.window then AH.window:Hide() end
  AH.switching = false
  AH.keepOpen = false
  if AuctionFrame then ShowUIPanel(AuctionFrame) end
end

-- Our window's OnHide: closing it ends the visit, unless we are only switching windows.
function AH.OnWindowHidden()
  if AH.switching then return end
  AH.keepOpen = false
  if AH.open then
    AH.open = false
    CloseAuctionHouse()
  end
end

function AH.OnClosed()
  AH.open, AH.keepOpen, AH.pending = false, false, false
  TaxTheFools.Scan.Pause("closed")
  if AH.window and AH.window:IsShown() then AH.window:Hide() end
end
