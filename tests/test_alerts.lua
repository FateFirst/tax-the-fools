local A, UI, Scan, DB, I = TaxTheFools, TaxTheFools.UI, TaxTheFools.Scan, TaxTheFools.DB, TaxTheFools.Items
local Al = A.Alerts

local function ctxWith(market)
  local ctx = A.TradeSkill.Context()
  ctx.market = market or {}
  return ctx
end

local S = { on = true, minProfit = 10000, sound = true, snipe = true }

T.test("a snipe match alerts once per session, with chat and a sound", function()
  I.Remember(4306, "Silk Cloth")
  DB.Realm().snipe = { ["4306:0"] = { max = 2000, name = "Silk Cloth", at = 1 } }
  local rows = { { key = "4306:0", qty = 20, buyout = 36000, unit = 1800, owner = "Bob" } }
  local out = Al.Check(rows, ctxWith(), S, 100)
  T.eq(table.getn(out), 1) T.eq(out[1].kind, "snipe")
  T.ok(T.calledWith("Snipe: Silk Cloth x20 at 18s each (max 20s)"), "chat")
  T.eq(T.count("PlaySound TellMessage"), 1)
  T.eq(table.getn(Al.Check(rows, ctxWith(), S, 200)), 0)
  T.eq(T.count("PlaySound TellMessage"), 1)
end)

T.test("a listing over the snipe max, or your own, does not alert", function()
  DB.Realm().snipe = { ["4306:0"] = { max = 2000, name = "Silk Cloth", at = 1 } }
  local rows = { { key = "4306:0", qty = 1, buyout = 2001, unit = 2001, owner = "Bob" },
                 { key = "4306:0", qty = 1, buyout = 100, unit = 100, owner = DB.charName } }
  T.eq(table.getn(Al.Check(rows, ctxWith(), S, 100)), 0)
end)

T.test("a deal alerts only at or above the minimum profit", function()
  I.Remember(14047, "Runecloth")
  local market = { ["14047:0"] = { v = 1000, conf = 1 } }
  local rows = { { key = "14047:0", qty = 20, buyout = 8000, unit = 400, owner = "Bob" } }
  local out = Al.Check(rows, ctxWith(market), S, 100)
  T.eq(table.getn(out), 1) T.eq(out[1].kind, "deal")
  T.ok(T.calledWith("Deal: Runecloth x20 for 80s"), "chat")
  Al.ResetState()
  local lo = { on = true, minProfit = 1000000, sound = true, snipe = true }
  T.eq(table.getn(Al.Check(rows, ctxWith(market), lo, 100)), 0)
end)

T.test("alerts off, snipe off and sound off are honoured", function()
  DB.Realm().snipe = { ["4306:0"] = { max = 2000, name = "Silk Cloth", at = 1 } }
  local rows = { { key = "4306:0", qty = 1, buyout = 100, unit = 100, owner = "Bob" } }
  T.eq(table.getn(Al.Check(rows, ctxWith(), { on = false, snipe = true }, 100)), 0)
  T.eq(table.getn(Al.Check(rows, ctxWith(), { on = true, snipe = false, minProfit = 10000 }, 100)), 0)
  Al.ResetState()
  T.eq(table.getn(Al.Check(rows, ctxWith(), { on = true, snipe = true, sound = false }, 100)), 1)
  T.eq(T.count("PlaySound"), 0)
end)

T.test("the sound is throttled to once every 5 seconds", function()
  DB.Realm().snipe = { ["4306:0"] = { max = 2000, name = "Silk Cloth", at = 1 } }
  Al.Check({ { key = "4306:0", qty = 1, buyout = 100, unit = 100, owner = "A" } }, ctxWith(), S, 100)
  Al.Check({ { key = "4306:0", qty = 1, buyout = 101, unit = 101, owner = "A" } }, ctxWith(), S, 103)
  T.eq(T.count("PlaySound"), 1)
  Al.Check({ { key = "4306:0", qty = 1, buyout = 102, unit = 102, owner = "A" } }, ctxWith(), S, 106)
  T.eq(T.count("PlaySound"), 2)
end)

T.test("a scan page fires Scan.OnRows listeners with that page's listings, Browse included", function()
  local got = {}
  Scan.OnRows(function(rows) table.insert(got, table.getn(rows)) end)
  for i = 1, 60 do
    table.insert(WoW.ah.listings, { id = 14047, name = "Runecloth", count = 1, buyout = 100 + i, owner = "S" })
  end
  T.ok(Scan.Browse("Rune", 0, WoW.clock))
  for _ = 1, 10 do
    WoW.clock = WoW.clock + 0.5
    Scan.Tick(WoW.clock)
    if WoW.ah.pending then WoW.ahRespond() Scan.OnListUpdate(WoW.clock) end
  end
  T.eq(got[table.getn(got)], 50)
  T.ok(table.getn(got) >= 1)
end)

T.test("Scan.MatsQueries lists every reagent on the realm, plus the shopping buys, sorted", function()
  I.Remember(4306, "Silk Cloth")
  DB.Realm().chars.Tailor = { professions = { Tailoring = { recipes = {
    Bolt = { item = "1:0", reagents = { { item = "4306:0", name = "x", count = 2 }, { name = "Thread", count = 1 } } } } } } }
  TaxTheFools.CraftUI.shopping = { buys = { { name = "Wool", source = "ah" }, { name = "Vial", source = "vendor" } } }
  local q = Scan.MatsQueries()
  TaxTheFools.CraftUI.shopping = nil
  local names = {}
  for _, e in ipairs(q) do table.insert(names, e.name) end
  T.eq(table.concat(names, ","), "Silk Cloth,Thread,Wool")
  DB.Realm().chars.Tailor = nil
  T.eq(table.getn(Scan.MatsQueries()), 0)
end)

T.test("Scan.SnipeQueries lists snipe names; empty lists refuse to start", function()
  DB.Realm().snipe = { ["4306:0"] = { max = 1, name = "Silk Cloth" }, ["2:0"] = { max = 1, name = "Linen" } }
  T.eq(Scan.SnipeQueries()[1].name, "Linen")
  T.eq(table.getn(Scan.SnipeQueries()), 2)
  DB.Realm().snipe = {}
  local ok, why = Scan.StartSnipe(WoW.clock)
  T.eq(ok, false) T.eq(why, "empty")
end)

T.test("mats and snipe scans record history like watch, and the paused text names the kind", function()
  I.Remember(14047, "Runecloth")
  DB.Realm().snipe = { ["14047:0"] = { max = 1, name = "Runecloth" } }
  for i = 1, 5 do table.insert(WoW.ah.listings, { id = 14047, name = "Runecloth", count = 1, buyout = 100 + i, owner = "S" }) end
  T.ok(Scan.StartSnipe(WoW.clock))
  for _ = 1, 20 do
    WoW.clock = WoW.clock + 0.5
    Scan.Tick(WoW.clock)
    if WoW.ah.pending then WoW.ahRespond() Scan.OnListUpdate(WoW.clock) end
  end
  T.ok(Scan.job == nil)
  T.eq(DB.Realm().history["14047:0"].days[20375].src, "snipe")
  local d = UI.Describe(nil, { kind = "mats", page = 0, rows = {} }, nil, WoW.now)
  T.ok(string.find(d.text, "Paused materials scan", 1, true), d.text)
  d = UI.Describe(nil, { kind = "snipe", page = 0, rows = {} }, nil, WoW.now)
  T.ok(string.find(d.text, "Paused snipe scan", 1, true), d.text)
end)

T.test("the Quick scan menu offers three scans with counts and starts the chosen one", function()
  UI.CreateAH()
  UI.ah:Show()
  DB.Realm().snipe = {}
  UI.ToggleQuickMenu()
  T.ok(UI.quickMenu:IsShown())
  T.ok(string.find(UI.quickMenu.items[3].text:GetText(), "Snipe list (0)", 1, true))
  WoW.runScript(UI.quickMenu.items[3], "OnClick")
  T.eq(UI.quickMenu:IsShown(), false)
  T.ok(T.calledWith("Your snipe list is empty"), "empty message")
  UI.StartScan("mats")
  T.ok(T.calledWith("Nothing to scan: no recipes captured yet"), "mats message")
end)

T.test("alerts never buy, bid, post or cancel", function()
  DB.Realm().snipe = { ["4306:0"] = { max = 2000, name = "Silk Cloth", at = 1 } }
  Al.Check({ { key = "4306:0", qty = 1, buyout = 100, unit = 100, owner = "A" } }, ctxWith(), S, 100)
  T.ok(not T.calledWith("PlaceAuctionBid"))
  T.ok(not T.calledWith("StartAuction"))
  T.ok(not T.calledWith("CancelAuction"))
end)
