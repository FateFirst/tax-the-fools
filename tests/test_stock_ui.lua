local A = TaxTheFools
local UI, AH, Scan, DB, Sell = A.UI, A.AH, A.Scan, A.DB, A.Sell
local SellUI, StockUI, L = A.SellUI, A.StockUI, A.List

local NOW = 1700000000

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

-- Runecloth (market 1000) with 20 in the bags, Linen with 5; a hand-made realm with two characters.
local function seed()
  WoW.items[14047] = { name = "Runecloth", stack = 20, quality = 1, tex = "rune" }
  WoW.items[2589] = { name = "Linen Cloth", stack = 20, quality = 1, tex = "linen" }
  DB.Realm().market["14047:0"] = { v = 1000, conf = 0.8 }
  WoW.bags[0] = { { id = 14047, name = "Runecloth", count = 20, vendor = 100 }, { id = 2589, name = "Linen Cloth", count = 5, vendor = 5 }, {}, {} }
  WoW.bags[1], WoW.bags[2], WoW.bags[3], WoW.bags[4] = nil, nil, nil, nil
  WoW.money = 1000000
  TaxTheFoolsCharDB.sellView = "bags"
  local c = DB.Char()
  c.sales, c.postings = {}, {}
  c.bags = { ["14047:0"] = 20, ["2589:0"] = 5 }
  local now = time()
  table.insert(c.sales, { key = "14047:0", outcome = "expired", at = now - 86400 })
  table.insert(c.postings, { key = "14047:0", stack = 5, bid = 4000, buyout = 5000, minutes = 480, at = now - 90000, done = true })
  DB.Realm().chars.Alt = { bags = { ["14047:0"] = 3 }, bank = { ["14047:0"] = 4 }, postings = {
    { key = "14047:0", stack = 2, buyout = 2000 }, { key = "14047:0", stack = 9, buyout = 9000, done = true } } }
end

local function page()
  openAH()
  UI.ah.tabs:Select("sell")
  local p = UI.pages.sell
  p:Refresh()
  return p
end

local function nameRow(rows, name)
  for _, r in ipairs(rows) do if r.name == name then return r end end
end

T.test("the switch remembers the view and a rebuilt page opens on it", function()
  seed()
  local p = page()
  T.eq(p.view, "bags")
  click(p.viewBtns.repost)
  T.eq(p.view, "repost")
  T.eq(TaxTheFoolsCharDB.sellView, "repost")
  click(p.viewBtns.stock)
  T.eq(TaxTheFoolsCharDB.sellView, "stock")
  StockUI.SetView(p, "nonsense")
  T.eq(p.view, "bags")
  TaxTheFoolsCharDB.sellView = "stock"
  local q = SellUI.Build(UI.ah)
  T.eq(q.view, "stock")
  T.ok(q.slist:IsShown())
  SellUI.frame = p
  TaxTheFoolsCharDB.sellView = "bags"
end)

T.test("Repost lists what came back and is in the bags, with last price and change", function()
  seed()
  local p = page()
  click(p.viewBtns.repost)
  T.ok(p.rlist:IsShown() and not p.slist:IsShown())
  T.eq(table.getn(p.rlist.data), 1)
  local r = p.rlist.data[1]
  T.eq(r.name, "Runecloth") T.eq(r.have, 20) T.eq(r.lastStack, 5) T.eq(r.lastBuyout, 1000) T.eq(r.suggest, 1000)
  T.eq(r.change, 0)
  T.ok(not p.empty:IsShown())
  for _, c in ipairs(p.cells) do T.ok(not c:IsShown(), "grid hidden") end
end)

T.test("Repost shows the empty state with the window in days", function()
  seed()
  DB.Char().sales = {}
  DB.S().sell.repostDays = 3
  local p = page()
  click(p.viewBtns.repost)
  T.eq(p.empty:GetText(), "Nothing came back from the auction house in the last 3 days.")
  T.ok(p.empty:IsShown())
  DB.S().sell.repostDays = 7
end)

T.test("clicking a Repost row selects the item and presets the last stack", function()
  seed()
  local p = page()
  click(p.viewBtns.repost)
  click(p.rlist.rows[1])
  T.eq(p.sel.key, "14047:0")
  T.eq(p.stackSize, 5)
  T.eq(p.nStacks, 4)
  T.eq(p.sizeBox:GetText(), "5")
  T.eq(p.countBox:GetText(), "4")
  T.eq(T.count("StartAuction"), 0)
end)

T.test("the stack preset falls back to the default when the bags hold fewer than the last stack", function()
  seed()
  WoW.bags[0][1].count = 3
  local p = page()
  click(p.viewBtns.repost)
  click(p.rlist.rows[1])
  T.eq(p.sel.key, "14047:0")
  T.eq(p.stackSize, 3, "the whole held stack, as the grid would")
  T.eq(p.nStacks, 1)
end)

T.test("the Repost tooltip carries the name, when it came back and both prices", function()
  seed()
  local p = page()
  click(p.viewBtns.repost)
  StockUI.RepostTip(p.rlist.rows[1], p.rlist.data[1])
  local all = ""
  for _, l in ipairs(GameTooltip.lines) do all = all .. l[1] .. "|" end
  T.ok(string.find(all, "Runecloth|", 1, true)) T.ok(string.find(all, "expired", 1, true))
  T.ok(string.find(all, "Last posted: 5 at 10s each", 1, true), all)
  T.ok(string.find(all, "Now: 10s each", 1, true), all)
end)

T.test("Stock rows, totals and the tooltip breakdown", function()
  seed()
  local p = page()
  click(p.viewBtns.stock)
  T.ok(p.slist:IsShown() and not p.rlist:IsShown() and p.totals:IsShown())
  local r = nameRow(p.slist.data, "Runecloth")
  T.eq(r.bags, 23) T.eq(r.bank, 4) T.eq(r.onAH, 2) T.eq(r.total, 29)
  T.eq(r.value, 29000)
  T.eq(p.totals:GetText(), "2 items  -  34 units  -  worth ~3g  (not counting mail)")
  StockUI.StockTip(p.slist.rows[1], r)
  T.eq(GameTooltip.lines[1][1], "Runecloth")
  T.ok(string.find(GameTooltip.lines[2][1], "Alt: bags 3, bank 4, on AH 2", 1, true), GameTooltip.lines[2][1])
  T.ok(string.find(GameTooltip.lines[3][1], "bags 20", 1, true))
  T.ok(string.find(GameTooltip.lines[4][1], "Mail is not counted", 1, true))
end)

T.test("Stock refreshes when the bags change", function()
  seed()
  local p = page()
  click(p.viewBtns.stock)
  WoW.bags[0][2].count = 8
  DB.Char().bags = { ["14047:0"] = 20, ["2589:0"] = 8 }
  SellUI.OnBags()
  T.eq(nameRow(p.slist.data, "Linen Cloth").bags, 8)
end)

T.test("Stock hides the grid and the pricing panel; Bags brings both and the selection back", function()
  seed()
  local p = page()
  click(p.cells[1])
  local sel = p.sel
  T.ok(sel)
  click(p.viewBtns.stock)
  T.ok(not p.cells[1]:IsShown() and not p.postBtn:IsShown() and not p.list:IsShown() and not p.buyoutIn:IsShown()
    and not p.chart:IsShown() and not p.title:IsShown(), "all hidden")
  T.eq(p.sel, sel)
  click(p.viewBtns.bags)
  T.ok(p.cells[1]:IsShown() and p.postBtn:IsShown() and p.list:IsShown() and p.buyoutIn:IsShown() and p.title:IsShown())
  T.eq(p.sel, sel)
  T.ok(string.find(p.title:GetText(), sel.name, 1, true))
  T.ok(p.cells[1].mark:IsShown(), "selection mark")
  T.ok(not p.rlist:IsShown() and not p.slist:IsShown())
  T.eq(T.count("StartAuction"), 0)
end)

T.test("the Repost and Stock columns fit the smallest window", function()
  local sum = 0
  for _, c in ipairs(StockUI.STOCK_COLUMNS) do sum = sum + c.width end
  T.ok(sum <= 660 - 20 - 12, "stock columns need " .. sum)
  sum = 0
  for _, c in ipairs(StockUI.REPOST_COLUMNS) do sum = sum + c.width end
  T.ok(sum <= SellUI.RX - 12 - 12, "repost columns need " .. sum)
  T.ok(L.Widths(StockUI.REPOST_COLUMNS, SellUI.RX - 12 - 12)[1] >= 140, "item column at the minimum")
  T.ok(SellUI.GY + SellUI.ROWS * SellUI.CELL <= 304, "grid no taller than before")
  local w = L.Widths(StockUI.STOCK_COLUMNS, 628)
  local total = 0
  for _, x in ipairs(w) do total = total + x end
  T.eq(total, 628)
end)

T.test("compact money", function()
  T.eq(StockUI.Short(nil), "-")
  T.eq(StockUI.Short(56), "56c") T.eq(StockUI.Short(3400), "34s") T.eq(StockUI.Short(123456), "12.34g")
  T.eq(StockUI.Short(1230000), "123g") T.eq(StockUI.Short(100500), "10.05g")
end)

T.test("opening, switching and clicking never post or split", function()
  seed()
  local p = page()
  click(p.viewBtns.repost) click(p.rlist.rows[1]) click(p.viewBtns.stock) click(p.viewBtns.bags)
  T.eq(T.count("StartAuction"), 0)
  T.eq(T.count("SplitContainerItem"), 0)
end)
