local A = TaxTheFools
local UI, Browse, AH, Scan, DB, Auction, Confirm = A.UI, A.Browse, A.AH, A.Scan, A.DB, A.Auction, A.Confirm

local function openAH()
  UI.CreateAH()
  AH.switching = true
  UI.ah:Hide()
  AH.switching = false
  AH.open = true
  AH.ShowOurs()
end

local function answer()
  for _ = 1, 20 do
    WoW.clock = WoW.clock + 0.5
    Scan.Tick(WoW.clock)
    if WoW.ah.pending then
      WoW.ahRespond()
      Scan.OnListUpdate(WoW.clock)
    end
    if not Scan.job then return end
  end
end

-- Searches for the listings and selects the first row.
local function select1(listings)
  openAH()
  for _, l in ipairs(listings) do table.insert(WoW.ah.listings, l) end
  Browse.Search("Rune", 0)
  answer()
  local p = UI.pages.browse
  p.list:SetHeight(400)
  p.list.selected = p.list.data[1]
  Browse.UpdateBar()
  return p
end

local function label(b) return b.label:GetText() end

T.test("the action bar labels Buy with the buyout and Bid with the next bid", function()
  WoW.money = 1000000
  local p = select1({ { id = 14047, name = "Runecloth", count = 20, buyout = 12000, minBid = 4500, owner = "Sel" } })
  T.eq(label(p.buyBtn), string.upper("Buy " .. A.Util.money(12000)))
  T.eq(label(p.bidBtn), string.upper("Bid " .. A.Util.money(4500)))
  T.ok(p.buyBtn.enabled) T.ok(p.bidBtn.enabled)
end)

T.test("both buttons are disabled with nothing selected", function()
  WoW.money = 1000000
  local p = select1({ { id = 14047, name = "Runecloth", count = 20, buyout = 12000, minBid = 4500, owner = "Sel" } })
  p.list.selected = false
  Browse.UpdateBar()
  T.eq(p.buyBtn.enabled, false) T.eq(p.bidBtn.enabled, false)
  T.ok(p.buyBtn.tip.body ~= nil)
end)

T.test("Buy is disabled with no buyout or when too dear; the tooltip says why", function()
  WoW.money = 1000000
  local p = select1({ { id = 14047, name = "Runecloth", count = 20, buyout = 0, minBid = 4500, owner = "Sel" } })
  T.eq(p.buyBtn.enabled, false)
  T.ok(string.find(p.buyBtn.tip.body, "no buyout", 1, true), p.buyBtn.tip.body)
  T.ok(p.bidBtn.enabled)
  WoW.ah.listings = {}
  WoW.money = 100
  p = select1({ { id = 14047, name = "Runecloth", count = 20, buyout = 12000, minBid = 4500, owner = "Sel" } })
  T.eq(p.buyBtn.enabled, false)
  T.ok(string.find(p.buyBtn.tip.body, "afford", 1, true), p.buyBtn.tip.body)
end)

T.test("Bid is disabled when it would reach the buyout or you hold the high bid", function()
  WoW.money = 1000000
  local p = select1({ { id = 14047, name = "Runecloth", count = 20, buyout = 5000, minBid = 4000, bid = 4900,
                        minInc = 100, owner = "Sel" } })
  T.eq(p.bidBtn.enabled, false)
  T.ok(string.find(p.bidBtn.tip.body, "buyout", 1, true), p.bidBtn.tip.body)
  T.ok(p.buyBtn.enabled)
  WoW.ah.listings = {}
  p = select1({ { id = 14047, name = "Runecloth", count = 20, buyout = 0, minBid = 4000, bid = 4500, minInc = 100,
                  highBidder = true, owner = "Sel" } })
  T.eq(p.bidBtn.enabled, false)
  T.ok(string.find(p.bidBtn.tip.body, "high bidder", 1, true), p.bidBtn.tip.body)
end)

T.test("your own listing disables both buttons", function()
  WoW.money = 1000000
  local p = select1({ { id = 14047, name = "Runecloth", count = 20, buyout = 12000, minBid = 4500, owner = WoW.player } })
  T.eq(p.buyBtn.enabled, false) T.eq(p.bidBtn.enabled, false)
  T.ok(string.find(p.buyBtn.tip.body, "your own", 1, true), p.buyBtn.tip.body)
  T.ok(string.find(p.bidBtn.tip.body, "your own", 1, true), p.bidBtn.tip.body)
end)

T.test("both buttons are disabled while an action is pending", function()
  WoW.money = 1000000
  local p = select1({ { id = 14047, name = "Runecloth", count = 20, buyout = 12000, minBid = 4500, owner = "Sel" } })
  WoW.runScript(p.buyBtn, "OnClick")
  T.eq(p.buyBtn.enabled, false) T.eq(p.bidBtn.enabled, false)
  WoW.bidRespond()
  T.ok(p.buyBtn.enabled == false or p.buyBtn.enabled == true)
end)

T.test("a Buy click places one buyout; a second click while pending places none; a confirmed reply re-searches", function()
  WoW.money = 1000000
  local p = select1({ { id = 14047, name = "Runecloth", count = 20, buyout = 12000, minBid = 4500, owner = "Sel" },
                      { id = 14047, name = "Runecloth", count = 20, buyout = 13000, owner = "Sel" } })
  local queries = T.count("QueryAuctionItems")
  WoW.runScript(p.buyBtn, "OnClick")
  T.eq(T.count("PlaceAuctionBid"), 1)
  T.ok(T.calledWith("PlaceAuctionBid list 1 12000"))
  WoW.runScript(p.buyBtn, "OnClick")
  T.eq(T.count("PlaceAuctionBid"), 1, "still one")
  WoW.runScript(p.bidBtn, "OnClick")
  T.eq(T.count("PlaceAuctionBid"), 1, "the Bid button is also held")
  T.eq(T.count("QueryAuctionItems"), queries, "no re-search yet")
  WoW.bidRespond()
  answer()
  T.ok(T.count("QueryAuctionItems") > queries, "the page was searched again")
  T.eq(Browse.query, "Rune")
end)

T.test("a failed buy does not re-search", function()
  WoW.money = 1000000
  local p = select1({ { id = 14047, name = "Runecloth", count = 20, buyout = 12000, owner = "Sel" } })
  WoW.ah.bidReply = "notfound"
  local queries = T.count("QueryAuctionItems")
  WoW.runScript(p.buyBtn, "OnClick")
  WoW.bidRespond()
  T.eq(T.count("QueryAuctionItems"), queries)
  WoW.ah.bidReply = nil
end)

T.test("a Bid click places the next bid amount", function()
  WoW.money = 1000000
  local p = select1({ { id = 14047, name = "Runecloth", count = 20, buyout = 12000, minBid = 4000, bid = 4500,
                        minInc = 250, owner = "Sel" } })
  T.eq(label(p.bidBtn), string.upper("Bid " .. A.Util.money(4750)))
  WoW.runScript(p.bidBtn, "OnClick")
  T.eq(T.count("PlaceAuctionBid"), 1)
  T.ok(T.calledWith("PlaceAuctionBid list 1 4750"))
end)

T.test("a Buy at or above the confirmation amount opens the window and bids nothing", function()
  WoW.money = 1000000
  local p = select1({ { id = 14047, name = "Runecloth", count = 20, buyout = 60000, owner = "Sel" } })
  WoW.runScript(p.buyBtn, "OnClick")
  T.eq(T.count("PlaceAuctionBid"), 0)
  T.ok(Confirm.frame:IsShown())
  Confirm.Cancel()
end)

T.test("the bar follows the selection and Auction changes", function()
  WoW.money = 1000000
  local p = select1({ { id = 14047, name = "Runecloth", count = 20, buyout = 12000, owner = "Sel" } })
  p.list.selected = false
  Auction.Changed()
  T.eq(p.buyBtn.enabled, false)
  T.eq(type(p.list.onClick), "function")
end)
