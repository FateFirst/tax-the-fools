local A = TaxTheFools
local Core, DB, Scan, UI, AH = A.Core, A.DB, A.Scan, A.UI, A.AH
local function ttf(msg) SlashCmdList["TAXTHEFOOLS"](msg) end

T.test("core is ready once saved variables load", function()
  T.ok(Core.ready)
end)

T.test("/ttf with no arguments lists the commands", function()
  ttf("")
  T.ok(T.calledWith("/ttf options")) T.ok(T.calledWith("/ttf watch")) T.ok(T.calledWith("/ttf probe"))
  T.ok(T.calledWith("/ttf craft"))
end)

T.test("chat messages carry the TTF prefix", function()
  A.Util.msg("hello")
  T.ok(T.calledWith("TTF:|r hello"))
end)

T.test("Safe switches a part off after an error instead of erroring every frame", function()
  local calls = 0
  local boom = function() calls = calls + 1 error("bad") end
  Core.Safe("thing", boom)
  Core.Safe("thing", boom)
  T.eq(calls, 1)
  T.ok(T.calledWith("thing stopped after an error"))
end)

T.test("an upgrade says which version it replaced", function()
  TaxTheFoolsDB.version = "0.0.9"
  Core.Init()
  T.ok(T.calledWith("loaded, replaces v0.0.9"))
end)

T.test("talking to an auctioneer opens our window a frame later, leaving closes it", function()
  AH.switching = true UI.ah:Hide() AH.switching = false
  AuctionFrame:Show()
  WoW.fire("AUCTION_HOUSE_SHOW")
  WoW.runScript(TaxTheFoolsCore, "OnUpdate")
  T.ok(UI.ah:IsShown())
  T.eq(AuctionFrame:IsShown(), false)
  WoW.fire("AUCTION_HOUSE_CLOSED")
  T.eq(UI.ah:IsShown(), false)
  T.ok(not T.calledWith("CloseAuctionHouse"), "the server already closed it")
end)

T.test("auction list updates reach the scan", function()
  for i = 1, 120 do table.insert(WoW.ah.listings, { id = 14047, name = "Runecloth", count = 1, buyout = 100 + i }) end
  Scan.StartFull(WoW.clock)
  WoW.runScript(TaxTheFoolsCore, "OnUpdate")
  WoW.ahRespond()
  T.eq(Scan.job.page, 1, "first page accepted through the event")
end)

T.test("opening a merchant learns vendor prices", function()
  WoW.bags[0] = { { id = 4306, name = "Silk Cloth", count = 20, vendor = 37 } }
  WoW.merchantOpen = true
  WoW.fire("MERCHANT_SHOW")
  T.eq(A.Items.Vendor(4306), 37)
end)

T.test("opening a merchant learns what it sells, and for how much", function()
  WoW.merchant = { { id = 2321, name = "Fine Thread", price = 100, quantity = 1, numAvailable = -1 } }
  WoW.merchantOpen = true
  WoW.fire("MERCHANT_SHOW")
  T.eq(A.Items.Get(2321).vb, 100)
end)

T.test("watch, list and unwatch by name", function()
  A.Items.Remember(4306, "Silk Cloth")
  ttf("watch silk cloth")
  T.ok(DB.Realm().watch["4306:0"])
  ttf("watchlist")
  T.ok(T.calledWith("Watching 1: Silk Cloth"))
  ttf("unwatch Silk Cloth")
  T.eq(DB.Realm().watch["4306:0"], nil)
end)

T.test("watching an item the addon hasn't seen explains how to teach it", function()
  ttf("watch Felcloth")
  T.ok(T.calledWith("don't know \"Felcloth\" yet"))
end)

T.test("status reports what is stored and the last full scan", function()
  DB.Realm().scan.lastFull = WoW.now - 90000
  ttf("status")
  T.ok(T.calledWith("items known"))
  T.ok(T.calledWith("Last full scan 1d 1h ago"))
end)

T.test("/ttf craft opens and closes the Crafting window", function()
  local f = A.CraftUI.Window()
  f:Hide()
  ttf("craft")
  T.ok(f:IsShown())
  ttf("craft")
  T.eq(f:IsShown(), false)
end)

T.test("debug toggles", function()
  ttf("debug") T.eq(DB.S().debug, true)
  ttf("debug") T.eq(DB.S().debug, false)
end)

T.test("nothing is bought, bid on, posted or cancelled without a click", function()
  for i = 1, 120 do table.insert(WoW.ah.listings, { id = 14047, name = "Runecloth", count = 1, buyout = 100 + i }) end
  DB.Realm().market["14047:0"] = { v = 100000, conf = 1 }     -- everything looks like a bargain
  AuctionFrame:Show()
  WoW.fire("AUCTION_HOUSE_SHOW")
  A.UI.StartScan("full")
  for _ = 1, 50 do
    WoW.clock = WoW.clock + 0.5
    WoW.runScript(TaxTheFoolsCore, "OnUpdate")
    if WoW.ah.pending then WoW.ahRespond() end
  end
  T.ok(Scan.job == nil, "full scan finished")
  T.ok(A.Browse.Search("Rune", 0), "search ran")
  for _ = 1, 5 do
    WoW.clock = WoW.clock + 0.5
    WoW.runScript(TaxTheFoolsCore, "OnUpdate")
    if WoW.ah.pending then WoW.ahRespond() end
  end
  T.ok(T.calledWith("QueryAuctionItems"), "it did scan")
  -- A merchant selling thread and a tradeskill window full of craftable recipes.
  WoW.bags[0] = { { id = 4306, name = "Silk Cloth", count = 40, vendor = 37 } }
  WoW.merchant = { { id = 2321, name = "Fine Thread", price = 100, quantity = 1, numAvailable = -1 } }
  WoW.merchantOpen = true
  WoW.fire("MERCHANT_SHOW")
  WoW.tradeskill = { name = "Tailoring", rank = 225, maxRank = 300, selected = 2, rows = {
    { header = true, name = "Cloth" },
    { name = "Bolt of Silk Cloth", type = "optimal", id = 4305, available = 10,
      reagents = { { id = 4306, name = "Silk Cloth", count = 4, have = 40 } } } } }
  WoW.openTradeSkill()
  WoW.fire("TRADE_SKILL_UPDATE")
  for _ = 1, 10 do
    WoW.clock = WoW.clock + 0.25
    WoW.runScript(TaxTheFoolsCore, "OnUpdate")
  end
  A.CraftUI.Toggle()
  T.ok(A.Items.Get(2321).vb, "the merchant was read")
  T.ok(DB.Char().professions.Tailoring.recipes["Bolt of Silk Cloth"], "the recipes were read")
  T.ok(not T.calledWith("PlaceAuctionBid"), "no bid or buyout")
  T.ok(not T.calledWith("StartAuction"), "no post")
  T.ok(not T.calledWith("CancelAuction"), "no cancel")
  T.ok(not T.calledWith("DoTradeSkill"), "nothing crafted")
  T.ok(not T.calledWith("BuyMerchantItem"), "nothing bought from the merchant")
  T.ok(not T.calledWith("UseContainerItem"), "nothing sold to the merchant")
  A.CraftUI.Toggle()
end)

T.test("a full scan of obvious bargains buys nothing; Find buys nothing; one Buy click buys exactly once", function()
  WoW.money = 1000000
  for i = 1, 120 do table.insert(WoW.ah.listings, { id = 14047, name = "Runecloth", count = 1, buyout = 100 + i, owner = "S" .. i }) end
  DB.Realm().market["14047:0"] = { v = 100000, conf = 1 }     -- everything looks like a bargain
  AuctionFrame:Show()
  WoW.fire("AUCTION_HOUSE_SHOW")
  WoW.runScript(TaxTheFoolsCore, "OnUpdate")
  A.UI.StartScan("full")
  for _ = 1, 60 do
    WoW.clock = WoW.clock + 0.5
    WoW.runScript(TaxTheFoolsCore, "OnUpdate")
    if WoW.ah.pending then WoW.ahRespond() end
  end
  T.ok(Scan.job == nil, "full scan finished")
  T.ok(DB.Realm().snapshot, "and left a snapshot")
  DB.Realm().market["14047:0"] = { v = 100000, conf = 1 }     -- the scan re-derived it; the snapshot is all bargains
  UI.ah:Show()
  UI.ah.tabs:Select("deals")
  local p = UI.pages.deals
  p.found, p.searching = false, false
  p.list:SetHeight(300)
  p:Refresh()
  T.ok(table.getn(p.list.data) > 0, "the page lists bargains")
  T.eq(T.count("PlaceAuctionBid"), 0, "a scan and opening Deals never bid")
  p.list.selected = p.list.data[1]
  A.DealsUI.UpdateBar()
  WoW.runScript(p.findBtn, "OnClick")
  for _ = 1, 40 do
    WoW.clock = WoW.clock + 0.5
    WoW.runScript(TaxTheFoolsCore, "OnUpdate")
    if WoW.ah.pending then WoW.ahRespond() end
  end
  T.ok(p.found, "Find located the listing")
  T.eq(T.count("PlaceAuctionBid"), 0, "Find never bids")
  WoW.runScript(p.findBtn, "OnClick")
  T.eq(T.count("PlaceAuctionBid"), 1, "Buy bids exactly once")
  WoW.runScript(p.findBtn, "OnClick")
  T.eq(T.count("PlaceAuctionBid"), 1, "a second click while pending bids no more")
  WoW.bidRespond()
  for _ = 1, 20 do
    WoW.clock = WoW.clock + 0.5
    WoW.runScript(TaxTheFoolsCore, "OnUpdate")
    if WoW.ah.pending then WoW.ahRespond() end
  end
  T.eq(T.count("PlaceAuctionBid"), 1, "nothing else bought afterwards")
  UI.ah.tabs:Select("browse")
end)

T.test("switching to Blizzard's window mid-scan stops all queries and buys nothing", function()
  for i = 1, 120 do table.insert(WoW.ah.listings, { id = 14047, name = "Runecloth", count = 1, buyout = 100 + i }) end
  AuctionFrame:Show()
  WoW.fire("AUCTION_HOUSE_SHOW")
  A.UI.StartScan("full")
  for _ = 1, 2 do
    WoW.clock = WoW.clock + 0.5
    WoW.runScript(TaxTheFoolsCore, "OnUpdate")
    if WoW.ah.pending then WoW.ahRespond() end
  end
  T.ok(Scan.job ~= nil, "scan is mid-way")
  A.AH.ShowBlizzard()
  local sent = T.count("QueryAuctionItems")
  for _ = 1, 40 do
    WoW.clock = WoW.clock + 0.5
    WoW.runScript(TaxTheFoolsCore, "OnUpdate")
    if WoW.ah.pending then WoW.ahRespond() end
  end
  T.eq(T.count("QueryAuctionItems"), sent, "no further queries")
  T.ok(not T.calledWith("PlaceAuctionBid"), "no bid or buyout")
  T.ok(not T.calledWith("StartAuction"), "no post")
  T.ok(not T.calledWith("CancelAuction"), "no cancel")
end)

T.test("after login, retention runs and market values are refreshed", function()
  DB.Realm().history["14047:0"] = { days = { [20375] = { p25 = 400, min = 390, n = 3 } }, months = {} }
  DB.StartPrune()
  Core.pruned = false
  for _ = 1, 3 do WoW.runScript(TaxTheFoolsCore, "OnUpdate") end
  T.eq(DB.Realm().market["14047:0"].v, 400)
end)

T.test("login prunes posting-log entries older than the retention", function()
  local char = DB.Char()
  char.postings = { { key = "14047:0", at = WoW.now - 40 * 86400 }, { key = "14047:0", at = WoW.now - 86400 } }
  Core.Init()
  T.eq(table.getn(char.postings), 1)
  T.eq(char.postings[1].at, WoW.now - 86400)
end)

T.test("selling and auctions: nothing posts, cancels, splits or bids without a click; each click does it once", function()
  WoW.items[14047] = { name = "Runecloth", stack = 20, quality = 1, tex = "rune" }
  WoW.bags[0] = { { id = 14047, name = "Runecloth", count = 20, vendor = 100 }, {}, {}, {} }
  WoW.bags[1], WoW.bags[2], WoW.bags[3], WoW.bags[4] = nil, nil, nil, nil
  WoW.money = 1000000
  DB.Realm().market["14047:0"] = { v = 1000, conf = 0.8 }
  table.insert(WoW.ah.listings, { id = 14047, name = "Runecloth", count = 10, buyout = 9000, minBid = 1, owner = "Rival" })
  table.insert(WoW.ah.listings, { id = 14047, name = "Runecloth", count = 20, buyout = 4000, minBid = 3600, owner = WoW.player })
  local function pump()
    for _ = 1, 40 do
      WoW.clock = WoW.clock + 0.5
      WoW.runScript(TaxTheFoolsCore, "OnUpdate")
      if WoW.ah.pending then WoW.ahRespond() end
    end
  end
  local function quiet(why)
    for _, name in ipairs({ "StartAuction", "CancelAuction", "SplitContainerItem", "PlaceAuctionBid", "GetInboxText",
                            "GetInboxInvoiceInfo", "TakeInboxMoney", "TakeInboxItem", "DeleteInboxItem", "ReturnInboxItem" }) do
      T.eq(T.count(name), 0, why .. ": " .. name)
    end
  end
  AuctionFrame:Show()
  WoW.fire("AUCTION_HOUSE_SHOW")
  WoW.runScript(TaxTheFoolsCore, "OnUpdate")
  UI.ah:Show()
  UI.ah.tabs:Select("sell")
  local p = UI.pages.sell
  p.list:SetHeight(200)
  p:Refresh()
  for _, c in ipairs(p.cells) do
    if c.item and c.item.name == "Runecloth" then WoW.runScript(c, "OnClick") end
  end
  pump()
  quiet("Sell open, select, competition search")
  UI.ah.tabs:Select("auctions")
  local a = UI.pages.auctions
  a.list:SetHeight(300)
  a:Refresh()
  WoW.ownerRespond()
  pump()
  quiet("Auctions open and owner list")
  UI.ah.tabs:Select("sell")
  p:Refresh()
  WoW.runScript(p.postBtn, "OnClick")
  T.eq(T.count("StartAuction"), 1, "one Post click")
  T.eq(T.count("CancelAuction"), 0)
  T.eq(T.count("PlaceAuctionBid"), 0)
  WoW.postRespond()
  pump()
  T.eq(T.count("StartAuction"), 1, "nothing posts after the reply")
  UI.ah.tabs:Select("auctions")
  a:Refresh()
  WoW.ownerRespond()
  WoW.runScript(a.list.rows[1], "OnClick")
  WoW.runScript(a.cancelBtn, "OnClick")
  T.eq(T.count("CancelAuction"), 1, "one Cancel click")
  T.eq(T.count("PlaceAuctionBid"), 0, "cancelling is not a bid")
  -- one Split click
  WoW.calls = {}
  WoW.bags[0] = { { id = 14047, name = "Runecloth", count = 20, vendor = 100 }, {}, {}, {} }
  UI.ah.tabs:Select("sell")
  p:Refresh()
  for _, c in ipairs(p.cells) do
    if c.item and c.item.name == "Runecloth" then WoW.runScript(c, "OnClick") end
  end
  pump()
  p.sizeBox:SetText("5") WoW.runScript(p.sizeBox, "OnTextChanged")
  quiet("sizing a stack")
  WoW.runScript(p.postBtn, "OnClick")
  T.eq(T.count("SplitContainerItem"), 1, "one Split click")
  T.eq(T.count("StartAuction"), 0, "splitting does not post")
  pump()
  T.eq(T.count("SplitContainerItem"), 1)
  T.eq(T.count("StartAuction"), 0)
  WoW.calls = {}
  -- the mailbox: AH mail is read from headers only, however many update events arrive
  WoW.mail = { { subject = "Auction successful: Runecloth", money = 3800, daysLeft = 29.5 },
               { subject = "Auction expired: Runecloth", money = 0, daysLeft = 28, hasItem = 1 } }
  WoW.fire("MAIL_SHOW")
  WoW.fire("MAIL_INBOX_UPDATE") WoW.fire("MAIL_INBOX_UPDATE")
  pump()
  T.ok(T.count("GetInboxHeaderInfo") >= 2, "the headers were read")
  quiet("mailbox open with AH mail")
  UI.ah.tabs:Select("browse")
end)
