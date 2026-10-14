local AH, Scan, DB = TaxTheFools.AH, TaxTheFools.Scan, TaxTheFools.DB

-- A stand-in for our window until the real one exists (Task 11).
local function fakeWindow()
  local w = CreateFrame("Frame", "TTFTestWindow", UIParent)
  w:Hide()
  w:SetScript("OnHide", function() AH.OnWindowHidden() end)
  return w
end

local function open()
  AuctionFrame:Show()          -- Blizzard shows its window when you talk to an auctioneer
  AH.OnShow()
  AH.Tick()                    -- the swap happens a frame later
end

T.test("opening the AH swaps in our window and keeps the session", function()
  local old = AH.window
  AH.window = fakeWindow()
  open()
  T.eq(AuctionFrame:IsShown(), false, "Blizzard's window hidden")
  T.ok(AH.window:IsShown(), "ours shown")
  T.ok(not T.calledWith("CloseAuctionHouse"), "session still open")
  AH.window = old
end)

T.test("the swap waits a frame: hiding during Blizzard's own OnShow would close the AH", function()
  local old = AH.window
  AH.window = fakeWindow()
  AuctionFrame:Show()
  AH.OnShow()
  T.ok(AuctionFrame:IsShown(), "nothing happens in the event itself")
  AH.Tick()
  T.eq(AuctionFrame:IsShown(), false)
  AH.window = old
end)

T.test("closing our window ends the session", function()
  local old = AH.window
  AH.window = fakeWindow()
  open()
  AH.window:Hide()
  T.ok(T.calledWith("CloseAuctionHouse"))
  AH.window = old
end)

T.test("switching to Blizzard's window and back keeps the session", function()
  local old = AH.window
  AH.window = fakeWindow()
  open()
  AH.ShowBlizzard()
  T.ok(AuctionFrame:IsShown()) T.eq(AH.window:IsShown(), false)
  AH.ShowOurs()
  T.eq(AuctionFrame:IsShown(), false) T.ok(AH.window:IsShown())
  T.ok(not T.calledWith("CloseAuctionHouse"))
  AH.window = old
end)

T.test("leaving the auctioneer pauses a running scan and hides our window", function()
  local old = AH.window
  AH.window = fakeWindow()
  open()
  table.insert(WoW.ah.listings, { id = 1, name = "x", count = 1, buyout = 5 })
  Scan.StartFull(0)
  AH.OnClosed()
  T.eq(Scan.job, nil)
  T.ok(DB.Realm().scan.resume, "progress saved")
  T.eq(AH.window:IsShown(), false)
  T.eq(AH.open, false)
  AH.window = old
end)

T.test("with replacement off, Blizzard's window is left alone", function()
  local old = AH.window
  AH.window = fakeWindow()
  DB.S().replaceBlizzardAH = false
  open()
  T.ok(AuctionFrame:IsShown())
  T.eq(AH.window:IsShown(), false)
  AH.window = old
end)

T.test("Blizzard's window gets a button back to ours", function()
  AH.Hook()
  T.ok(TaxTheFoolsBackButton, "button exists")
  T.eq(AuctionFrameAuctions.page, 0, "seeded so Blizzard's owner-list handler doesn't throw")
end)
