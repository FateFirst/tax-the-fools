local A = TaxTheFools
local UI, AH, Scan, DB, Auction, Sell, Inv = A.UI, A.AH, A.Scan, A.DB, A.Auction, A.Sell, A.Inventory
local SellUI = A.SellUI

local function openAH()
  UI.CreateAH()
  if UI.ah.tabs.selected then UI.ah.tabs:Select("browse") end
  AH.switching = true
  UI.ah:Hide()
  AH.switching = false
  AH.open = true
  AH.ShowOurs()
end

local function answer()
  for _ = 1, 40 do
    WoW.clock = WoW.clock + 0.5
    Scan.Tick(WoW.clock)
    if WoW.ah.pending then
      WoW.ahRespond()
      Scan.OnListUpdate(WoW.clock)
    end
    if not Scan.job then return end
  end
end

local function bagsUpdate()
  WoW.clock = WoW.clock + 2
  Inv.Tick(WoW.clock)
end

-- Runecloth 14047 (market 1000, floor 800, vendor 100), Linen 2589 (no market), stacks of 20.
local function seed(bags)
  WoW.items[14047] = { name = "Runecloth", stack = 20, quality = 1, tex = "rune" }
  WoW.items[2589] = { name = "Linen Cloth", stack = 20, quality = 1, tex = "linen" }
  WoW.items[4306] = { name = "Silk Cloth", stack = 20, quality = 1, tex = "silk" }
  DB.Realm().market["14047:0"] = { v = 1000, conf = 0.8 }
  WoW.bags[0] = bags or { { id = 14047, name = "Runecloth", count = 20, vendor = 100 }, {}, {}, {} }
  WoW.bags[1], WoW.bags[2], WoW.bags[3], WoW.bags[4] = nil, nil, nil, nil
  WoW.money = 1000000
end

local function page()
  openAH()
  UI.ah.tabs:Select("sell")
  local p = UI.pages.sell
  p.list:SetHeight(200)
  p:Refresh()
  return p
end

local function click(b) WoW.runScript(b, "OnClick") end

local function cell(p, name)
  for _, c in ipairs(p.cells) do
    if c.item and c.item.name == name then return c end
  end
  return nil
end

local function pick(p, name)
  local c = cell(p, name)
  click(c)
  answer()
  return c
end

local function compete(id, name, count, buyout, owner)
  table.insert(WoW.ah.listings, { id = id, name = name, count = count, buyout = buyout, minBid = 1, owner = owner or "Rival" })
end

T.test("Sell sits third in the tabs and Browse is still selected on open", function()
  T.eq(UI.TABS[3].key, "sell") T.eq(UI.TABS[5].key, "craft")
  openAH()
  T.eq(UI.ah.tabs.selected, "browse")
  T.ok(UI.builders.sell)
end)

T.test("a tab whose builder is missing is left out of the strip and ShowPage ignores it", function()
  local keep = UI.builders.auctions
  UI.builders.auctions = nil
  local keys = {}
  for _, t in ipairs(UI.VisibleTabs()) do table.insert(keys, t.key) end
  T.eq(table.concat(keys, ","), "deals,browse,sell,craft")
  openAH()
  UI.ah.tabs:Select("browse")
  T.eq(UI.ShowPage("auctions"), false)
  T.ok(UI.pages.browse:IsShown(), "the current page stays")
  UI.builders.auctions = keep
end)

T.test("the grid combines slots, sorts by name and shows only auctionable items", function()
  seed({ { id = 14047, name = "Runecloth", count = 10, vendor = 100 }, { id = 2589, name = "Linen Cloth", count = 5 },
         { id = 14047, name = "Runecloth", count = 7, vendor = 100 }, { id = 4306, name = "Silk Cloth", count = 3 } })
  local keep, tip, soul = Sell.TipLines, nil, getglobal("ITEM_SOULBOUND")
  setglobal("ITEM_SOULBOUND", "Soulbound")
  Sell.TipLines = function(bag, slot)
    if bag == 0 and slot == 4 then return { "Silk Cloth", "Soulbound" } end
    return { "x" }
  end
  local p = page()
  Sell.TipLines = keep
  setglobal("ITEM_SOULBOUND", soul)
  T.eq(table.getn(p.items), 2)
  T.eq(p.items[1].name, "Linen Cloth") T.eq(p.items[1].total, 5)
  T.eq(p.items[2].name, "Runecloth") T.eq(p.items[2].total, 17)
  T.eq(p.cells[2].count:GetText(), "17")
  T.eq(p.cells[3].item, false)
end)

T.test("selecting an item searches the auction house by name and lists only that item", function()
  seed()
  compete(14047, "Runecloth", 10, 9000)
  compete(14047, "Runecloth", 5, 5500, "Bankalt")
  compete(2589, "Linen Cloth", 1, 100)
  local p = page()
  click(cell(p, "Runecloth"))
  T.ok(Scan.Busy() and Scan.job.kind == "browse", "a browse job started")
  answer()
  T.ok(T.calledWith("QueryAuctionItems [Runecloth]"), "searched by name")
  T.eq(table.getn(p.list.data), 2)
  local mine, theirs
  for _, r in ipairs(p.list.data) do if r.mine then mine = r else theirs = r end end
  T.eq(theirs.unit, 900) T.eq(theirs.pct, 90) T.eq(theirs.count, 10)
  T.ok(mine and mine.owner == "Bankalt")
  T.eq(p.list.columns[4].fmt(mine), "you")
  T.eq(p.sourceText:GetText(), "undercut")
end)

T.test("the suggested buyout and bid undercut the cheapest competitor above the floor", function()
  seed()
  compete(14047, "Runecloth", 10, 9000)
  compete(14047, "Runecloth", 10, 5000)          -- 500 each: under the 800 floor, ignored
  local p = page()
  pick(p, "Runecloth")
  T.eq(p.buyoutIn:GetValue(), 899)
  T.eq(p.bidIn:GetValue(), 809)
end)

T.test("with no listings the market value is suggested; vendor x3 and 'set a price' are the weak sources", function()
  seed({ { id = 14047, name = "Runecloth", count = 20, vendor = 100 }, { id = 2589, name = "Linen Cloth", count = 5, vendor = 7 },
         { id = 4306, name = "Silk Cloth", count = 3 } })
  A.Items.Remember(2589, "Linen Cloth", 1, 20).v = 7
  local p = page()
  pick(p, "Runecloth")
  T.eq(p.buyoutIn:GetValue(), 1000) T.eq(p.sourceText:GetText(), "market")
  pick(p, "Linen Cloth")
  T.eq(p.buyoutIn:GetValue(), 21) T.eq(p.sourceText:GetText(), "vendor x3")
  T.eq(A.Theme.registry[p.sourceText].token, "warn")
  pick(p, "Silk Cloth")
  T.eq(p.buyoutIn:GetValue(), nil) T.eq(p.sourceText:GetText(), "set a price")
  T.eq(p.postBtn.enabled, false)
end)

T.test("a scan in progress refuses the search and prices from the snapshot", function()
  seed()
  DB.Realm().snapshot = { at = time(), day = A.Util.day(time()), rows = { ["14047:0"] = { "10|9500|0|Rival", "1|100|0|Cheap" } } }
  local p = page()
  Scan.StartFull(WoW.clock)
  WoW.calls = {}
  click(cell(p, "Runecloth"))
  T.eq(T.count("QueryAuctionItems"), 0)
  T.eq(p.buyoutIn:GetValue(), 949)
  T.eq(table.getn(p.list.data), 2)
  T.ok(T.calledWith("A scan is using the auction house"), "says why")
end)

T.test("a search that gets no reply falls back to the snapshot", function()
  seed()
  DB.Realm().snapshot = { at = time(), day = A.Util.day(time()), rows = { ["14047:0"] = { "10|9500|0|Rival" } } }
  local p = page()
  click(cell(p, "Runecloth"))
  for _ = 1, 200 do WoW.clock = WoW.clock + 1 Scan.Tick(WoW.clock) end
  T.ok(not Scan.job)
  T.eq(p.buyoutIn:GetValue(), 949)
end)

T.test("stack size defaults to what fits and stacks to the most possible", function()
  seed({ { id = 14047, name = "Runecloth", count = 20, vendor = 100 }, { id = 14047, name = "Runecloth", count = 5, vendor = 100 } })
  local p = page()
  pick(p, "Runecloth")
  T.eq(p.stackSize, 20) T.eq(p.nStacks, 1)
  p.sizeBox:SetText("5") WoW.runScript(p.sizeBox, "OnTextChanged")
  T.eq(p.stackSize, 5) T.eq(p.nStacks, 5)
  p.countBox:SetText("99") WoW.runScript(p.countBox, "OnTextChanged")
  T.eq(p.nStacks, 5)
  p.sizeBox:SetText("500") WoW.runScript(p.sizeBox, "OnTextChanged")
  T.eq(p.stackSize, 20)
end)

T.test("deposit, after-cut and the post button read from the chosen stack and duration", function()
  seed()
  A.Items.Remember(14047, "Runecloth", 1, 20).v = 100
  local p = page()
  pick(p, "Runecloth")
  p.sizeBox:SetText("10") WoW.runScript(p.sizeBox, "OnTextChanged")
  T.ok(string.find(p.depositText:GetText(), "approx", 1, true))
  local est = A.Craft.Deposit(100, 20, 10, 480, 1)
  T.eq(est, 150)
  T.eq(p.depositText:GetText(), "Deposit approx " .. A.Util.money(est, true))
  T.eq(UI.ShowPage("sell"), true)
  -- learned deposit wins
  A.Sell.LearnDeposit(TaxTheFoolsDB.items, 14047, 480, 4)
  p:Refresh()
  T.eq(p.depositText:GetText(), "Deposit " .. A.Util.money(40, true))
  T.eq(p.netText:GetText(), "You receive " .. A.Util.money(1000 * 10 * 0.95 - 40, true))
end)

T.test("Split then Post: the button splits into an empty slot, then posts that stack", function()
  seed()
  local p = page()
  pick(p, "Runecloth")
  p.sizeBox:SetText("5") WoW.runScript(p.sizeBox, "OnTextChanged")
  T.eq(p.postBtn.label:GetText(), "SPLIT")
  WoW.calls = {}
  T.eq(T.count("StartAuction"), 0)
  click(p.postBtn)
  T.eq(T.count("SplitContainerItem"), 1)
  T.eq(T.count("StartAuction"), 0)
  T.eq(p.postBtn.enabled, false, "waits for the bags")
  bagsUpdate()
  T.eq(p.postBtn.label:GetText(), "POST 1 OF 4")
  T.eq(p.postBtn.enabled, true)
  click(p.postBtn)
  T.eq(T.count("StartAuction"), 1)
  T.ok(T.calledWith("StartAuction 4500 5000 480"), "total bid and buyout")
end)

T.test("Post sends the totals for the stack and duration, and Auctions is asked to refresh", function()
  seed({ { id = 14047, name = "Runecloth", count = 5, vendor = 100 }, { id = 14047, name = "Runecloth", count = 5, vendor = 100 },
         { id = 14047, name = "Runecloth", count = 5, vendor = 100 } })
  local p = page()
  pick(p, "Runecloth")
  p.sizeBox:SetText("5") WoW.runScript(p.sizeBox, "OnTextChanged")
  T.eq(p.nStacks, 3)
  click(p.durBtns[1440])
  T.eq(p.minutes, 1440)
  p.buyoutIn.gold:SetText("") p.buyoutIn.silver:SetText("10") p.buyoutIn.copper:SetText("0")
  WoW.runScript(p.buyoutIn.copper, "OnTextChanged")
  T.eq(p.bidIn:GetValue(), 900, "bid follows the buyout")
  local asked = 0
  local keep = A.AuctionsUI and A.AuctionsUI.Request
  A.AuctionsUI.Request = function() asked = asked + 1 end
  WoW.calls = {}
  click(p.postBtn)
  T.ok(T.calledWith("StartAuction 4500 5000 1440"), "5 x 1000 buyout, bid 900 each")
  WoW.postRespond()
  A.AuctionsUI.Request = keep
  T.eq(asked, 1)
  T.eq(p.status:GetText(), "1 of 3 posted")
  T.eq(p.postBtn.label:GetText(), "POST 2 OF 3")
  T.eq(table.getn(DB.Char().postings), 1)
end)

T.test("the default duration comes from settings", function()
  seed()
  DB.S().sell.duration = 1440
  local p = page()
  pick(p, "Runecloth")
  T.eq(p.minutes, 1440)
  T.eq(p.durBtns[1440].picked, true) T.eq(p.durBtns[480].picked, false)
  T.eq(p.durBtns[120].label:GetText(), "6H")
end)

T.test("a buyout under the floor blocks Post until Allow below floor is ticked, and it resets per item", function()
  seed({ { id = 14047, name = "Runecloth", count = 20, vendor = 100 }, { id = 2589, name = "Linen Cloth", count = 20, vendor = 7 } })
  local p = page()
  pick(p, "Runecloth")
  p.buyoutIn:SetValue(500)
  WoW.runScript(p.buyoutIn.gold, "OnTextChanged")
  T.eq(p.floorText:GetText(), "Below your floor (80% of market)")
  T.eq(p.postBtn.enabled, false)
  click(p.allowSw)
  T.eq(p.allowBelow, true)
  T.eq(p.postBtn.enabled, true)
  -- another item: the override is off again
  pick(p, "Linen Cloth")
  T.eq(p.allowBelow, false) T.eq(p.allowSw.on, false)
  -- and back: Runecloth starts clean too
  pick(p, "Runecloth")
  T.eq(p.allowBelow, false)
  p.buyoutIn:SetValue(500)
  WoW.runScript(p.buyoutIn.gold, "OnTextChanged")
  T.eq(p.postBtn.enabled, false)
  -- the engine agrees: a refused post makes no StartAuction
  WoW.calls = {}
  click(p.postBtn)
  T.eq(T.count("StartAuction"), 0)
end)

T.test("the override is handed to Auction.Post and lets a below-floor post through", function()
  seed()
  local p = page()
  pick(p, "Runecloth")
  p.buyoutIn:SetValue(500)
  WoW.runScript(p.buyoutIn.gold, "OnTextChanged")
  click(p.allowSw)
  WoW.calls = {}
  click(p.postBtn)
  T.eq(T.count("StartAuction"), 1)
end)

T.test("a reply that fails shows on the status line and the stack count does not move", function()
  seed()
  WoW.ah.postReply = "limited"
  local p = page()
  pick(p, "Runecloth")
  click(p.postBtn)
  WoW.postRespond()
  T.eq(p.status:GetText(), ERR_AUCTION_LIMITED_DURATION_ITEM)
  T.eq(p.posted, 0)
end)

T.test("opening Sell, selecting and searching never spend: only the click does", function()
  seed()
  compete(14047, "Runecloth", 10, 9000)
  local p = page()
  pick(p, "Runecloth")
  bagsUpdate()
  for _, name in ipairs({ "StartAuction", "CancelAuction", "SplitContainerItem", "PlaceAuctionBid" }) do
    T.eq(T.count(name), 0, name)
  end
  click(p.postBtn)
  T.eq(T.count("StartAuction"), 1)
end)
