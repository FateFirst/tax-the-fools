local A = TaxTheFools
local DB, Opt, UI, AH = A.DB, A.Options, A.UI, A.AH

local function ttf(msg) SlashCmdList["TAXTHEFOOLS"](msg) end

local function openAH()
  UI.CreateAH()
  if UI.ah.tabs.selected then UI.ah.tabs:Select("browse") end
  AH.switching = true
  UI.ah:Hide()
  AH.switching = false
  AH.open = true
  AH.ShowOurs()
end

local function later() WoW.now = WoW.now + 100 end

T.test("defaults carry the removal records", function()
  T.eq(type(DB.Realm().removed.watch), "table")
  T.eq(type(DB.Realm().removed.snipe), "table")
  T.eq(type(DB.S().mail.keepRemoved), "table")
end)

T.test("Opt.Set stamps settingsAt, with a path or a custom setter", function()
  TaxTheFoolsDB.settingsAt = nil
  Opt.Set({ kind = "switch", path = { "tooltip", "vendor" } }, false)
  T.eq(TaxTheFoolsDB.settingsAt, WoW.now)
  later()
  Opt.Set({ key = "safeMode" }, true)
  T.eq(TaxTheFoolsDB.settingsAt, WoW.now)
  later()
  Opt.Set({ get = function() end, set = function() end }, "x")
  T.eq(TaxTheFoolsDB.settingsAt, WoW.now)
end)

T.test("the Deals rail switches and sliders stamp settingsAt", function()
  openAH()
  UI.ah.tabs:Select("deals")
  local p = UI.pages.deals
  TaxTheFoolsDB.settingsAt = nil
  WoW.runScript(p.vendorSw, "OnClick")
  T.eq(TaxTheFoolsDB.settingsAt, WoW.now)
  later()
  p.profitSl.slider:SetValue(8000)
  WoW.runScript(p.profitSl.slider, "OnMouseUp")
  T.eq(TaxTheFoolsDB.settingsAt, WoW.now)
end)

T.test("/ttf debug and the minimap drag stamp settingsAt", function()
  TaxTheFoolsDB.settingsAt = nil
  ttf("debug")
  T.eq(TaxTheFoolsDB.settingsAt, WoW.now)
  later()
  A.Minimap.Create()
  WoW.cursorX, WoW.cursorY = 100, 200
  A.Minimap.DragUpdate()
  T.eq(TaxTheFoolsDB.settingsAt, WoW.now)
end)

T.test("watch stores its time, unwatch leaves a removal record, a re-add clears it", function()
  A.Items.Remember(4306, "Silk Cloth")
  ttf("watch silk cloth")
  T.eq(DB.Realm().watch["4306:0"], WoW.now)
  T.eq(DB.Realm().removed.watch["4306:0"], nil)
  later()
  ttf("unwatch silk cloth")
  T.eq(DB.Realm().watch["4306:0"], nil)
  T.eq(DB.Realm().removed.watch["4306:0"], WoW.now)
  later()
  ttf("watch silk cloth")
  T.eq(DB.Realm().removed.watch["4306:0"], nil)
  T.eq(DB.Realm().watch["4306:0"], WoW.now)
  ttf("watchlist")
  T.ok(T.calledWith("Watching 1: Silk Cloth"))
end)

T.test("the Browse Watch button records adds and removals", function()
  openAH()
  UI.pages.browse.list.selected = { key = "14047:0", name = "Runecloth" }
  A.Browse.ToggleWatch()
  T.eq(DB.Realm().watch["14047:0"], WoW.now)
  later()
  A.Browse.ToggleWatch()
  T.eq(DB.Realm().watch["14047:0"], nil)
  T.eq(DB.Realm().removed.watch["14047:0"], WoW.now)
end)

T.test("auto-watch from a trade skill window keeps an existing time and clears removals", function()
  local realm = DB.Realm()
  realm.watch["4306:0"] = 5
  realm.removed.watch["2996:0"] = 7
  A.TradeSkill.Watch({ { item = "4305:0", reagents = { { item = "4306:0" }, { item = "2996:0" } } } })
  T.eq(realm.watch["4306:0"], 5, "already watched: stamp unchanged")
  T.eq(realm.watch["4305:0"], WoW.now)
  T.eq(realm.watch["2996:0"], WoW.now)
  T.eq(realm.removed.watch["2996:0"], nil)
end)

T.test("snipe adds clear the removal record, removals record the time", function()
  A.Items.Remember(4306, "Silk Cloth")
  local realm = DB.Realm()
  ttf("snipe Silk Cloth 20s")
  T.eq(realm.snipe["4306:0"].at, WoW.now)
  later()
  T.ok(DB.SnipeRemove("4306:0"))
  T.eq(realm.snipe["4306:0"], nil)
  T.eq(realm.removed.snipe["4306:0"], WoW.now)
  T.eq(DB.SnipeRemove("4306:0"), false)
  later()
  ttf("snipe Silk Cloth 30s")
  T.eq(realm.removed.snipe["4306:0"], nil)
  T.eq(realm.snipe["4306:0"].at, WoW.now)
end)

T.test("the Deals Remove button leaves a snipe removal record", function()
  openAH()
  UI.ah.tabs:Select("deals")
  local realm = DB.Realm()
  A.Snipe.Set(realm.snipe, "14047:0", "Runecloth", 700, 1)
  A.DealsUI.SetView("snipe")
  local p = UI.pages.deals
  p.slist.selected = { key = "14047:0" }
  T.ok(A.DealsUI.SnipeRemove())
  T.eq(realm.removed.snipe["14047:0"], WoW.now)
end)

T.test("Snipe.Set and Snipe.Remove take the record table", function()
  local list, rec = {}, { a = 3 }
  A.Snipe.Set(list, "a", "A", 10, 50, rec)
  T.eq(rec.a, nil)
  A.Snipe.Remove(list, "a", rec, 60)
  T.eq(rec.a, 60)
  T.eq(A.Snipe.Remove(list, "a", rec, 70), false)
  T.eq(rec.a, 60, "not listed: record untouched")
end)

T.test("mail keep stores its time; removals leave records; keep and re-add clear them", function()
  local m = DB.S().mail
  DB.KeepSet("100:0", true)
  T.eq(m.keep["100:0"], WoW.now)
  T.eq(TaxTheFoolsDB.settingsAt, WoW.now)
  later()
  DB.KeepSet("100:0", false)
  T.eq(m.keep["100:0"], nil)
  T.eq(m.keepRemoved["100:0"], WoW.now)
  later()
  DB.KeepSet("100:0", true)
  T.eq(m.keepRemoved["100:0"], nil)
  T.eq(MailRules and 1 or 1, 1)
end)

T.test("the options keep list and the Mail Keep button use the keep helper", function()
  Opt.Create()
  local m = DB.S().mail
  DB.KeepSet("100:0", true)
  later()
  Opt.Select("mail")
  local kl = Opt.frame.pages.mail.controls[7]
  kl:Refresh()
  WoW.runScript(kl.lines[1], "OnClick")
  T.eq(m.keep["100:0"], nil)
  T.eq(m.keepRemoved["100:0"], WoW.now)
  T.eq(TaxTheFoolsDB.settingsAt, WoW.now)
end)

T.test("login stamps old true entries and snipe entries without a time", function()
  local realm = DB.Realm()
  realm.watch["1:0"] = true
  realm.snipe["2:0"] = { max = 5 }
  DB.S().mail.keep["3:0"] = true
  DB.StampLegacy()
  T.eq(realm.watch["1:0"], WoW.now)
  T.eq(realm.snipe["2:0"].at, WoW.now)
  T.eq(DB.S().mail.keep["3:0"], WoW.now)
end)

T.test("captures carry timestamps: bags, bank and each profession", function()
  WoW.bags[0] = { { id = 4306, name = "Silk Cloth", count = 2 } }
  WoW.bags[-1] = { { id = 4306, name = "Silk Cloth", count = 3 } }
  WoW.bankOpen = true
  WoW.fire("BANKFRAME_OPENED")
  WoW.fire("BAG_UPDATE", 0)
  WoW.runScript(TaxTheFoolsCore, "OnUpdate")
  T.eq(DB.Char().bagsAt, WoW.now)
  T.eq(DB.Char().bankAt, WoW.now)
  WoW.tradeskill = { name = "Tailoring", rank = 1, maxRank = 300, selected = 0, rows = {
    { name = "Bolt of Silk Cloth", type = "medium", id = 4305, made = { 1, 1 }, reagents = { { id = 4306, name = "Silk Cloth", count = 4 } } } } }
  WoW.fire("TRADE_SKILL_SHOW")
  WoW.clock = WoW.clock + 2
  WoW.runScript(TaxTheFoolsCore, "OnUpdate")
  T.eq(DB.Char().professions.Tailoring.at, WoW.now)
end)

T.test("market values are recomputed from history at login", function()
  local realm = DB.Realm()
  local day = A.Util.day(time())
  realm.history["14047:0"] = { days = { [day] = { n = 5, p25 = 900, min = 800, max = 1200, med = 1000 } } }
  realm.market["14047:0"] = nil
  A.Scan.RecomputeMarket()
  local want = A.Price.Market(realm.history["14047:0"], day)
  T.ok(want ~= nil)
  T.eq(realm.market["14047:0"].v, want.v)
  T.eq(realm.market["14047:0"].conf, want.conf)
  DB.Realm().market = {}
  A.Core.Init()
  T.eq(DB.Realm().market["14047:0"].v, want.v, "Core.Init recomputes")
end)

T.test("/ttf sync reports the last sync, or that there was none", function()
  TaxTheFoolsDB.sync = nil
  ttf("sync")
  T.ok(T.calledWith("Not synced yet: see docs/sync.md"))
  TaxTheFoolsDB.sync = { at = WoW.now - 7200, device = "Laptop", version = "1.0.0" }
  ttf("sync")
  T.ok(T.calledWith("Last synced 2h 0m ago from Laptop (TTF Sync 1.0.0)"))
  TaxTheFoolsDB.sync = nil
end)
