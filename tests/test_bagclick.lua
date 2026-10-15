local A = TaxTheFools
local UI, AH, Scan, DB, Sell, BagClick = A.UI, A.AH, A.Scan, A.DB, A.Sell, A.BagClick
local Browse, SellUI = A.Browse, A.SellUI

local function openAH()
  UI.CreateAH()
  if UI.ah.tabs.selected then UI.ah.tabs:Select("browse") end
  AH.switching = true
  UI.ah:Hide()
  AH.switching = false
  AH.open = true
  AH.ShowOurs()
end

local function seed()
  WoW.items[14047] = { name = "Runecloth", stack = 20, quality = 1, tex = "rune" }
  WoW.bags[0] = { { id = 14047, name = "Runecloth", count = 20, vendor = 100 }, {}, {} }
  WoW.money = 1000000
end

local function btn(slot) return WoW.bagButton(0, slot or 1) end
local function click(b, mouse) WoW.clickBag(b, mouse or "RightButton") end
-- Scan.Browse queues the query; the next Tick sends it.
local function queries()
  WoW.clock = WoW.clock + 1
  Scan.Tick(WoW.clock)
  return T.count("QueryAuctionItems")
end

T.test("installing twice wraps once and the original runs once per pass-through click", function()
  BagClick.Install() BagClick.Install()
  seed() openAH()
  click(btn(), "LeftButton")
  T.eq(T.count("ContainerFrameItemButton_OnClick"), 1)
  T.ok(T.calledWith("ContainerFrameItemButton_OnClick LeftButton 0 1"))
end)

T.test("right-click on Browse puts the name in the search box and searches, without the original", function()
  seed() openAH()
  click(btn())
  T.eq(Browse.frame.search:GetText(), "Runecloth")
  T.eq(Browse.query, "Runecloth")
  queries()
  T.ok(T.calledWith("QueryAuctionItems [Runecloth]"))
  T.eq(T.count("ContainerFrameItemButton_OnClick"), 0)
end)

T.test("right-click on Sell selects the item, without the original or any auction call", function()
  seed() openAH()
  UI.ah.tabs:Select("sell")
  click(btn())
  T.ok(SellUI.frame.sel)
  T.eq(SellUI.frame.sel.key, "14047:0")
  T.eq(T.count("ContainerFrameItemButton_OnClick"), 0)
  T.eq(T.count("StartAuction"), 0) T.eq(T.count("CancelAuction"), 0) T.eq(T.count("SplitContainerItem"), 0)
  T.eq(T.count("PlaceAuctionBid"), 0) T.eq(T.count("UseContainerItem"), 0)
end)

T.test("right-click on Sell for an item that cannot be auctioned says so and still consumes the click", function()
  seed() openAH()
  UI.ah.tabs:Select("sell")
  local keep, soul = Sell.TipLines, getglobal("ITEM_SOULBOUND")
  setglobal("ITEM_SOULBOUND", "Soulbound")
  Sell.TipLines = function() return { "Runecloth", "Soulbound" } end
  SellUI.Refresh()
  click(btn())
  Sell.TipLines = keep
  setglobal("ITEM_SOULBOUND", soul)
  T.ok(not SellUI.frame.sel)
  T.eq(SellUI.frame.status:GetText(), "Can't auction that")
  T.eq(T.count("ContainerFrameItemButton_OnClick"), 0)
end)

T.test("an empty slot passes through", function()
  seed() openAH()
  click(btn(2))
  T.eq(T.count("ContainerFrameItemButton_OnClick"), 1)
  T.eq(queries(), 0)
end)

T.test("a left-click always passes through, on Browse and on Sell", function()
  seed() openAH()
  click(btn(), "LeftButton")
  UI.ah.tabs:Select("sell")
  click(btn(), "LeftButton")
  T.eq(T.count("ContainerFrameItemButton_OnClick"), 2)
  T.eq(queries(), 0)
  T.ok(not SellUI.frame.sel)
end)

T.test("a right-click passes through with the AH window hidden", function()
  seed() openAH()
  AH.switching = true UI.ah:Hide() AH.switching = false
  click(btn())
  T.eq(T.count("ContainerFrameItemButton_OnClick"), 1)
  T.ok(T.calledWith("ContainerFrameItemButton_OnClick RightButton 0 1"))
  T.eq(queries(), 0)
end)

T.test("a right-click passes through on another tab", function()
  seed() openAH()
  UI.ah.tabs:Select("deals")
  click(btn())
  T.eq(T.count("ContainerFrameItemButton_OnClick"), 1)
  T.eq(queries(), 0)
end)

T.test("a right-click passes through with Shift, Ctrl or Alt held", function()
  seed() openAH()
  WoW.shift = true click(btn()) WoW.shift = false
  WoW.ctrl = true click(btn()) WoW.ctrl = false
  WoW.alt = true click(btn()) WoW.alt = false
  T.eq(T.count("ContainerFrameItemButton_OnClick"), 3)
  T.eq(queries(), 0)
  UI.ah.tabs:Select("sell")
  WoW.shift = true click(btn()) WoW.shift = false
  T.eq(T.count("ContainerFrameItemButton_OnClick"), 4)
  T.ok(not SellUI.frame.sel)
end)

T.test("the setting is read at click time", function()
  seed() openAH()
  DB.S().bagClick = false
  click(btn())
  T.eq(T.count("ContainerFrameItemButton_OnClick"), 1)
  T.eq(queries(), 0)
  DB.S().bagClick = true
  click(btn())
  T.eq(T.count("ContainerFrameItemButton_OnClick"), 1)
  T.eq(queries(), 1)
end)

T.test("bagClick defaults to on", function()
  T.eq(A.Data.DEFAULTS.settings.bagClick, true)
end)
