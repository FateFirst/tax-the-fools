local A = TaxTheFools
local UI, AH, Scan, DB, Auction, Deals = A.UI, A.AH, A.Scan, A.DB, A.Auction, A.DealsUI

local function openAH()
  UI.CreateAH()
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

-- Runecloth (14047): market 1000. Linen (2589): vendor 500.
--   20 for 8000 (40%, profit 20000*0.95-8000 = 11000), 20 for 13000 (65%, profit 6000),
--   1 for 600 (60%, profit 350), Linen 1 for 400 (vendor, profit 100).
local function seed(day)
  local realm = DB.Realm()
  realm.market["14047:0"] = { v = 1000, conf = 0.8 }
  A.Items.Remember(14047, "Runecloth", 1, 20)
  A.Items.Remember(2589, "Linen Cloth", 1, 20).v = 500
  realm.snapshot = { at = time(), day = day or A.Util.day(time()), rows = {
    ["14047:0"] = { "20|8000|0|Deal", "20|13000|0|Other", "1|600|0|Cheap" },
    ["2589:0"] = { "1|400|0|Vend" },
  } }
end

local function page()
  openAH()
  UI.ah.tabs:Select("deals")
  local p = UI.pages.deals
  p.found, p.searching = false, false      -- the page outlives WoW.reset() between tests
  p.list:SetHeight(300)
  p:Refresh()
  return p
end

local function types(p)
  local t = {}
  for _, d in ipairs(p.list.data) do table.insert(t, d.type .. ":" .. d.profit) end
  return table.concat(t, ",")
end

T.test("Deals is the first tab and registered as a builder", function()
  T.eq(UI.TABS[1].key, "deals") T.eq(UI.TABS[2].key, "browse") T.eq(UI.TABS[3].key, "craft")
  T.ok(UI.builders.deals)
end)

T.test("Browse is still the tab selected on open", function()
  openAH()
  T.eq(UI.ah.tabs.selected, "browse")
end)

T.test("rows come from the seeded snapshot, best profit first, with defaults applied", function()
  seed()
  local p = page()
  -- defaults: min profit 5000, so the 350 market deal is out; vendor profit has no minimum.
  T.eq(types(p), "market:11000,market:6000,vendor:100")
  T.eq(p.list.data[1].name, "Runecloth")
  T.near(p.list.data[1].pct, 40, 0.001)
end)

T.test("switching off vendor removes vendor deals", function()
  seed()
  local p = page()
  WoW.runScript(p.vendorSw, "OnClick")
  T.eq(DB.S().deals.vendor, false)
  T.eq(types(p), "market:11000,market:6000")
end)

T.test("raising the minimum profit removes the small ones", function()
  seed()
  local p = page()
  p.profitSl.slider:SetValue(8000)
  WoW.runScript(p.profitSl.slider, "OnMouseUp")
  T.eq(DB.S().deals.minProfit, 8000)
  T.eq(types(p), "market:11000,vendor:100")
  p.profitSl.slider:SetValue(0)
  WoW.runScript(p.profitSl.slider, "OnMouseUp")
  T.eq(types(p), "market:11000,market:6000,market:350,vendor:100")
end)

T.test("the confidence dropdown sets the minimum confidence", function()
  seed()
  local p = page()
  DB.Realm().market["14047:0"].conf = 0.5
  p:Refresh()
  T.eq(table.getn(p.list.data), 3)
  WoW.runScript(p.confDD.menu.items[3], "OnClick")       -- high = 0.7
  T.eq(DB.S().deals.minConfidence, 0.7)
  T.eq(types(p), "vendor:100")
end)

T.test("the banner says no scan, a fresh scan, and a stale scan", function()
  local p = page()
  T.eq(p.banner:GetText(), "No scan yet. Run a full scan.")
  seed()
  p:Refresh()
  T.eq(p.banner:GetText(), "Deals from a scan today")
  seed(A.Util.day(time()) - 1)
  p:Refresh()
  T.eq(p.banner:GetText(), "Deals from a scan 1 day ago")
  seed(A.Util.day(time()) - 3)
  p:Refresh()
  T.eq(p.banner:GetText(), "Deals are from a scan 3 days ago. Run a full scan for fresh deals.")
end)

T.test("a deal with no market value shows a dash instead of a percent", function()
  seed()
  local p = page()
  local row
  for i, d in ipairs(p.list.data) do if d.type == "vendor" then row = i end end
  T.eq(p.list.rows[row].cells[6]:GetText(), "-")
end)

-- 60 other Runecloth listings come first, so the deal sits on the second page.
local function seedPages()
  seed()
  WoW.money = 1000000
  for i = 1, 60 do
    table.insert(WoW.ah.listings, { id = 14047, name = "Runecloth", count = 20, buyout = 20000 + i, owner = "S" .. i })
  end
  table.insert(WoW.ah.listings, { id = 14047, name = "Runecloth", count = 20, buyout = 8000, owner = "Deal" })
end

T.test("Find locates a listing on page 2 and Buy makes exactly one PlaceAuctionBid", function()
  seedPages()
  local p = page()
  p.list.selected = p.list.data[1]
  A.DealsUI.UpdateBar()
  T.eq(p.findBtn.label:GetText(), "FIND")
  WoW.runScript(p.findBtn, "OnClick")
  answer()
  T.ok(string.find(p.status:GetText(), "Found on page 2", 1, true), p.status:GetText())
  T.eq(p.findBtn.label:GetText(), string.upper("Buy " .. A.Util.money(8000)))
  T.eq(T.count("PlaceAuctionBid"), 0, "finding never buys")
  WoW.runScript(p.findBtn, "OnClick")
  T.eq(T.count("PlaceAuctionBid"), 1)
  T.ok(T.calledWith("PlaceAuctionBid list 11 8000"))
end)

T.test("Find on a gone listing removes the row and never bids", function()
  seedPages()
  table.remove(WoW.ah.listings)              -- sold since the scan
  local p = page()
  p.list.selected = p.list.data[1]
  A.DealsUI.UpdateBar()
  WoW.runScript(p.findBtn, "OnClick")
  answer()
  T.ok(string.find(p.status:GetText(), "Gone", 1, true), p.status:GetText())
  T.eq(T.count("PlaceAuctionBid"), 0)
  T.eq(types(p), "market:6000,vendor:100")
  T.eq(DB.Realm().snapshot.rows["14047:0"][1], "20|13000|0|Other")
end)

T.test("Find is refused during a full scan and leaves the scan running", function()
  seedPages()
  local p = page()
  p.list.selected = p.list.data[1]
  A.DealsUI.UpdateBar()
  T.ok(Scan.StartFull(WoW.clock))
  WoW.runScript(p.findBtn, "OnClick")
  T.ok(T.calledWith("A scan is using the auction house. Pause it to search."))
  T.eq(Scan.job.kind, "full")
  T.eq(T.count("QueryAuctionItems"), 0)
  T.eq(T.count("PlaceAuctionBid"), 0)
end)

T.test("a Find that no longer matches the page refuses to buy", function()
  seedPages()
  local p = page()
  p.list.selected = p.list.data[1]
  A.DealsUI.UpdateBar()
  WoW.runScript(p.findBtn, "OnClick")
  answer()
  -- another search replaces the list before the click
  WoW.ah.listings = { { id = 2589, name = "Linen Cloth", count = 1, buyout = 5, owner = "X" } }
  A.Scan.Browse("Linen", 0, WoW.clock)
  answer()
  WoW.runScript(p.findBtn, "OnClick")
  T.eq(T.count("PlaceAuctionBid"), 0)
end)

T.test("Find with nothing selected does nothing", function()
  seedPages()
  local p = page()
  p.list.selected = false
  A.DealsUI.UpdateBar()
  WoW.runScript(p.findBtn, "OnClick")
  T.eq(T.count("QueryAuctionItems"), 0)
end)

-- The AH window outlives WoW.reset(): leave it on Browse, as test_ui.lua expects.
T.test("leave the window on the Browse tab", function()
  openAH()
  UI.ah.tabs:Select("browse")
  T.eq(UI.ah.tabs.selected, "browse")
end)
