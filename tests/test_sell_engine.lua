local A = TaxTheFools
local Auction, Scan, DB, Sell, Confirm = A.Auction, A.Scan, A.DB, A.Sell, A.Confirm

-- Bag 0 holds 20 Runecloth in slot 1, with free slots 2 and 3. Vendor price 100 each, so the client's
-- deposit for a 24h (480 min) post is 100 * 20 * 0.15 * 480/120 = 1200; the fake server charges 0.6x = 720.
local function stock(count)
  WoW.items[14047] = { name = "Runecloth", stack = 20, vendor = 100 }
  WoW.bags[0] = { { id = 14047, name = "Runecloth", count = count or 20, vendor = 100 }, {}, {} }
  WoW.bags[1], WoW.bags[2], WoW.bags[3], WoW.bags[4] = nil, nil, nil, nil
end

local function frame() WoW.runScript(TaxTheFoolsCore, "OnUpdate") end

-- Your auctions on the server, loaded into the client's owner list.
local function owned(listings)
  for _, l in ipairs(listings) do
    l.owner = WoW.player
    table.insert(WoW.ah.listings, l)
  end
  GetOwnerAuctionItems(0)
  WoW.ownerRespond()
end
local function osig(i) return Auction.Sig(Auction.OwnerRow(i)) end

-- ---------- the fake client ----------

T.test("the fake client rejects wrongly typed arguments for the new calls, as 1.12 does", function()
  T.eq(pcall(StartAuction, "100", 200, 480), false)
  T.eq(pcall(StartAuction, 100, 200, 481), false, "not 120, 480 or 1440")
  T.eq(pcall(CancelAuction, "1"), false)
  T.eq(pcall(SplitContainerItem, 0, 1, "5"), false)
  T.eq(pcall(PickupContainerItem, "0", 1), false)
  T.eq(pcall(CalculateAuctionDeposit, "480"), false)
  T.eq(pcall(GetOwnerAuctionItems, "0"), false)
  T.eq(pcall(GetNumAuctionItems), false)
end)

T.test("the fake cursor and sell slot: pick up, click, lock, return", function()
  stock()
  PickupContainerItem(0, 1)
  T.ok(WoW.cursor, "the hand holds the stack")
  local _, _, locked = GetContainerItemInfo(0, 1)
  T.eq(locked, 1, "the source slot is locked")
  ClickAuctionSellItemButton()
  T.eq(WoW.cursor, nil)
  local name, _, count = GetAuctionSellItemInfo()
  T.eq(name, "Runecloth") T.eq(count, 20)
  T.eq(CalculateAuctionDeposit(480), 1200)
  ClickAuctionSellItemButton()                       -- takes it back to the hand
  T.eq(GetAuctionSellItemInfo(), nil)
  ClearCursor()
  local _, _, locked2 = GetContainerItemInfo(0, 1)
  T.eq(locked2, nil, "unlocked again")
end)

T.test("the fake client splits a stack into an empty slot", function()
  stock()
  SplitContainerItem(0, 1, 5)
  PickupContainerItem(0, 2)
  local _, c1 = GetContainerItemInfo(0, 1)
  local _, c2 = GetContainerItemInfo(0, 2)
  T.eq(c1, 15) T.eq(c2, 5)
end)

T.test("the owner list reads through the owner type and is stale until asked again", function()
  owned({ { id = 14047, name = "Runecloth", count = 20, buyout = 4000, minBid = 3600 } })
  T.eq(GetNumAuctionItems("owner"), 1)
  local name, _, count, _, _, _, minBid, _, buyout, bid, _, owner = GetAuctionItemInfo("owner", 1)
  T.eq(name, "Runecloth") T.eq(count, 20) T.eq(minBid, 3600) T.eq(buyout, 4000) T.eq(bid, 0) T.eq(owner, "Bankalt")
  T.eq(GetNumAuctionItems("list"), 0, "the search page is separate")
  WoW.ah.listings = {}
  T.eq(GetNumAuctionItems("owner"), 1, "stale")
end)

-- ---------- Post ----------

T.test("Post makes the exact call sequence, logs the posting and learns the deposit", function()
  stock() WoW.money = 100000
  DB.Realm().market["14047:0"] = { v = 4000, conf = 1 }
  local after = 0
  -- 20 x 4000 = 80000 total buyout, at market (floor 3200 each); starting bid 90% = 72000
  T.eq(Auction.Post(0, 1, 20, 72000, 80000, 480, "14047:0", false, function() after = after + 1 end), true)
  local want = { "ClearCursor", "PickupContainerItem 0 1", "ClickAuctionSellItemButton", "StartAuction 72000 80000 480" }
  local got = {}
  for _, c in ipairs(WoW.calls) do
    if string.find(c, "^ClearCursor") or string.find(c, "^Pickup") or string.find(c, "^ClickAuction")
       or string.find(c, "^StartAuction") then table.insert(got, c) end
  end
  T.eq(table.concat(got, "|"), table.concat(want, "|"))
  T.eq(Auction.busy.kind, "post")
  WoW.postRespond()
  T.eq(Auction.busy, false, "released on ERR_AUCTION_STARTED")
  T.eq(after, 1)
  T.eq(WoW.money, 100000 - 720)
  local e = DB.Char().postings[1]
  T.eq(e.key, "14047:0") T.eq(e.stack, 20) T.eq(e.bid, 72000) T.eq(e.buyout, 80000) T.eq(e.minutes, 480)
  T.eq(e.deposit, 720) T.eq(e.at, WoW.now)
  -- 720 / (20 x (1 + (20-20) x 0.05)) = 36 per unit base, learned. A full stack predicts 720; a stack of 5 is
  -- 36 x 5 x (1 + (20-5) x 0.05) = 180 x 1.75 = 315 (the old linear model said 180).
  T.eq(Sell.Deposit(TaxTheFoolsDB.items, 14047, 480, 20, 20), 720)
  T.eq(Sell.Deposit(TaxTheFoolsDB.items, 14047, 480, 5, 20), 315)
  T.ok(T.calledWith("Posted Runecloth x20"))
end)

T.test("Post empties an occupied sell slot first", function()
  stock() WoW.money = 100000
  WoW.sellSlot = { item = { id = 1, name = "Junk", count = 1, vendor = 1 }, count = 1, bag = 0, slot = 3 }
  Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true)
  local got = {}
  for _, c in ipairs(WoW.calls) do
    if string.find(c, "^ClearCursor") or string.find(c, "^Pickup") or string.find(c, "^ClickAuction")
       or string.find(c, "^StartAuction") then table.insert(got, c) end
  end
  T.eq(table.concat(got, "|"), "ClearCursor|ClickAuctionSellItemButton|ClearCursor|PickupContainerItem 0 1|" ..
    "ClickAuctionSellItemButton|StartAuction 100 200 480")
  T.eq(GetAuctionSellItemInfo(), "Runecloth")
end)

local function noPost(why)
  T.eq(T.count("StartAuction"), 0, why)
  T.eq(Auction.busy, false, why)
end

T.test("Post refuses when the bag slot changed after selecting (Review Focus 1)", function()
  stock(15) WoW.money = 100000                         -- 15 now, the panel thought 20
  T.eq(Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true), false)
  noPost("stack smaller")
  T.ok(T.calledWith("changed"))
  T.eq(T.count("PickupContainerItem"), 0, "the bag is not touched")
  WoW.bags[0][1] = { id = 2589, name = "Linen Cloth", count = 20 }
  T.eq(Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true), false, "another item")
  WoW.bags[0][1] = {}
  T.eq(Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true), false, "sold")
  noPost("empty")
  T.eq(T.count("PickupContainerItem"), 0)
end)

T.test("Post below the floor needs the override (Review Focus 2)", function()
  stock() WoW.money = 100000
  DB.Realm().market["14047:0"] = { v = 4000, conf = 1 }
  -- floor 80% of 4000 = 3200 each; 20 x 3200 = 64000. 63999 is under, 64000 is not.
  T.eq(Auction.Post(0, 1, 20, 100, 63999, 480, "14047:0", false), false)
  noPost("under the floor")
  T.ok(T.calledWith("below your floor"))
  T.eq(T.count("PickupContainerItem"), 0)
  T.eq(Auction.Post(0, 1, 20, 100, 63999, 480, "14047:0", true), true, "allowed")
  T.eq(T.count("StartAuction"), 1)
  Auction.ResetState() WoW.calls = {}
  T.eq(Auction.Post(0, 1, 20, 100, 64000, 480, "14047:0", false), true, "at the floor")
end)

T.test("Post with no market value has no floor", function()
  stock() WoW.money = 100000
  T.eq(Auction.Post(0, 1, 20, 1, 1, 480, "14047:0", false), true)
end)

T.test("Post refuses a bid above the buyout, and an unaffordable deposit", function()
  stock() WoW.money = 100000
  T.eq(Auction.Post(0, 1, 20, 201, 200, 480, "14047:0", true), false)
  noPost("bid above buyout")
  T.ok(T.calledWith("bid"))
  WoW.calls = {}
  WoW.money = 1199                                     -- the client's figure is 1200
  T.eq(Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true), false)
  noPost("cannot afford")
  T.ok(T.calledWith("deposit"))
  T.eq(WoW.sellSlot, nil, "the item is taken back out of the sell slot")
  T.eq(WoW.cursor, nil)
  local _, _, locked = GetContainerItemInfo(0, 1)
  T.eq(locked, nil)
  WoW.money = 1200
  T.eq(Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true), true, "exactly the deposit")
end)

T.test("Post hands StartAuction whole copper only (Review I3)", function()
  stock() WoW.money = 100000
  T.eq(Auction.Post(0, 1, 20, 100.7, 200.9, 480, "14047:0", true), true)
  T.ok(T.calledWith("StartAuction 100 200 480"), "floored bid and buyout")
  T.eq(Auction.busy.bid, 100) T.eq(Auction.busy.buyout, 200)
end)

T.test("a learned deposit is what affordability uses", function()
  stock() WoW.money = 800
  Sell.LearnDeposit(TaxTheFoolsDB.items, 14047, 480, 720, 20, 20)   -- 720 / 20 = 36 per unit; a full stack 720
  T.eq(Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true), true, "800 >= 720 although the client says 1200")
end)

T.test("clicking Post twice quickly makes exactly one StartAuction (Review Focus 3)", function()
  stock() WoW.money = 100000
  T.eq(Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true), true)
  T.eq(Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true), false)
  T.eq(T.count("StartAuction"), 1)
  T.ok(T.calledWith("Wait for the auction house"))
  WoW.postRespond()
  T.eq(Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true), false, "and the stack is gone after the reply")
  T.eq(T.count("StartAuction"), 1)
end)

T.test("a post failure releases the lock, runs onFail and learns nothing", function()
  stock() WoW.money = 100000
  WoW.ah.postReply = "limited"
  local failed = nil
  Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true, nil, function(t) failed = t end)
  WoW.postRespond()
  T.eq(Auction.busy, false)
  T.eq(failed, ERR_AUCTION_LIMITED_DURATION_ITEM)
  T.eq(DB.Char().postings, nil)
  T.eq(TaxTheFoolsDB.items[14047] and TaxTheFoolsDB.items[14047].dep, nil)
  T.ok(T.calledWith(ERR_AUCTION_LIMITED_DURATION_ITEM))
  for _, name in ipairs({ "ERR_NOT_ENOUGH_MONEY", "ERR_AUCTION_REPAIR_ITEM", "ERR_AUCTION_USED_CHARGES" }) do
    Auction.busy = { kind = "post", at = GetTime(), after = false, onFail = false }
    WoW.fire("UI_ERROR_MESSAGE", getglobal(name))
    T.eq(Auction.busy, false, name)
  end
end)

-- Review I1: a post that fails leaves nothing in the sell slot, so the bag slot is not stuck locked.
local function slotFree()
  T.eq(WoW.sellSlot, nil, "sell slot empty")
  T.eq(WoW.cursor, nil, "hand empty")
  local _, _, locked = GetContainerItemInfo(0, 1)
  T.eq(locked, nil, "bag slot unlocked")
end

T.test("a failed post empties the sell slot, and the same stack posts on the next click (Review I1)", function()
  stock() WoW.money = 100000
  WoW.ah.postReply = "money"
  Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true)
  T.ok(WoW.sellSlot, "in the slot while pending")
  WoW.postRespond()
  T.eq(Auction.busy, false)
  slotFree()
  WoW.ah.postReply = "auto"
  T.eq(Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true), true, "the next click posts the same stack")
  T.eq(T.count("StartAuction"), 2)
  WoW.postRespond()
  T.eq(DB.Char().postings[1].stack, 20)
end)

T.test("a timed-out post empties the sell slot too (Review I1)", function()
  stock() WoW.money = 100000
  WoW.ah.postReply = "none"
  Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true)
  WoW.postRespond()
  WoW.clock = WoW.clock + 5
  frame()
  T.eq(Auction.busy, false)
  slotFree()
end)

T.test("Post refuses, clears and never starts when the item did not reach the sell slot (Review I1)", function()
  stock() WoW.money = 100000
  local keep = ClickAuctionSellItemButton
  ClickAuctionSellItemButton = function() WoW.log("ClickAuctionSellItemButton") end   -- the click does nothing
  local r = Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true)
  ClickAuctionSellItemButton = keep
  T.eq(r, false)
  noPost("not in the slot")
  T.ok(T.calledWith("The item didn't reach the sell slot. Try again."))
  slotFree()
end)

T.test("Post refuses when the sell slot holds a different count (Review I1)", function()
  stock() WoW.money = 100000
  local keep = ClickAuctionSellItemButton
  ClickAuctionSellItemButton = function() keep() if WoW.sellSlot then WoW.sellSlot.count = 14 end end
  local r = Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true)
  ClickAuctionSellItemButton = keep
  T.eq(r, false)
  noPost("wrong count in the slot")
  slotFree()
end)

T.test("a nil client deposit does not raise or block the post (Review I1)", function()
  stock() WoW.money = 100000
  local keep = CalculateAuctionDeposit
  CalculateAuctionDeposit = function() return nil end
  local ok, r = pcall(Auction.Post, 0, 1, 20, 100, 200, 480, "14047:0", true)
  CalculateAuctionDeposit = keep
  T.ok(ok, "raised: " .. tostring(r))
  T.eq(r, true)
  T.eq(T.count("StartAuction"), 1)
end)

T.test("no reply to a post within 5 seconds releases the lock", function()
  stock() WoW.money = 100000
  WoW.ah.postReply = "none"
  Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true)
  WoW.postRespond()
  WoW.clock = WoW.clock + 4.9
  frame()
  T.ok(Auction.busy)
  WoW.clock = WoW.clock + 0.1
  frame()
  T.eq(Auction.busy, false)
  T.ok(T.calledWith("No reply from the auction house. Check the Auctions tab."))
end)

T.test("ERR_AUCTION_STARTED is accepted on UI_ERROR_MESSAGE, and a bid reply does not end a post", function()
  stock() WoW.money = 100000
  Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true)
  WoW.fire("CHAT_MSG_SYSTEM", ERR_AUCTION_BID_PLACED)
  T.ok(Auction.busy, "wrong success text for a post")
  WoW.fire("UI_ERROR_MESSAGE", ERR_AUCTION_STARTED)
  T.eq(Auction.busy, false)
end)

T.test("a post blocks a buy, and a pending buy blocks a post", function()
  stock() WoW.money = 100000
  Auction.busy = { kind = "buy", at = GetTime(), after = false, onFail = false }
  T.eq(Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true), false)
  T.eq(Auction.Split(0, 1, 5), nil)
  T.eq(Auction.Cancel(1, { key = "x", count = 1, buyout = 1 }), false)
  T.eq(T.count("StartAuction") + T.count("SplitContainerItem") + T.count("CancelAuction"), 0)
end)

-- ---------- Split ----------

T.test("Split moves part of a stack into an empty slot, with no lock", function()
  stock()
  T.eq(Auction.Split(0, 1, 5), true)
  T.ok(T.calledWith("SplitContainerItem 0 1 5"))
  T.ok(T.calledWith("PickupContainerItem 0 2"))
  T.eq(Auction.busy, false, "the lock is not taken")
  local _, c1 = GetContainerItemInfo(0, 1)
  local _, c2 = GetContainerItemInfo(0, 2)
  T.eq(c1, 15) T.eq(c2, 5)
end)

T.test("Split with no empty slot, or an impossible size, makes no call", function()
  stock()
  WoW.bags[0] = { { id = 14047, name = "Runecloth", count = 20 }, { id = 2589, name = "Linen Cloth", count = 3 } }
  local ok, why = Auction.Split(0, 1, 5)
  T.eq(ok, nil)
  T.eq(why, "No empty slot in a normal bag to split into.")
  T.ok(T.calledWith("No empty slot in a normal bag to split into."))
  T.eq(T.count("SplitContainerItem"), 0)
  stock()
  T.eq((Auction.Split(0, 1, 20)), nil, "the whole stack is not a split")
  T.eq((Auction.Split(0, 1, 0)), nil)
  T.eq((Auction.Split(0, 3, 5)), nil, "an empty slot")
  T.eq(T.count("SplitContainerItem"), 0)
end)

T.test("Split finds an empty slot in a later bag", function()
  stock()
  WoW.bags[0] = { { id = 14047, name = "Runecloth", count = 20 } }
  WoW.bags[1] = { { id = 2589, name = "Linen Cloth", count = 3 }, {} }
  T.eq(Auction.Split(0, 1, 5), true)
  T.ok(T.calledWith("PickupContainerItem 1 2"))
end)

-- ---------- Cancel ----------

T.test("OwnerRow reads an owner row in the shape of Scan.ReadRow", function()
  owned({ { id = 14047, name = "Runecloth", count = 20, buyout = 4000, minBid = 3600, bid = 3700, quality = 1 } })
  local r = Auction.OwnerRow(1)
  T.eq(r.key, "14047:0") T.eq(r.name, "Runecloth") T.eq(r.count, 20) T.eq(r.buyout, 4000) T.eq(r.bid, 3700)
  T.eq(r.minBid, 3600) T.eq(r.unit, 200) T.eq(r.index, 1) T.eq(r.owner, "Bankalt")
  T.eq(Auction.OwnerRow(2), nil)
end)

T.test("Cancel re-verifies the row, cancels once, and re-requests the owner list on success", function()
  owned({ { id = 14047, name = "Runecloth", count = 20, buyout = 4000, minBid = 3600 } })
  local s = osig(1)
  local after = 0
  T.eq(Auction.Cancel(1, s, function() after = after + 1 end), true)
  T.ok(T.calledWith("CancelAuction 1"))
  T.eq(Auction.busy.kind, "cancel")
  T.eq(Auction.Cancel(1, s), false, "a second click")
  T.eq(T.count("CancelAuction"), 1)
  T.eq(T.count("GetOwnerAuctionItems"), 1, "only the setup request so far")
  WoW.cancelRespond()
  T.eq(Auction.busy, false)
  T.eq(after, 1)
  T.eq(T.count("GetOwnerAuctionItems"), 2, "re-requested")
  WoW.ownerRespond()
  T.eq(GetNumAuctionItems("owner"), 0)
  T.ok(T.calledWith("Cancelled Runecloth x20"))
end)

T.test("Cancel refuses a row that changed", function()
  owned({ { id = 14047, name = "Runecloth", count = 20, buyout = 4000 },
          { id = 14047, name = "Runecloth", count = 20, buyout = 5000 } })
  local s = osig(1)
  T.eq(Auction.Cancel(2, s), false, "row 2 is not what was selected")
  T.eq(Auction.Cancel(3, s), false, "no row 3")
  T.eq(T.count("CancelAuction"), 0)
  T.ok(T.calledWith("Auction changed"))
  T.eq(T.count("GetOwnerAuctionItems"), 3, "setup request, plus one for each of the two refusals (Review M3)")
end)

T.test("Cancelling an auction that has a bid asks first (Review Focus 4)", function()
  owned({ { id = 14047, name = "Runecloth", count = 20, buyout = 4000, minBid = 3600, bid = 3700, quality = 1 } })
  local after = 0
  T.eq(Auction.Cancel(1, osig(1), function() after = after + 1 end), "confirm")
  T.eq(T.count("CancelAuction"), 0, "the first click cancels nothing")
  T.ok(Confirm.frame:IsShown())
  T.ok(string.find(Confirm.frame.lines[3]:GetText(), "bidder", 1, true), "warns about the bidder and deposit")
  WoW.runScript(Confirm.frame.buy, "OnClick")
  T.eq(T.count("CancelAuction"), 1)
  T.ok(T.calledWith("CancelAuction 1"))
  T.eq(Confirm.frame:IsShown(), false)
  WoW.runScript(Confirm.frame.buy, "OnClick")
  T.eq(T.count("CancelAuction"), 1, "a stray second click")
  WoW.cancelRespond()
  T.eq(after, 1)
end)

T.test("closing the cancel window cancels nothing; and the buy confirmation still works afterwards", function()
  owned({ { id = 14047, name = "Runecloth", count = 20, buyout = 4000, bid = 3700 } })
  Auction.Cancel(1, osig(1))
  WoW.runScript(Confirm.frame.cancel, "OnClick")
  T.eq(Confirm.Buy(), false, "nothing pending")
  T.eq(T.count("CancelAuction"), 0)
  WoW.money = 1000000
  WoW.ah.listings = { { id = 14047, name = "Runecloth", count = 20, buyout = 60000 } }
  QueryAuctionItems("", "", "", nil, nil, nil, 0, nil, nil)
  WoW.ahRespond()
  T.eq(Auction.Buy(1, Auction.Sig(Scan.ReadRow(1))), "confirm")
  T.eq(Confirm.frame.header.title:GetText(), "CONFIRM PURCHASE")
  WoW.runScript(Confirm.frame.buy, "OnClick")
  T.eq(T.count("PlaceAuctionBid"), 1)
  T.eq(T.count("CancelAuction"), 0)
end)

T.test("a cancel failure or silence releases the lock", function()
  owned({ { id = 14047, name = "Runecloth", count = 20, buyout = 4000 } })
  WoW.ah.cancelReply = "none"
  Auction.Cancel(1, osig(1))
  WoW.cancelRespond()
  WoW.clock = WoW.clock + 5
  frame()
  T.eq(Auction.busy, false)
  T.ok(T.calledWith("No reply from the auction house. Check the Auctions tab."), "post and cancel point at the Auctions tab")
  T.eq(T.calledWith("Search again to see"), false, "not the buy wording")
  local failed = nil
  WoW.ah.cancelReply = "auto"
  WoW.ah.listings = {}                                  -- already gone on the server
  Auction.Cancel(1, osig(1), nil, function(t) failed = t end)
  WoW.cancelRespond()
  T.eq(Auction.busy, false)
  T.eq(failed, ERR_ITEM_NOT_FOUND)
end)

-- ---------- one click ----------

T.test("events, ticks and list updates never post, cancel, split or bid", function()
  stock() WoW.money = 100000
  owned({ { id = 14047, name = "Runecloth", count = 20, buyout = 4000, bid = 100 } })
  WoW.fire("BAG_UPDATE") WoW.fire("PLAYER_MONEY") WoW.fire("AUCTION_OWNED_LIST_UPDATE")
  WoW.fire("AUCTION_ITEM_LIST_UPDATE") WoW.fire("CHAT_MSG_SYSTEM", ERR_AUCTION_STARTED)
  WoW.fire("CHAT_MSG_SYSTEM", ERR_AUCTION_REMOVED)
  frame()
  WoW.clock = WoW.clock + 60
  frame()
  T.eq(T.count("StartAuction") + T.count("CancelAuction") + T.count("SplitContainerItem")
    + T.count("PlaceAuctionBid"), 0)
end)

-- Bag 1 is a quiver or soul bag with a free slot; the only other free slot (if any) is elsewhere.
local function specialBag(subtype)
  WoW.items[2101] = { name = "Quiver", type = "Container", subtype = subtype }
  WoW.equip[20] = { id = 2101, name = "Quiver" }
end

T.test("Split skips quivers and soul bags", function()
  stock()
  WoW.bags[0] = { { id = 14047, name = "Runecloth", count = 20 } }
  WoW.bags[1] = { {} }
  for _, sub in ipairs({ "Quiver", "Ammo Pouch", "Soul Bag", "Herb Bag", "Enchanting Bag" }) do
    WoW.calls = {}
    specialBag(sub)
    local ok, why = Auction.Split(0, 1, 5)
    T.eq(ok, nil, sub)
    T.eq(why, "No empty slot in a normal bag to split into.")
    T.eq(T.count("SplitContainerItem"), 0, sub)
  end
  WoW.bags[2] = { {} }                                   -- a bag with no known type counts as normal
  T.eq(Auction.Split(0, 1, 5), true)
  T.ok(T.calledWith("PickupContainerItem 2 1"), "went past the quiver")
  WoW.calls = {}
  WoW.bags[0] = { { id = 14047, name = "Runecloth", count = 20 } }
  WoW.items[2101].subtype = "Bag"
  T.eq(Auction.Split(0, 1, 5), true)
  T.ok(T.calledWith("PickupContainerItem 1 1"), "a plain Bag is general")
end)

-- Review I2: real servers often send the money change after the chat reply.
local function lateMoney() WoW.ah.moneyLate = true end

T.test("money arriving after the reply still teaches the deposit (Review I2)", function()
  stock() WoW.money = 100000
  TaxTheFoolsDB.items[14047] = { v = 100 }
  lateMoney()
  Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true)
  WoW.postRespond()                                      -- the reply; the money has not moved
  T.eq(Auction.busy, false)
  T.eq(WoW.money, 100000)
  T.eq(DB.Char().postings[1].deposit, nil, "unknown at the reply")
  WoW.clock = WoW.clock + 1.5
  WoW.moneyArrive()                                      -- 1200 x 0.6 = 720 leaves, PLAYER_MONEY fires
  T.eq(WoW.money, 100000 - 720)
  -- 720 against the estimate floor(100 x 20 x 4 x 1 x 0.025) = 200: 3.6x, inside 0.25x - 4x (50 - 800).
  T.eq(DB.Char().postings[1].deposit, 720, "the log entry is filled in")
  T.eq(Sell.Deposit(TaxTheFoolsDB.items, 14047, 480, 20, 20), 720)
  -- a second money event teaches nothing more
  WoW.money = WoW.money - 5000
  WoW.fire("PLAYER_MONEY")
  T.eq(Sell.Deposit(TaxTheFoolsDB.items, 14047, 480, 20, 20), 720)
end)

T.test("a late money change after 3 seconds teaches nothing (Review I2)", function()
  stock() WoW.money = 100000
  lateMoney()
  Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true)
  WoW.postRespond()
  WoW.clock = WoW.clock + 3.1
  WoW.moneyArrive()
  T.eq(DB.Char().postings[1].deposit, nil)
  T.eq(TaxTheFoolsDB.items[14047] and TaxTheFoolsDB.items[14047].dep, nil)
end)

T.test("a deposit outside 0.25x - 4x of the estimate is not learned (Review I2)", function()
  TaxTheFoolsDB.items[14047] = { v = 100 }
  -- estimate 200 for 20 x 480: the band is 50 to 800. The fake server charges 1200 x factor.
  for _, c in ipairs({ { 0.01, "12 is under 50" }, { 1, "1200 is over 800" } }) do
    stock() WoW.money = 100000
    WoW.ah.depositFactor = c[1]
    WoW.ah.moneyLate = true
    Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true)
    WoW.postRespond()
    WoW.moneyArrive()
    T.eq(DB.Char().postings[table.getn(DB.Char().postings)].deposit, nil, c[2] .. ": logged as nil (late)")
    T.eq(TaxTheFoolsDB.items[14047].dep, nil, c[2] .. ": not learned (late)")
    -- and money before the reply
    stock() WoW.money = 100000
    WoW.ah.moneyLate = false
    Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true)
    WoW.postRespond()
    T.eq(DB.Char().postings[table.getn(DB.Char().postings)].deposit, nil, c[2] .. ": logged as nil (early)")
    T.eq(TaxTheFoolsDB.items[14047].dep, nil, c[2] .. ": not learned (early)")
  end
end)

T.test("a stack learned full predicts a single correctly (Review I2)", function()
  stock() WoW.money = 100000
  Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true)
  WoW.postRespond()                                      -- 720 for a full stack of 20 (max 20)
  -- base 720 / (20 x 1) = 36; one unit: 36 x 1 x (1 + (20-1) x 0.05) = 36 x 1.95 = 70.2 -> 70
  T.eq(Sell.Deposit(TaxTheFoolsDB.items, 14047, 480, 1, 20), 70)
end)

T.test("starting another post drops a pending learn (Review I2)", function()
  stock() WoW.money = 100000
  lateMoney()
  Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true)
  WoW.postRespond()
  stock() WoW.ah.moneyLate = false
  Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true)
  WoW.postRespond()
  WoW.fire("PLAYER_MONEY")
  T.eq(DB.Char().postings[1].deposit, nil, "the first post's entry is not given the second one's money")
  T.eq(DB.Char().postings[2].deposit, 720)
end)

T.test("a learned deposit that can't be paid refuses before any pickup", function()
  stock() WoW.money = 719
  Sell.LearnDeposit(TaxTheFoolsDB.items, 14047, 480, 720, 20, 20)   -- 720
  T.eq(Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true), false)
  T.eq(T.count("PickupContainerItem") + T.count("ClearCursor") + T.count("StartAuction"), 0)
end)

T.test("an unknown deposit (no money change at the reply) is logged as nil and not learned", function()
  stock() WoW.money = 100000
  Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true)
  WoW.ah.postReply = "none"
  Auction.OnMessage(ERR_AUCTION_STARTED)                 -- the reply, with the money unchanged
  T.eq(Auction.busy, false)
  T.eq(DB.Char().postings[1].deposit, nil)
  T.eq(TaxTheFoolsDB.items[14047] and TaxTheFoolsDB.items[14047].dep, nil)
end)
