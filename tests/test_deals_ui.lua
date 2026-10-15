local A = TaxTheFools
local UI, AH, Scan, DB, Auction, Deals = A.UI, A.AH, A.Scan, A.DB, A.Auction, A.DealsUI

local function openAH()
  UI.CreateAH()
  -- The window outlives WoW.reset(): start every test on Browse, as a fresh open does.
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
  T.eq(UI.TABS[1].key, "deals") T.eq(UI.TABS[2].key, "browse") T.eq(UI.TABS[3].key, "sell") T.eq(UI.TABS[4].key, "auctions") T.eq(UI.TABS[5].key, "history") T.eq(UI.TABS[6].key, "craft")
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

T.test("the minimum confidence setting (Options page) filters the list", function()
  seed()
  local p = page()
  DB.Realm().market["14047:0"].conf = 0.5
  p:Refresh()
  T.eq(table.getn(p.list.data), 3)
  DB.S().deals.minConfidence = 0.7
  A.DealsUI.Paint()
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

local function startFind()
  seedPages()
  local p = page()
  p.list.selected = p.list.data[1]
  A.DealsUI.UpdateBar()
  WoW.runScript(p.findBtn, "OnClick")
  T.ok(p.searching)
  return p
end

local function interrupted(p)
  T.eq(p.searching, false)
  T.ok(string.find(p.status:GetText(), "Search interrupted. Press Find again.", 1, true), p.status:GetText())
  T.eq(p.findBtn.enabled, true)
  T.eq(p.findBtn.label:GetText(), "FIND")
  T.eq(types(p), "market:11000,market:6000,vendor:100", "the deal is still listed")
  T.eq(DB.Realm().snapshot.rows["14047:0"][1], "20|8000|0|Deal")
  T.eq(T.count("PlaceAuctionBid"), 0)
end

T.test("a Find interrupted by Scan.Pause reports back and can be retried", function()
  local p = startFind()
  Scan.Pause("user")
  interrupted(p)
end)

T.test("a Find interrupted by closing the auction house reports back", function()
  local p = startFind()
  AH.OnClosed()
  interrupted(p)
end)

T.test("a stuck searching flag clears itself when no scan is running", function()
  seedPages()
  local p = page()
  p.list.selected = p.list.data[1]
  p.searching = true
  A.DealsUI.UpdateBar()
  T.eq(p.searching, false)
  T.eq(p.findBtn.enabled, true)
end)

local function found()
  seedPages()
  local p = page()
  p.list.selected = p.list.data[1]
  A.DealsUI.UpdateBar()
  WoW.runScript(p.findBtn, "OnClick")
  answer()
  return p
end

T.test("a Buy refused after the list was replaced goes back to Find, and Find works again", function()
  local p = found()
  T.eq(p.findBtn.label:GetText(), string.upper("Buy " .. A.Util.money(8000)))
  -- another query replaced the client's list since the Find (no repaint: the page is not the one showing)
  WoW.ah.current = { { id = 2589, name = "Linen Cloth", count = 1, buyout = 5, owner = "X" } }
  WoW.runScript(p.findBtn, "OnClick")
  T.eq(T.count("PlaceAuctionBid"), 0)
  T.ok(string.find(p.status:GetText(), "Press Find again", 1, true), p.status:GetText())
  T.eq(p.findBtn.label:GetText(), "FIND")
  T.ok(p.findBtn.enabled)
  WoW.runScript(p.findBtn, "OnClick")
  answer()
  -- (the second scan re-estimates the market, which may reshuffle the list; Find itself worked)
  T.ok(string.find(p.status:GetText(), "Found on page 2", 1, true), p.status:GetText())
  T.ok(p.found)
end)

T.test("a sniped deal: ERR_ITEM_NOT_FOUND removes it from the list and snapshot", function()
  local p = found()
  WoW.ah.bidReply = "notfound"
  WoW.runScript(p.findBtn, "OnClick")
  T.eq(T.count("PlaceAuctionBid"), 1)
  WoW.bidRespond()
  T.ok(string.find(p.status:GetText(), "Gone: someone else bought it.", 1, true), p.status:GetText())
  T.eq(types(p), "market:6000,vendor:100")
  T.eq(DB.Realm().snapshot.rows["14047:0"][1], "20|13000|0|Other")
  T.eq(p.findBtn.label:GetText(), "FIND")
  WoW.ah.bidReply = "auto"
end)

T.test("another failed buy goes back to Find and keeps the deal", function()
  local p = found()
  WoW.ah.bidReply = "money"
  WoW.runScript(p.findBtn, "OnClick")
  WoW.bidRespond()
  T.eq(p.findBtn.label:GetText(), "FIND")
  T.eq(types(p), "market:11000,market:6000,vendor:100")
  T.eq(DB.Realm().snapshot.rows["14047:0"][1], "20|8000|0|Deal")
  WoW.ah.bidReply = "auto"
end)

T.test("a failed buy confirmed in the window also reports back to Find", function()
  local p = found()
  DB.S().buy.confirmAbove = 5000
  WoW.runScript(p.findBtn, "OnClick")
  T.eq(T.count("PlaceAuctionBid"), 0, "the window comes first")
  WoW.ah.bidReply = "money"
  A.Confirm.Buy()
  WoW.bidRespond()
  T.eq(p.findBtn.label:GetText(), "FIND")
  WoW.ah.bidReply = "auto"
  DB.S().buy.confirmAbove = 50000
end)

-- ---------- undersupplied deals (phase 4) ----------
-- Runecloth 14047:0 held 5 (bag), market 1000, 1 listing in the snapshot (the 20|8000 deal group is
-- replaced), median 6 listings, 4 results of which 3 sold (rate 0.75).
-- suggest = floor(max(1000, 400) * 110/100) = 1100; profit = 5 * 1100 * 0.95 = 5225.
local function seedUnder()
  local realm = DB.Realm()
  realm.market["14047:0"] = { v = 1000, conf = 0.8 }
  A.Items.Remember(14047, "Runecloth", 1, 20)
  realm.snapshot = { at = time(), day = A.Util.day(time()), rows = { ["14047:0"] = { "1|400|0|Bob" } } }
  local today = A.Util.day(time())
  realm.history["14047:0"] = { days = { [today - 1] = { p25 = 1000, n = 6 }, [today - 2] = { p25 = 1000, n = 6 },
                                         [today - 3] = { p25 = 1000, n = 6 } } }
  realm.chars[DB.charName] = realm.chars[DB.charName] or {}
  local c = realm.chars[DB.charName]
  c.bags = { ["14047:0"] = 5 }
  c.sales = {}
  local out = { "sold", "sold", "sold", "expired" }
  for i = 1, 4 do table.insert(c.sales, { key = "14047:0", outcome = out[i], money = 1000, at = time() - 3600 }) end
end

local function underPage()
  seedUnder()
  local p = page()
  return p
end

local function underRow(p)
  for i, d in ipairs(p.list.data) do if d.type == "under" then return i, d end end
end

T.test("an undersupplied item shows as an Under row with its profit", function()
  local p = underPage()
  local i, d = underRow(p)
  T.ok(i, "Under row present")
  T.eq(d.typeLabel, "Under") T.eq(d.suggest, 1100) T.eq(d.held, 5) T.near(d.profit, 5225, 0.001)
  T.eq(p.list.rows[i].cells[8]:GetText(), "Under")
end)

T.test("the Deals rail has the Under switch but not the underPct and premiumPct sliders (I2)", function()
  local p = underPage()
  T.ok(p.underSw)
  T.eq(rawget(p, "underSl"), nil) T.eq(rawget(p, "premiumSl"), nil)
end)

T.test("the Under switch and the underPct and premiumPct settings (Options page) refresh the list", function()
  local p = underPage()
  T.ok(underRow(p))
  WoW.runScript(p.underSw, "OnClick")
  T.eq(DB.S().deals.under, false)
  T.eq(underRow(p), nil)
  WoW.runScript(p.underSw, "OnClick")
  T.ok(underRow(p))
  DB.S().deals.underPct = 10
  A.DealsUI.Paint()
  -- 1 listing of a median 6 is 16.7%: over 10%, so the row goes.
  T.eq(underRow(p), nil)
  DB.S().deals.underPct = 33
  DB.S().deals.premiumPct = 150
  A.DealsUI.Paint()
  local _, d = underRow(p)
  T.eq(d.suggest, 1500)          -- floor(1000 * 150/100)
  DB.S().deals.premiumPct = 110
end)

T.test("Sell on an Under deal for an item that is not in the bags says where it is (M4)", function()
  local p = underPage()
  WoW.items[14047] = { name = "Runecloth", stack = 20, quality = 1, tex = "rune" }
  WoW.bags[0] = { {}, {}, {} }
  local _, ud = underRow(p)
  p.list.selected = ud
  A.DealsUI.UpdateBar()
  WoW.runScript(p.findBtn, "OnClick")
  T.eq(UI.ah.tabs.selected, "sell")
  T.eq(A.SellUI.frame.status:GetText(), "Not in your bags (it's in the bank or on another character).")
  T.ok(not A.SellUI.frame.sel)
  T.eq(T.count("PlaceAuctionBid"), 0) T.eq(T.count("StartAuction"), 0)
  UI.ah.tabs:Select("deals")
end)

T.test("Sell on an Under deal switches to the Sell tab and selects it, with no buy call", function()
  local p = underPage()
  WoW.items[14047] = { name = "Runecloth", stack = 20, quality = 1, tex = "rune" }
  WoW.bags[0] = { { id = 14047, name = "Runecloth", count = 20, vendor = 100 }, {}, {} }
  local _, ud = underRow(p)
  p.list.selected = ud
  A.DealsUI.UpdateBar()
  T.eq(p.findBtn.label:GetText(), "SELL")
  WoW.runScript(p.findBtn, "OnClick")
  T.eq(UI.ah.tabs.selected, "sell")
  T.ok(A.SellUI.frame.sel)
  T.eq(A.SellUI.frame.sel.key, "14047:0")
  T.eq(T.count("PlaceAuctionBid"), 0) T.eq(T.count("QueryAuctionItems"), 0)
  T.eq(T.count("StartAuction"), 0)
  UI.ah.tabs:Select("deals")
end)

-- ---------- recipe deals (phase 5a) ----------
-- Pattern 600 teaches Robe (skill 40, product 500, one Thread 300 at 200): 750 a craft. Listed at
-- 2000 it pays back in 3 crafts (profit 750*10-2000 = 5500, over the default minimum). The current character is a tailor of rank 50 who hasn't learned it.
local function seedRecipe()
  local realm = DB.Realm()
  realm.market["500:0"] = { v = 1000, conf = 0.8 }
  realm.market["300:0"] = { v = 200, conf = 0.8 }
  A.Items.Remember(600, "Pattern: Robe", 1, 1)
  A.Items.Remember(500, "Robe", 1, 1)
  A.Items.Remember(300, "Thread", 1, 20)
  realm.snapshot = { at = time(), day = A.Util.day(time()), rows = { ["600:0"] = { "1|2000|0|Seller" } } }
  realm.chars[DB.charName] = realm.chars[DB.charName] or {}
  realm.chars[DB.charName].professions = { Tailoring = { rank = 50, recipes = {} } }
  A.RecipeData = { Tailoring = { [900] = { n = "Robe", skill = 40, item = 500, pat = { 600 }, src = { "drop" }, r = { 300, 1 } } } }
  WoW.money = 1000000
  table.insert(WoW.ah.listings, { id = 600, name = "Pattern: Robe", count = 1, buyout = 2000, owner = "Seller" })
end

local savedData = A.RecipeData
local function recipeRow(p)
  for i, d in ipairs(p.list.data) do if d.type == "recipe" then return i, d end end
end

T.test("a pattern that pays back shows as a Recipe row with its payback text", function()
  seedRecipe()
  local p = page()
  local i, d = recipeRow(p)
  T.ok(i, "Recipe row present")
  T.eq(d.typeLabel, "Recipe") T.eq(d.payback, 3) T.eq(d.crafter, A.DB.charName) T.eq(d.profit, 5500)
  T.eq(p.list.rows[i].cells[8]:GetText(), "Recipe")
  T.eq(Deals.RecipeText(d), "Pays back in 3 crafts for Robe")
  T.eq(Deals.RecipeText({ payback = 1, recipe = "Robe" }), "Pays back in 1 craft for Robe")
  A.RecipeData = savedData
end)

T.test("the Deals rail has the Recipe switch and no payback slider; it drives the list", function()
  seedRecipe()
  local p = page()
  T.ok(p.recipeSw)
  T.eq(rawget(p, "paybackSl"), nil)
  T.ok(recipeRow(p))
  WoW.runScript(p.recipeSw, "OnClick")
  T.eq(DB.S().deals.recipe, false)
  T.eq(recipeRow(p), nil)
  WoW.runScript(p.recipeSw, "OnClick")
  T.ok(recipeRow(p))
  DB.S().deals.paybackCrafts = 2
  A.DealsUI.Paint()
  T.eq(recipeRow(p), nil, "3 crafts is not under a limit of 2")
  DB.S().deals.paybackCrafts = 10
  A.RecipeData = savedData
end)

T.test("a Recipe deal goes through Find then Buy, with one PlaceAuctionBid on the Buy click", function()
  seedRecipe()
  local p = page()
  local _, d = recipeRow(p)
  p.list.selected = d
  A.DealsUI.UpdateBar()
  T.eq(p.findBtn.label:GetText(), "FIND")
  WoW.runScript(p.findBtn, "OnClick")
  answer()
  T.ok(string.find(p.status:GetText(), "Found on page 1", 1, true), p.status:GetText())
  T.eq(p.findBtn.label:GetText(), string.upper("Buy " .. A.Util.money(2000)))
  T.eq(T.count("PlaceAuctionBid"), 0, "finding never buys")
  WoW.runScript(p.findBtn, "OnClick")
  T.eq(T.count("PlaceAuctionBid"), 1)
  A.RecipeData = savedData
end)

T.test("the Deals rail fits the body at the minimum window height", function()
  local p = page()
  -- body at minH 380: 380 - header 30 - tabs 29 - status strip 38 - top gap 8 - bottom 22 = 253
  local available = 380 - 30 - 29 - 38 - 8 - 22
  local used = 0
  used = used + p.marketSw:GetHeight() + 2 + p.vendorSw:GetHeight() + 2 + p.matsSw:GetHeight() + 2
  used = used + p.underSw:GetHeight() + 2 + p.recipeSw:GetHeight() + 14
  used = used + p.belowSl:GetHeight() + 8 + p.profitSl:GetHeight()
  T.ok(used <= available, used .. " > " .. available)
  T.eq(rawget(p, "matSl"), nil) T.eq(rawget(p, "confDD"), nil)
end)
