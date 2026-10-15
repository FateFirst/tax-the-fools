local A = TaxTheFools
local Auction, Confirm, Scan, DB, AH = A.Auction, A.Confirm, A.Scan, A.DB, A.AH

local function page(listings)
  for _, l in ipairs(listings) do table.insert(WoW.ah.listings, l) end
  QueryAuctionItems("", "", "", nil, nil, nil, 0, nil, nil)
  WoW.ahRespond()
end

local function sig(i) return Auction.Sig(Scan.ReadRow(i)) end

-- 20 Runecloth for 6g: at or above the default 5g (50000 copper), so it asks first.
local function dear()
  WoW.money = 1000000
  page({ { id = 14047, name = "Runecloth", count = 20, buyout = 60000, quality = 1 } })
end

T.test("a buy at or above the confirmation amount asks first; the window's Buy buys exactly once", function()
  dear()
  local after = 0
  T.eq(Auction.Buy(1, sig(1), function() after = after + 1 end), "confirm")
  T.eq(T.count("PlaceAuctionBid"), 0, "the first click makes no call")
  T.ok(Confirm.frame:IsShown())
  WoW.runScript(Confirm.frame.buy, "OnClick")
  T.eq(T.count("PlaceAuctionBid"), 1)
  T.ok(T.calledWith("PlaceAuctionBid list 1 60000"))
  T.eq(Confirm.frame:IsShown(), false)
  WoW.runScript(Confirm.frame.buy, "OnClick")          -- a stray second click on a closed window
  T.eq(T.count("PlaceAuctionBid"), 1, "still once")
  WoW.bidRespond()
  T.eq(after, 1, "the follow-up runs after the confirmed buy")
end)

T.test("exactly the confirmation amount asks; one copper under does not", function()
  WoW.money = 1000000
  page({ { id = 14047, name = "Runecloth", count = 20, buyout = 50000 },
         { id = 14047, name = "Runecloth", count = 20, buyout = 49999 } })
  T.eq(Auction.Buy(1, sig(1)), "confirm", "50000 >= 50000")
  Confirm.Cancel()
  T.eq(Auction.Buy(2, sig(2)), true, "49999 < 50000")
end)

T.test("the window shows the item, quantity, total, price each and percent of market", function()
  dear()
  DB.Realm().market["14047:0"] = { v = 4000, conf = 1 }
  Auction.Buy(1, sig(1))
  local l = Confirm.frame.lines
  T.eq(l[1]:GetText(), "|cffffffffRunecloth|r  x20")
  T.eq(l[2]:GetText(), "Total " .. A.Util.money(60000))
  -- each 60000 / 20 = 3000 (30s); 3000 / 4000 = 75% of market
  T.eq(l[3]:GetText(), "Each " .. A.Util.money(3000) .. "   Market " .. A.Util.money(4000) .. "   75% of market")
  local lines = Confirm.Lines({ name = "Runecloth", count = 20, buyout = 60000, quality = 1 }, nil)
  T.eq(lines[3], "Each " .. A.Util.money(3000) .. "   no market value")
end)

T.test("a listing that changed while the window was open is refused", function()
  dear()
  Auction.Buy(1, sig(1))
  WoW.ah.listings = {}
  page({ { id = 14047, name = "Runecloth", count = 20, buyout = 61000 } })
  WoW.runScript(Confirm.frame.buy, "OnClick")
  T.eq(T.count("PlaceAuctionBid"), 0)
  T.ok(T.calledWith("Listing changed. Search again."))
end)

T.test("Cancel and Escape close the window without buying", function()
  dear()
  Auction.Buy(1, sig(1))
  WoW.runScript(Confirm.frame.cancel, "OnClick")
  T.eq(Confirm.frame:IsShown(), false)
  T.eq(Confirm.pending, false)
  Auction.Buy(1, sig(1))
  local listed = false
  for _, n in ipairs(UISpecialFrames) do if n == "TaxTheFoolsConfirm" then listed = true end end
  T.ok(listed, "Escape hides it")
  Confirm.frame:Hide()                                   -- what Escape does
  T.eq(Confirm.Buy(), false, "nothing pending")
  T.eq(T.count("PlaceAuctionBid"), 0)
end)

T.test("leaving the auction house closes the window", function()
  dear()
  Auction.Buy(1, sig(1))
  AH.OnClosed()
  T.eq(Confirm.frame:IsShown(), false)
  T.eq(Confirm.pending, false)
end)
