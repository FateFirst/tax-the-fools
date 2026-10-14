local A = TaxTheFools
local Core, DB, Scan, UI, AH = A.Core, A.DB, A.Scan, A.UI, A.AH
local function ttf(msg) SlashCmdList["TAXTHEFOOLS"](msg) end

T.test("core is ready once saved variables load", function()
  T.ok(Core.ready)
end)

T.test("/ttf with no arguments lists the commands", function()
  ttf("")
  T.ok(T.calledWith("/ttf options")) T.ok(T.calledWith("/ttf watch")) T.ok(T.calledWith("/ttf probe"))
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
  T.ok(not T.calledWith("PlaceAuctionBid"), "no bid or buyout")
  T.ok(not T.calledWith("StartAuction"), "no post")
  T.ok(not T.calledWith("CancelAuction"), "no cancel")
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
