local A = TaxTheFools
local UI, AH, Scan, DB, Auction, Q = A.UI, A.AH, A.Scan, A.DB, A.Auction, A.Quick
local SellUI, StockUI, L = A.SellUI, A.StockUI, A.List
local QuickUI = A.QuickUI

local function openAH()
  UI.CreateAH()
  if UI.ah.tabs.selected then UI.ah.tabs:Select("browse") end
  AH.switching = true
  UI.ah:Hide()
  AH.switching = false
  AH.open = true
  AH.ShowOurs()
end

local function click(b) WoW.runScript(b, "OnClick") end

local function pump()
  for _ = 1, 200 do
    WoW.clock = WoW.clock + 0.5
    Scan.Tick(WoW.clock)
    if WoW.ah.pending then
      WoW.ahRespond()
      Scan.OnListUpdate(WoW.clock)
    end
    if not Scan.job then return end
  end
end

local function list(id, name, n, buyout, count)
  for i = 1, n do
    table.insert(WoW.ah.listings, { id = id, name = name, count = count or 20, buyout = buyout + i, minBid = 1, owner = "S" .. i })
  end
end

-- Bags: Runecloth 20 + 7 (undercut), Mageweave 10 (at floor), Linen 5 (vendor only), Silk 3 (no price).
local function seed(bags)
  WoW.items[14047] = { name = "Runecloth", stack = 20, quality = 1, tex = "rune" }
  WoW.items[4338] = { name = "Mageweave Cloth", stack = 20, quality = 1, tex = "mage" }
  WoW.items[2589] = { name = "Linen Cloth", stack = 20, quality = 1, tex = "linen" }
  WoW.items[4306] = { name = "Silk Cloth", stack = 20, quality = 1, tex = "silk" }
  TaxTheFoolsDB.items[2589] = { n = "Linen Cloth", v = 10, st = 20 }
  DB.Realm().market["4338:0"] = { v = 1000, conf = 0.8 }
  -- Ten days at 1000 keep the market (and so the 800 floor) where it is after the scan adds today.
  local days = {}
  for d = 20365, 20374 do days[d] = { p25 = 1000, min = 1000, n = 5 } end
  DB.Realm().history["4338:0"] = { days = days, months = {} }
  WoW.bags[0] = bags or { { id = 14047, name = "Runecloth", count = 20 }, { id = 14047, name = "Runecloth", count = 7 },
    { id = 4338, name = "Mageweave Cloth", count = 10 }, { id = 2589, name = "Linen Cloth", count = 5 },
    { id = 4306, name = "Silk Cloth", count = 3 }, {}, {} }
  WoW.bags[1], WoW.bags[2], WoW.bags[3], WoW.bags[4] = nil, nil, nil, nil
  WoW.money = 1000000
  list(14047, "Runecloth", 3, 8000)
  list(4338, "Mageweave Cloth", 1, 7999, 10)     -- 800 each: exactly the floor
  TaxTheFoolsCharDB.sellView = "bags"
end

local function page()
  openAH()
  UI.ah.tabs:Select("sell")
  local p = UI.pages.sell
  p:Refresh()
  StockUI.SetView(p, "quick")
  p.quick.list:SetWidth(628)
  p.quick.list:SetHeight(300)
  p.quick.list:Paint()
  return p, p.quick
end

local function scanned()
  local p, q = page()
  click(q.scanBtn)
  pump()
  return p, q
end

local function rowOf(q, name, count)
  for _, r in ipairs(q.list.data) do
    if r.name == name and (not count or r.count == count) then return r end
  end
end

local function statusOf(r) return (QuickUI.StatusText(r)) end

T.test("the Quick view is a fourth view: it hides the grid and the pricing panel and is remembered", function()
  seed()
  local p, q = page()
  T.eq(p.view, "quick")
  T.eq(TaxTheFoolsCharDB.sellView, "quick")
  T.ok(q:IsShown())
  T.ok(not p.cells[1]:IsShown() and not p.postBtn:IsShown() and not p.list:IsShown() and not p.title:IsShown()
    and not p.chart:IsShown() and not p.rlist:IsShown() and not p.slist:IsShown())
  click(p.viewBtns.bags)
  T.ok(not q:IsShown())
  T.ok(p.cells[1]:IsShown() and p.postBtn:IsShown())
  click(p.viewBtns.quick)
  T.ok(q:IsShown())
  TaxTheFoolsCharDB.sellView = "bags"
end)

T.test("before a scan the bag rows show 'scan for prices' and Post next is disabled", function()
  seed()
  local p, q = page()
  T.eq(table.getn(q.list.data), 5)
  T.eq(statusOf(q.list.data[1]), "scan for prices")
  T.eq(q.postBtn.enabled, false)
  T.eq(q.postBtn.label:GetText(), "POST NEXT")
  T.eq(q.skipBtn.enabled, false)
  T.eq(q.statusText:GetText(), "Scan your bags to price them.")
end)

T.test("Scan bags prices every row; the status shows progress, then the age of the prices", function()
  seed()
  local p, q = page()
  click(q.scanBtn)
  T.eq(Q.state, "scanning")
  T.eq(q.statusText:GetText(), "Scanning 1 of 4...")
  T.eq(q.postBtn.enabled, false)
  pump()
  T.eq(Q.state, "ready")
  T.eq(q.statusText:GetText(), "Prices from just now")
  WoW.now = WoW.now + 125
  QuickUI.Paint()
  T.eq(q.statusText:GetText(), "Prices from 2m ago")
  T.eq(table.getn(q.list.data), 5)
  T.eq(statusOf(rowOf(q, "Mageweave Cloth")), "at floor")
  T.eq(statusOf(rowOf(q, "Linen Cloth")), "vendor x3")
  T.eq(statusOf(rowOf(q, "Silk Cloth")), "no price")
  T.eq(statusOf(rowOf(q, "Runecloth", 20)), "")
  T.eq(rowOf(q, "Linen Cloth").unit, 30)
  T.eq(q.postBtn.enabled, true)
  T.eq(UI.KIND_LABEL.quick, "Bag prices")
end)

T.test("a scan refused because another scan runs says why", function()
  seed()
  local p, q = page()
  Scan.StartFull(WoW.clock)
  click(q.scanBtn)
  T.eq(Q.state, "idle")
  T.eq(q.statusText:GetText(), "Another scan is running. Wait for it, or pause it, first.")
end)

T.test("the highlight starts on the first postable row and passes over vendor rows with the box off", function()
  seed()
  local p, q = scanned()
  -- Linen (vendor) is first by name, but the box is off.
  T.eq(QuickUI.Cur().name, "Mageweave Cloth")
  T.ok(q.list.selected == QuickUI.Cur(), "painted as the selected row")
end)

T.test("Focus 1 and 2: each Post next click is one StartAuction; the highlight moves only on the reply", function()
  seed()
  local p, q = scanned()
  local mage = rowOf(q, "Mageweave Cloth")
  local r20, r7 = rowOf(q, "Runecloth", 20), rowOf(q, "Runecloth", 7)
  T.eq(r20.unit, r7.unit)
  local queries = T.count("QueryAuctionItems")
  WoW.calls = {}
  click(q.postBtn)
  T.eq(T.count("StartAuction"), 1)
  T.ok(T.calledWith("StartAuction " .. mage.bid * 10 .. " " .. 8000 .. " 480"), "at the floor, 10 x 800")
  T.eq(q.postBtn.label:GetText(), "WAITING...")
  T.ok(QuickUI.Cur() == mage, "still on the posted row")
  click(q.postBtn)
  click(q.postBtn)
  T.eq(T.count("StartAuction"), 1, "clicks while waiting send nothing")
  T.ok(QuickUI.Cur() == mage)
  WoW.postRespond()
  T.eq(mage.done, "posted")
  T.eq(statusOf(mage), "Posted")
  T.ok(QuickUI.Cur() == r20, "moved on after the reply")
  T.eq(q.postBtn.label:GetText(), "POST NEXT")
  click(q.postBtn)
  T.eq(T.count("StartAuction"), 2)
  T.ok(T.calledWith("StartAuction " .. r20.bid * 20 .. " " .. r20.unit * 20 .. " 480"))
  WoW.postRespond()
  T.ok(QuickUI.Cur() == r7)
  click(q.postBtn)
  T.eq(T.count("StartAuction"), 3)
  T.ok(T.calledWith("StartAuction " .. r7.bid * 7 .. " " .. r7.unit * 7 .. " 480"), "the odd 7 as it sits")
  WoW.postRespond()
  T.eq(T.count("QueryAuctionItems"), 0, "no second scan")
  T.eq(QuickUI.Cur(), nil, "nothing left to post")
  T.eq(q.postBtn.enabled, false)
  T.eq(q.summary:GetText(), "3 of 5 posted, " .. A.Util.money(8000 + r20.unit * 27, true))
  T.eq(table.getn(DB.Char().postings), 3, "logged like a Bags post")
end)

T.test("Focus 3: a failed reply marks the row Failed with the reason and moves on", function()
  seed()
  local p, q = scanned()
  local mage, r20 = rowOf(q, "Mageweave Cloth"), rowOf(q, "Runecloth", 20)
  WoW.ah.postReply = "money"
  click(q.postBtn)
  WoW.postRespond()
  T.eq(mage.done, "failed")
  T.eq(statusOf(mage), "Failed: " .. ERR_NOT_ENOUGH_MONEY)
  T.ok(QuickUI.Cur() == r20)
  WoW.ah.postReply = "auto"
  WoW.calls = {}
  click(q.postBtn)
  T.eq(T.count("StartAuction"), 1, "the next click posts the next row")
end)

T.test("Focus 3: a post refused at once (bags changed) marks Failed and moves on, with no StartAuction", function()
  seed()
  local p, q = scanned()
  local mage, r20 = rowOf(q, "Mageweave Cloth"), rowOf(q, "Runecloth", 20)
  WoW.bags[0][3].count = 4
  WoW.calls = {}
  click(q.postBtn)
  T.eq(T.count("StartAuction"), 0)
  T.eq(statusOf(mage), "Failed: Your bags changed. Pick the item again.")
  T.ok(QuickUI.Cur() == r20)
  click(q.postBtn)
  T.eq(T.count("StartAuction"), 1)
end)

T.test("a reply timeout marks the row Failed and the button comes back", function()
  seed()
  local p, q = scanned()
  local mage = rowOf(q, "Mageweave Cloth")
  WoW.ah.postReply = "none"
  click(q.postBtn)
  WoW.postRespond()
  Auction.Tick(WoW.clock + 60)
  T.eq(mage.done, "failed")
  T.eq(q.postBtn.label:GetText(), "POST NEXT")
end)

T.test("Focus 4: vendor rows post only with the box ticked, at vendor x the multiple", function()
  seed()
  local p, q = scanned()
  local linen = rowOf(q, "Linen Cloth")
  T.ok(QuickUI.Cur() ~= linen)
  click(q.vendorSw)
  T.eq(DB.S().sell.quickVendor, true)
  T.ok(QuickUI.Cur() == linen, "the vendor row is now first")
  q.multBox:SetText("5")
  WoW.runScript(q.multBox, "OnTextChanged")
  T.eq(DB.S().sell.vendorMult, 5)
  T.eq(linen.unit, 50)
  T.eq(statusOf(linen), "vendor x5")
  WoW.calls = {}
  click(q.postBtn)
  T.ok(T.calledWith("StartAuction " .. linen.bid * 5 .. " 250 480"), "5 x 50")
  WoW.postRespond()
  T.eq(linen.done, "posted")
  click(q.vendorSw)
  T.eq(DB.S().sell.quickVendor, false)
end)

T.test("changing the multiple keeps the marks and the highlight", function()
  seed()
  local p, q = scanned()
  local mage = rowOf(q, "Mageweave Cloth")
  click(q.postBtn)
  WoW.postRespond()
  local cur = QuickUI.Cur()
  q.multBox:SetText("4")
  WoW.runScript(q.multBox, "OnTextChanged")
  T.eq(mage.done, "posted")
  T.eq(statusOf(rowOf(q, "Mageweave Cloth")), "Posted", "the posted row stays listed")
  T.ok(QuickUI.Cur() == cur)
  T.eq(rowOf(q, "Linen Cloth").unit, 40)
  T.eq(table.getn(q.list.data), 5)
end)

T.test("the Bags view's vendor suggestion uses the same multiple", function()
  seed()
  DB.S().sell.vendorMult = 4
  local p = page()
  click(p.viewBtns.bags)
  for _, c in ipairs(p.cells) do
    if c.item and c.item.name == "Linen Cloth" then click(c) end
  end
  pump()
  T.eq(p.sourceText:GetText(), "vendor x4")
  T.eq(p.buyoutIn:GetValue(), 40)
  TaxTheFoolsCharDB.sellView = "bags"
end)

T.test("Skip marks the row Skipped and moves on; with nothing left Post next is disabled", function()
  seed()
  local p, q = scanned()
  local mage = rowOf(q, "Mageweave Cloth")
  click(q.skipBtn)
  T.eq(mage.done, "skipped")
  T.eq(statusOf(mage), "Skipped")
  T.ok(QuickUI.Cur() == rowOf(q, "Runecloth", 20))
  click(q.skipBtn) click(q.skipBtn)
  T.eq(QuickUI.Cur(), nil)
  T.eq(q.postBtn.enabled, false)
  T.eq(q.skipBtn.enabled, false)
  T.eq(T.count("StartAuction"), 0)
  T.eq(q.summary:GetText(), "0 of 5 posted, 0c")
end)

T.test("clicking a postable row makes it the next; a row that can't post doesn't take the highlight", function()
  seed()
  local p, q = scanned()
  local r7 = rowOf(q, "Runecloth", 7)
  QuickUI.Pick(r7)
  T.ok(QuickUI.Cur() == r7)
  T.ok(q.list.selected == r7)
  QuickUI.Pick(rowOf(q, "Silk Cloth"))
  T.ok(QuickUI.Cur() == r7)
  T.ok(q.list.selected == r7)
  QuickUI.Pick(rowOf(q, "Linen Cloth"))
  T.ok(QuickUI.Cur() == r7, "vendor row with the box off")
  WoW.calls = {}
  click(q.postBtn)
  T.ok(T.calledWith("StartAuction " .. r7.bid * 7 .. " " .. r7.unit * 7 .. " 480"))
  T.eq(T.count("StartAuction"), 1, "picking never posts")
end)

T.test("a row click through the list picks it", function()
  seed()
  local p, q = scanned()
  local target
  for _, row in ipairs(q.list.rows) do
    if row.item and row.item.name == "Runecloth" and row.item.count == 7 then target = row end
  end
  click(target)
  T.ok(QuickUI.Cur() == target.item)
  T.eq(T.count("StartAuction"), 0)
end)

T.test("a rescan clears every mark", function()
  seed()
  local p, q = scanned()
  click(q.skipBtn)
  click(q.postBtn)
  WoW.postRespond()
  click(q.scanBtn)
  pump()
  for _, r in ipairs(q.list.data) do T.eq(r.done, nil) end
  T.eq(QuickUI.Cur().name, "Mageweave Cloth", "the skip is cleared; the posted Runecloth 20 is gone")
  T.eq(q.summary:GetText(), "0 of 4 posted, 0c")
end)

T.test("the duration picker starts at the Sell default and changes only the list", function()
  seed()
  DB.S().sell.duration = 1440
  local p, q = scanned()
  T.eq(q.durBtns[1440].picked, true)
  click(q.durBtns[120])
  T.eq(q.durBtns[120].picked, true)
  T.eq(DB.S().sell.duration, 1440)
  WoW.calls = {}
  click(q.postBtn)
  T.ok(T.calledWith(" 120"), "posted for 6h")
end)

T.test("switching views away and back keeps the list, the marks and the highlight", function()
  seed()
  local p, q = scanned()
  click(q.skipBtn)
  local cur, data = QuickUI.Cur(), q.list.data
  click(p.viewBtns.stock)
  click(p.viewBtns.quick)
  T.ok(QuickUI.Cur() == cur)
  T.eq(rowOf(q, "Mageweave Cloth").done, "skipped")
  T.eq(table.getn(q.list.data), table.getn(data))
end)

T.test("the row tooltip shows the bag item and a failure's full reason", function()
  seed()
  local p, q = scanned()
  local mage = rowOf(q, "Mageweave Cloth")
  WoW.bags[0][3].count = 4
  click(q.postBtn)
  QuickUI.RowTip(q.list.rows[1], mage)
  local all = ""
  for _, l in ipairs(GameTooltip.lines) do all = all .. l[1] .. "|" end
  T.ok(string.find(all, "Your bags changed", 1, true), all)
end)

T.test("nothing in the Quick view's OnUpdate or events posts", function()
  seed()
  local p, q = scanned()
  WoW.calls = {}
  for _ = 1, 20 do
    WoW.clock = WoW.clock + 1
    WoW.runScript(q, "OnUpdate")
    WoW.runScript(TaxTheFoolsCore, "OnUpdate")
  end
  WoW.fire("BAG_UPDATE")
  WoW.fire("PLAYER_MONEY")
  WoW.fire("AUCTION_ITEM_LIST_UPDATE")
  T.eq(T.count("StartAuction"), 0)
  click(q.postBtn)
  WoW.postRespond()
  for _ = 1, 20 do
    WoW.clock = WoW.clock + 1
    WoW.runScript(q, "OnUpdate")
    WoW.runScript(TaxTheFoolsCore, "OnUpdate")
  end
  WoW.fire("BAG_UPDATE")
  T.eq(T.count("StartAuction"), 1, "the reply moves the highlight but never posts")
end)

T.test("the Quick view fits the 660 window: columns, top bar, bottom bar and statuses", function()
  local sum = 0
  for _, c in ipairs(QuickUI.COLUMNS) do sum = sum + c.width end
  T.ok(sum <= 660 - 20 - 12, "columns need " .. sum)
  local w = L.Widths(QuickUI.COLUMNS, 628)
  local statusW = w[table.getn(w)] - 12
  for _, s in ipairs({ "scan for prices", "not scanned", "vendor x10", "at floor", "no price", "Posted", "Skipped", "Failed: " }) do
    T.ok(string.len(s) * 6 <= statusW, s .. " fits " .. statusW)
  end
  local fits = QuickUI.Fits(640)
  T.ok(fits.ok, fits.why)
end)

T.test("Options: the Selling page has the vendor switch and the multiple, with hints", function()
  local Opt = A.Options
  local found = {}
  for _, cat in ipairs(Opt.CATEGORIES) do
    if cat.key == "selling" then
      for _, row in ipairs(cat.rows) do
        if row.path and row.path[2] == "quickVendor" then found.sw = row end
        if row.path and row.path[2] == "vendorMult" then found.mult = row end
      end
    end
  end
  T.eq(found.sw.label, "Include vendor-priced items") T.eq(found.sw.kind, "switch") T.ok(found.sw.hint)
  T.eq(found.mult.label, "Vendor price multiple") T.eq(found.mult.kind, "slider") T.ok(found.mult.hint)
  T.eq(found.mult.min, 1) T.eq(found.mult.fmt(3), "x3")
end)

T.test("an Options change to the multiple re-prices the Quick list", function()
  seed()
  local p, q = scanned()
  local Opt = A.Options
  local row
  for _, cat in ipairs(Opt.CATEGORIES) do
    for _, r in ipairs(cat.rows) do if r.path and r.path[2] == "vendorMult" then row = r end end
  end
  Opt.Set(row, 6)
  T.eq(rowOf(q, "Linen Cloth").unit, 60)
  T.eq(q.multBox:GetText(), "6")
end)

-- The Sell page outlives each test: leave it on Bags for the files that follow.
T.test("cleanup: back to the Bags view", function()
  if UI.pages.sell then StockUI.SetView(UI.pages.sell, "bags") end
  T.eq(UI.pages.sell.view, "bags")
end)
