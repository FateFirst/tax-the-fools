local DB = TaxTheFools.DB

T.test("a fresh install gets every default", function()
  T.eq(TaxTheFoolsDB.dataVersion, 1)
  T.eq(DB.S().scanDelay, 0.3)
  T.eq(DB.S().tooltip.market, true)
  T.eq(type(TaxTheFoolsCharDB.windows), "table")
end)

T.test("existing choices survive and new defaults fill in", function()
  TaxTheFoolsDB = { dataVersion = 1, settings = { scanDelay = 1, tooltip = { vendor = false } } }
  DB.Init()
  T.eq(DB.S().scanDelay, 1)
  T.eq(DB.S().tooltip.vendor, false)
  T.eq(DB.S().tooltip.market, true, "new nested default added")
  T.eq(DB.S().safeMode, false)
end)

T.test("an unreadable saved table is set aside, not merged into", function()
  TaxTheFoolsDB = { settings = 5 }
  DB.Init()
  T.ok(DB.wasBroken)
  T.eq(TaxTheFoolsDB_broken[WoW.now].settings, 5)
  T.eq(type(DB.S()), "table")
  TaxTheFoolsDB = "garbage"
  DB.Init()
  T.eq(TaxTheFoolsDB_broken[WoW.now], "garbage")
end)

T.test("realm and character tables are created once", function()
  local r = DB.Realm()
  T.eq(type(r.history), "table") T.eq(type(r.watch), "table")
  T.eq(DB.Realm(), r)
  T.eq(TaxTheFoolsDB.realms.Medivh, r)
  T.eq(DB.Char().class, "WARRIOR")
  T.eq(r.chars.Bankalt, DB.Char())
end)

T.test("pruning runs a few items per step and removes emptied entries", function()
  local r = DB.Realm()
  local today = 20375
  r.history["1:0"] = { days = { [today] = { p25 = 10 } }, months = {} }
  r.history["2:0"] = { days = { [today - 400] = { n = 1 } }, months = {} }
  r.history["3:0"] = { days = { [today - 70] = { p25 = 30, n = 1 } }, months = {} }
  r.market["2:0"] = { v = 1 }
  DB.StartPrune()
  T.eq(DB.PruneStep(2, today), false, "three entries, budget two")
  T.eq(DB.PruneStep(2, today), true)
  T.eq(r.history["2:0"], nil, "empty entry removed")
  T.eq(r.market["2:0"], nil, "and its market value")
  T.ok(r.history["1:0"].days[today], "recent kept")
  T.eq(next(r.history["3:0"].days), nil, "old day folded")
  T.ok(next(r.history["3:0"].months), "into a month")
  T.eq(DB.PruneStep(2, today), true, "nothing to do afterwards")
end)

T.test("pruning survives entries added between steps", function()
  local r = DB.Realm()
  for i = 1, 10 do r.history[i .. ":0"] = { days = { [20375] = { p25 = i } }, months = {} } end
  DB.StartPrune()
  DB.PruneStep(3, 20375)
  for i = 11, 200 do r.history[i .. ":0"] = { days = { [20375] = { p25 = i } }, months = {} } end
  local done = false
  for _ = 1, 10 do done = DB.PruneStep(3, 20375) if done then break end end
  T.ok(done, "finishes the snapshot it started with")
end)

T.test("size text counts what is stored", function()
  local r = DB.Realm()
  TaxTheFoolsDB.items[1] = { n = "x" }
  r.history["1:0"] = { days = { [20375] = {}, [20374] = {} }, months = {} }
  local s = DB.SizeText()
  T.ok(string.find(s, "1 items known", 1, true), s)
  T.ok(string.find(s, "2 daily rows", 1, true), s)
end)

T.test("wipe starts again from defaults", function()
  DB.S().scanDelay = 2
  DB.Wipe()
  T.eq(DB.S().scanDelay, 0.3)
end)
