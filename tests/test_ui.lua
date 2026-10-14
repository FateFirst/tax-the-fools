local UI, Browse, AH, Scan, DB = TaxTheFools.UI, TaxTheFools.Browse, TaxTheFools.AH, TaxTheFools.Scan, TaxTheFools.DB

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

T.test("durations read naturally", function()
  T.eq(UI.Duration(45), "45s")
  T.eq(UI.Duration(1320), "22m")
  T.eq(UI.Duration(3900), "1h 5m")
  T.eq(UI.Duration(90000), "1d 1h")
end)

T.test("an idle strip says when the last full scan ran", function()
  local d = UI.Describe(nil, nil, nil, WoW.now)
  T.ok(string.find(d.text, "No full scan yet", 1, true), d.text)
  T.ok(d.canStart) T.eq(d.pause, false)
  d = UI.Describe(nil, nil, WoW.now - 7200, WoW.now)
  T.eq(d.text, "Last full scan 2h 0m ago")
end)

T.test("a running full scan shows the page, pace and time left", function()
  local d = UI.Describe({ kind = "full", state = "wait", page = 2, totalPages = 10, qi = 1, nq = 1, listings = 100,
    safe = false, secsPerPage = 5, eta = 40 }, nil, nil, WoW.now)
  T.ok(string.find(d.text, "page 3/10", 1, true), d.text)
  T.ok(string.find(d.text, "5.0s/page", 1, true), d.text)
  T.ok(string.find(d.text, "~40s left", 1, true), d.text)
  T.eq(d.pause, "Pause") T.eq(d.canStart, false)
  T.near(d.fraction, 0.2, 0.001)
end)

T.test("a stalled scan offers to try again", function()
  local d = UI.Describe({ kind = "watch", state = "stalled", page = 0, qi = 2, nq = 5, listings = 0, safe = false },
    nil, nil, WoW.now)
  T.ok(string.find(d.text, "server not responding", 1, true), d.text)
  T.eq(d.pause, "Resume")
end)

T.test("a paused scan offers resume or discard", function()
  local d = UI.Describe(nil, { kind = "full", page = 4, rows = { "a", "b" } }, nil, WoW.now)
  T.ok(string.find(d.text, "page 5", 1, true), d.text)
  T.eq(d.pause, "Resume") T.ok(d.discard) T.eq(d.canStart, false)
end)

T.test("browse rows get market value and percent of market", function()
  DB.Realm().market["1:0"] = { v = 400 }
  local rows = Browse.Decorate({ { key = "1:0", unit = 300 }, { key = "2:0", unit = 5 }, { key = "1:0" } }, DB.Realm().market)
  T.eq(rows[1].pct, 75) T.eq(rows[2].pct, nil) T.eq(rows[3].pct, nil)
  T.eq(Browse.PctToken(70), "good") T.eq(Browse.PctToken(130), "bad")
  T.eq(Browse.PctToken(100), "text") T.eq(Browse.PctToken(nil), "dim")
end)

T.test("opening the AH shows our window on the Browse tab with your gold", function()
  WoW.money = 123456
  openAH()
  T.ok(UI.ah:IsShown())
  T.eq(UI.ah.tabs.selected, "browse")
  T.ok(UI.pages.browse:IsShown())
  T.ok(string.find(UI.ah.gold:GetText(), "12g", 1, true))
end)

T.test("a search fills the list with market percentages", function()
  openAH()
  table.insert(WoW.ah.listings, { id = 14047, name = "Runecloth", count = 20, buyout = 6000 })
  DB.Realm().market["14047:0"] = { v = 400 }
  T.ok(Browse.Search("Rune", 0))
  answer()
  local data = UI.pages.browse.list.data
  T.eq(table.getn(data), 1)
  T.eq(data[1].pct, 75)
  T.ok(string.find(UI.pages.browse.pageText:GetText(), "1 found", 1, true))
end)

T.test("watch toggles the selected row's item", function()
  openAH()
  table.insert(WoW.ah.listings, { id = 14047, name = "Runecloth", count = 20, buyout = 6000 })
  Browse.Search("Rune", 0)
  answer()
  local p = UI.pages.browse
  p.list.selected = p.list.data[1]
  Browse.ToggleWatch()
  T.ok(DB.Realm().watch["14047:0"])
  T.eq(p.watchBtn.label:GetText(), "UNWATCH")
  Browse.ToggleWatch()
  T.eq(DB.Realm().watch["14047:0"], nil)
end)

T.test("searching during a scan is refused and the strip shows the scan", function()
  openAH()
  for i = 1, 120 do table.insert(WoW.ah.listings, { id = 14047, name = "Runecloth", count = 1, buyout = 100 + i }) end
  UI.StartScan("full")
  T.eq(Browse.Search("Rune", 0), false)
  T.ok(T.calledWith("Pause it to search"))
  UI.RefreshStatus()
  T.eq(UI.ah.status.full.enabled, false)
  T.eq(UI.ah.status.pause.label:GetText(), "PAUSE")
end)

T.test("hovering a Browse row puts the item tooltip at the cursor, not past the row's far end", function()
  local row = CreateFrame("Button")
  Browse.RowTip(row, { link = WoW.link(14047, "Runecloth") })
  T.eq(GameTooltip.owner, row)
  T.eq(GameTooltip.anchor, "ANCHOR_CURSOR")
end)
