-- the 30-day price chart: widget, Browse and Sell
local A = TaxTheFools
local W, UI, AH, Scan, DB, Browse, SellUI, U = A.Widgets, A.UI, A.AH, A.Scan, A.DB, A.Browse, A.SellUI, A.Util

local function seedHistory(key, ages)
  local e = { days = {}, months = {} }
  for age, p in pairs(ages) do e.days[U.day() - age] = { p25 = p, min = p, n = 5 } end
  DB.Realm().history[key] = e
end

local function series(ages)
  local out = {}
  for age = 29, 0, -1 do
    if ages[age] then table.insert(out, { day = U.day() - age, p25 = ages[age] }) end
  end
  return out
end

T.test("a chart draws one bar per day, today at the right, scaled to the highest price", function()
  local c = W.Chart(UIParent, 302, 62)
  c:SetSeries(series({ [0] = 200, [1] = 100, [29] = 50 }), nil)
  T.ok(c.bars[30]:IsShown() and c.bars[29]:IsShown() and c.bars[1]:IsShown())
  T.eq(c.bars[28]:IsShown(), false, "days without a price have no bar")
  T.eq(c.bars[30].height, 60) T.eq(c.bars[29].height, 30)
  T.ok(c.bars[30].points[1][4] > c.bars[1].points[1][4], "today is to the right")
  T.eq(c.empty:IsShown(), false)
end)

T.test("the marker line sits at the market value and can raise the scale", function()
  local c = W.Chart(UIParent, 302, 62)
  c:SetSeries(series({ [0] = 100 }), 200)
  T.ok(c.marker:IsShown())
  T.eq(c.bars[30].height, 30, "scaled to the marker")
  T.eq(c.marker.points[1][5], 61)
  c:SetSeries(series({ [0] = 100 }), nil)
  T.eq(c.marker:IsShown(), false)
end)

T.test("an empty series hides every bar and says there is no history", function()
  local c = W.Chart(UIParent, 302, 62)
  c:SetSeries(series({ [0] = 100 }), 100)
  c:SetSeries({}, 100)
  for i = 1, 30 do T.eq(c.bars[i]:IsShown(), false) end
  T.eq(c.marker:IsShown(), false)
  T.ok(c.empty:IsShown())
  T.eq(c.empty:GetText(), "No price history yet")
end)

T.test("hovering a bar shows its date and price", function()
  local c = W.Chart(UIParent, 302, 62)
  c:SetSeries(series({ [0] = 12345 }), nil)
  WoW.runScript(c.hits[30], "OnEnter")
  T.eq(GameTooltip.lines[1][1], date("!%d %b", U.day() * 86400))
  T.eq(GameTooltip.lines[2][1], U.money(12345))
  WoW.runScript(c.hits[30], "OnLeave")
  T.eq(GameTooltip:IsShown(), false)
end)

-- ---- Browse ----
local function openAH()
  UI.CreateAH()
  AH.switching = true
  UI.ah:Hide()
  AH.switching = false
  AH.open = true
  AH.ShowOurs()
end

local function browsePage()
  openAH()
  WoW.items[14047] = { name = "Runecloth", stack = 20, quality = 1, tex = "rune" }
  table.insert(WoW.ah.listings, { id = 14047, name = "Runecloth", count = 20, buyout = 12000, minBid = 4500, owner = "Sel" })
  Browse.Search("Rune", 0)
  for _ = 1, 20 do
    WoW.clock = WoW.clock + 0.5
    Scan.Tick(WoW.clock)
    if WoW.ah.pending then WoW.ahRespond() Scan.OnListUpdate(WoW.clock) end
    if not Scan.job then break end
  end
  local p = UI.pages.browse
  p:SetWidth(640) p:SetHeight(360)
  p.list:SetHeight(400)
  return p
end

T.test("Browse shows the chart for the selected row at the default size", function()
  local p = browsePage()
  seedHistory("14047:0", { [0] = 1000, [3] = 900 })
  DB.Realm().market["14047:0"] = { v = 950, conf = 0.8 }
  T.eq(p.chart:IsShown(), false, "nothing selected")
  p.list.selected = p.list.data[1]
  Browse.UpdateBar()
  T.ok(p.chart:IsShown())
  T.ok(p.chart.bars[30]:IsShown() and p.chart.marker:IsShown())
  p.list.selected = false
  Browse.UpdateBar()
  T.eq(p.chart:IsShown(), false)
end)

T.test("Browse hides the chart at the smallest window, never overlapping the Buy and Bid bar", function()
  local p = browsePage()
  p.list.selected = p.list.data[1]
  -- the AH minimum 660x380 leaves about 640x264 for the page
  p:SetWidth(640) p:SetHeight(264)
  Browse.UpdateBar()
  T.ok(p.chart:IsShown(), "still fits")
  local w = p:GetWidth() - Browse.CHART_RIGHT
  T.ok(w >= Browse.CHART_MIN_W and p.chart:GetWidth() + Browse.CHART_RIGHT <= 640, "left of the buttons")
  T.eq(p.chart:GetHeight(), Browse.CHART_H)
  p:SetHeight(Browse.CHART_MIN_PAGE_H - 1)
  Browse.UpdateBar()
  T.eq(p.chart:IsShown(), false, "too short")
  p:SetHeight(264) p:SetWidth(Browse.CHART_RIGHT + Browse.CHART_MIN_W - 1)
  Browse.UpdateBar()
  T.eq(p.chart:IsShown(), false, "too narrow")
  local pt = p.list.points[table.getn(p.list.points)]
  T.eq(pt[5], 32, "the list takes its full height back")
end)

T.test("Browse repaints the list when the chart takes or gives back its height", function()
  local p = browsePage()
  seedHistory("14047:0", { [0] = 1000, [3] = 900 })
  DB.Realm().market["14047:0"] = { v = 950, conf = 0.8 }
  -- the client derives the list's height from its anchors; the stub needs telling
  local setPoint = p.list.SetPoint
  p.list.SetPoint = function(self, pt, rel, rp, x, y)
    setPoint(self, pt, rel, rp, x, y)
    if pt == "BOTTOMRIGHT" then self:SetHeight(p:GetHeight() - 60 - y) end
  end
  local data = {}
  for i = 1, 40 do data[i] = p.list.data[1] end
  p.list:SetData(data)
  local function shown()
    local n = 0
    for _, r in ipairs(p.list.rows) do if r:IsShown() then n = n + 1 end end
    return n
  end
  p.list.rows[1]:Show()
  WoW.runScript(p.list.rows[1], "OnClick")
  T.ok(p.chart:IsShown())
  T.eq(shown(), p.list:Slots(), "rows fit the shortened list")
  p.list.selected = false
  Browse.UpdateBar()
  T.eq(p.chart:IsShown(), false)
  T.eq(shown(), p.list:Slots(), "rows fill the restored list")
end)

-- ---- Sell ----
local function sellPage(height)
  openAH()
  UI.ah.tabs:Select("sell")
  WoW.items[14047] = { name = "Runecloth", stack = 20, quality = 1, tex = "rune" }
  DB.Realm().market["14047:0"] = { v = 1000, conf = 0.8 }
  WoW.bags[0] = { { id = 14047, name = "Runecloth", count = 20, vendor = 100 }, {}, {}, {} }
  WoW.bags[1], WoW.bags[2], WoW.bags[3], WoW.bags[4] = nil, nil, nil, nil
  local p = UI.pages.sell
  p:SetWidth(640) p:SetHeight(height)
  p:Refresh()
  return p
end

T.test("Sell shows the chart at the default size by shortening the competition list", function()
  local p = sellPage(380)
  seedHistory("14047:0", { [0] = 1000, [2] = 800 })
  T.eq(p.chart:IsShown(), false, "nothing selected")
  SellUI.Select(p.items[1])
  T.ok(p.chart:IsShown())
  T.ok(p.chart.bars[30]:IsShown() and p.chart.marker:IsShown())
  T.eq(p.list:GetHeight(), SellUI.LIST_H - SellUI.CHART_H - SellUI.CHART_GAP)
  T.ok(p.list:Slots() >= 3, "three rows left")
  local bottomOfList = SellUI.LIST_Y + p.list:GetHeight()
  T.eq(-p.chart.points[1][5], bottomOfList + SellUI.CHART_GAP, "under the list")
  T.ok(-p.chart.points[1][5] + p.chart:GetHeight() <= 154, "above the Buyout field at y 154")
end)

T.test("Sell hides the chart and restores the list when it would leave under three rows", function()
  local p = sellPage(380)
  SellUI.Select(p.items[1])
  T.ok(p.chart:IsShown())
  local saved = SellUI.LIST_H
  SellUI.LIST_H = 100
  SellUI.UpdateChart()
  T.eq(p.chart:IsShown(), false)
  T.eq(p.list:GetHeight(), 100, "list has its whole height")
  SellUI.LIST_H = saved
  SellUI.UpdateChart()
  T.ok(p.chart:IsShown())
end)

T.test("Sell repaints the list when the chart shortens it", function()
  local p = sellPage(380)
  SellUI.Select(p.items[1])
  local item = p.sel
  p.sel = false
  SellUI.UpdateChart()                              -- the chart is off and the list is tall
  T.eq(p.list:GetHeight(), SellUI.LIST_H)
  local data = {}
  for i = 1, 8 do data[i] = { key = "14047:0", count = 20, buyout = 1000 + i, bid = 1, owner = "x", unit = 50 + i } end
  p.list:SetData(data)
  p.list:Paint()
  local function shown()
    local n = 0
    for _, r in ipairs(p.list.rows) do if r:IsShown() then n = n + 1 end end
    return n
  end
  T.eq(shown(), p.list:Slots())
  p.sel = item
  SellUI.UpdateChart()
  T.ok(p.chart:IsShown())
  T.eq(shown(), p.list:Slots(), "no row below the shortened list")
end)
