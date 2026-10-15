local A = TaxTheFools
local Auction, Scan, DB, UI = A.Auction, A.Scan, A.DB, A.UI

-- Puts listings on the server and loads the first page into the client, as a search would.
local function page(listings)
  for _, l in ipairs(listings) do table.insert(WoW.ah.listings, l) end
  QueryAuctionItems("", "", "", nil, nil, nil, 0, nil, nil)
  WoW.ahRespond()
end

local function sig(i) return Auction.Sig(Scan.ReadRow(i)) end

local function frame() WoW.runScript(TaxTheFoolsCore, "OnUpdate") end

T.test("the fake client rejects PlaceAuctionBid with arguments of the wrong type, as 1.12 does", function()
  local ok = pcall(PlaceAuctionBid, 1, "list", 100)
  T.eq(ok, false)
  ok = pcall(PlaceAuctionBid, "list", 1, "100")
  T.eq(ok, false)
  T.ok(pcall(PlaceAuctionBid, "list", 1, 100))
end)

T.test("the fake client reports the high bidder as the 11th return", function()
  page({ { id = 14047, name = "Runecloth", count = 1, buyout = 0, minBid = 100, highBidder = true },
         { id = 14047, name = "Runecloth", count = 1, buyout = 0, minBid = 100 } })
  local a = { GetAuctionItemInfo("list", 1) }
  T.eq(a[11], 1)
  a = { GetAuctionItemInfo("list", 2) }
  T.eq(a[11], nil)
  T.eq(Scan.ReadRow(1).high, true) T.eq(Scan.ReadRow(2).high, false)
end)

T.test("a buy below the confirmation amount places one buyout and waits for the reply", function()
  WoW.money = 10000
  page({ { id = 14047, name = "Runecloth", count = 20, buyout = 4000, owner = "Sel" } })
  DB.Realm().snapshot = { at = WoW.now, day = 20375, rows = { ["14047:0"] = { "20|4000|1|Sel" } } }
  local after = 0
  T.eq(Auction.Buy(1, sig(1), function() after = after + 1 end), true)
  T.eq(T.count("PlaceAuctionBid"), 1)
  T.ok(T.calledWith("PlaceAuctionBid list 1 4000"))
  T.eq(Auction.busy.kind, "buy") T.eq(Auction.busy.amount, 4000)
  WoW.bidRespond()                                  -- CHAT_MSG_SYSTEM "Bid accepted." through the core frame
  T.eq(Auction.busy, false, "the lock is released")
  T.eq(WoW.money, 6000, "10000 - 4000")
  T.eq(after, 1, "the page is searched again")
  T.eq(DB.Realm().snapshot.rows["14047:0"], nil, "the bought listing left the snapshot")
  T.ok(T.calledWith("Bought Runecloth x20 for 40s."))
end)

T.test("a listing that changed is refused without a server call", function()
  WoW.money = 10000
  page({ { id = 14047, name = "Runecloth", count = 20, buyout = 4000 } })
  local s = sig(1)
  WoW.ah.listings = {}
  page({ { id = 14047, name = "Runecloth", count = 20, buyout = 4100 } })   -- someone relisted dearer
  T.eq(Auction.Buy(1, s), false)
  T.eq(Auction.Bid(1, s), false)
  T.eq(T.count("PlaceAuctionBid"), 0)
  T.eq(T.count("Listing changed. Search again."), 2)
  T.eq(Auction.Match(1, { key = "14047:0", count = 20, buyout = 4100, owner = "Someone" }) ~= nil, true,
    "owner unknown on the page: not compared")
end)

T.test("a different seller with the same stack and price is not the same auction", function()
  page({ { id = 14047, name = "Runecloth", count = 20, buyout = 4000, owner = "Other" } })
  T.eq(Auction.Match(1, { key = "14047:0", count = 20, buyout = 4000, owner = "Sel" }), nil)
end)

T.test("a buy you can't afford is refused before any call", function()
  WoW.money = 3999
  page({ { id = 14047, name = "Runecloth", count = 20, buyout = 4000 } })
  T.eq(Auction.Buy(1, sig(1)), false)
  T.eq(T.count("PlaceAuctionBid"), 0)
  T.ok(T.calledWith("You can't afford 40s."))
end)

T.test("your own auction is never bought or bid on", function()
  WoW.money = 100000
  page({ { id = 14047, name = "Runecloth", count = 20, buyout = 4000, minBid = 100, owner = "Bankalt" } })
  T.eq(Auction.Buy(1, sig(1)), false)
  T.eq(Auction.Bid(1, sig(1)), false)
  T.eq(T.count("PlaceAuctionBid"), 0)
  T.eq(T.count("That is your own auction."), 2)
end)

T.test("a second click while a buy is pending makes no call", function()
  WoW.money = 100000
  page({ { id = 14047, name = "Runecloth", count = 20, buyout = 4000 },
         { id = 14047, name = "Runecloth", count = 20, buyout = 4100 } })
  Auction.Buy(1, sig(1))
  T.eq(Auction.Buy(2, sig(2)), false)
  T.eq(Auction.Bid(2, sig(2)), false)
  T.eq(T.count("PlaceAuctionBid"), 1)
  T.ok(T.calledWith("Wait for the auction house to answer the last bid."))
end)

T.test("an error reply releases the lock and is shown", function()
  WoW.money = 100000
  WoW.ah.bidReply = "notfound"
  page({ { id = 14047, name = "Runecloth", count = 20, buyout = 4000 } })
  local after = 0
  Auction.Buy(1, sig(1), function() after = after + 1 end)
  WoW.bidRespond()                                  -- UI_ERROR_MESSAGE "Item not found."
  T.eq(Auction.busy, false)
  T.eq(after, 0, "no re-search after a failure")
  T.eq(WoW.money, 100000, "nothing spent")
  T.ok(T.calledWith("Item not found."))
end)

T.test("the server's own money check releases the lock too", function()
  WoW.money = 100000
  WoW.ah.bidReply = "money"
  page({ { id = 14047, name = "Runecloth", count = 20, buyout = 4000 } })
  Auction.Buy(1, sig(1))
  WoW.bidRespond()
  T.eq(Auction.busy, false)
  T.ok(T.calledWith("You don't have enough money."))
end)

T.test("no reply within 5 seconds releases the lock", function()
  WoW.money = 100000
  WoW.ah.bidReply = "none"
  page({ { id = 14047, name = "Runecloth", count = 20, buyout = 4000 } })
  Auction.Buy(1, sig(1))
  WoW.bidRespond()                                  -- nothing comes back
  WoW.clock = WoW.clock + 4.9
  frame()
  T.ok(Auction.busy, "still waiting at 4.9s")
  WoW.clock = WoW.clock + 0.1
  frame()
  T.eq(Auction.busy, false, "released at 5s")
  T.ok(T.calledWith("No reply from the auction house"))
end)

T.test("messages that are not auction replies leave the lock alone", function()
  WoW.money = 100000
  page({ { id = 14047, name = "Runecloth", count = 20, buyout = 4000 } })
  Auction.Buy(1, sig(1))
  WoW.fire("CHAT_MSG_SYSTEM", "Bankalt has come online.")
  WoW.fire("UI_ERROR_MESSAGE", "You are too far away.")
  T.ok(Auction.busy)
  T.eq(ERR_AUCTION_RESTRICTED_ACCOUNT, nil, "not a 1.12 global, and no harm done")
end)

T.test("a bid is the minimum bid, or the current bid plus the increment", function()
  WoW.money = 100000
  page({ { id = 14047, name = "Runecloth", count = 20, buyout = 9000, minBid = 4000 },
         { id = 14047, name = "Runecloth", count = 20, buyout = 0, minBid = 4000, bid = 5000, minInc = 250 } })
  T.eq(Auction.BidAmount(Scan.ReadRow(1)), 4000, "no bid yet: the minimum bid")
  T.eq(Auction.BidAmount(Scan.ReadRow(2)), 5250, "5000 + 250")
  T.eq(Auction.Bid(2, sig(2)), true)
  T.ok(T.calledWith("PlaceAuctionBid list 2 5250"))
  WoW.bidRespond()
  T.eq(WoW.money, 94750, "100000 - 5250, held while the bid stands")
  T.ok(T.calledWith("Bid 52s 50c on Runecloth x20."))
end)

T.test("a bid that would reach the buyout is refused: on 1.12 it would buy", function()
  WoW.money = 100000
  page({ { id = 14047, name = "Runecloth", count = 20, buyout = 5000, minBid = 4000, bid = 4900, minInc = 100 } })
  T.eq(Auction.Bid(1, sig(1)), false, "4900 + 100 = 5000, the buyout")
  T.eq(T.count("PlaceAuctionBid"), 0)
  T.ok(T.calledWith("Use Buy"))
end)

T.test("a bid is refused when you already hold the high bid", function()
  WoW.money = 100000
  page({ { id = 14047, name = "Runecloth", count = 20, buyout = 0, minBid = 4000, bid = 4500, minInc = 100,
           highBidder = true } })
  T.eq(Auction.Bid(1, sig(1)), false)
  T.eq(T.count("PlaceAuctionBid"), 0)
  T.ok(T.calledWith("You are already the high bidder."))
end)

T.test("a confirmation amount of 0 never asks", function()
  WoW.money = 10000000
  DB.S().buy.confirmAbove = 0
  page({ { id = 14047, name = "Runecloth", count = 20, buyout = 9000000 } })
  T.eq(Auction.Buy(1, sig(1)), true)
  T.ok(T.calledWith("PlaceAuctionBid list 1 9000000"))
end)

T.test("a refusal shows on the status strip", function()
  UI.CreateAH()
  UI.ah:Show()
  page({ { id = 14047, name = "Runecloth", count = 20, buyout = 4000 } })
  Auction.Buy(1, sig(1))
  T.eq(UI.ah.status.text:GetText(), "You can't afford 40s.")
  T.eq(UI.ah.status.text.color[1], A.Theme.color.bad[1])
  WoW.clock = WoW.clock + 10
  UI.RefreshStatus()
  T.ok(string.find(UI.ah.status.text:GetText(), "full scan", 1, true), "back to the scan line after 10s")
  UI.ah:Hide()
end)
